import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing

@Suite("Chunked transcriber", .timeLimit(.minutes(1)))
struct ChunkedTranscriberTests {
    private static let rate = AudioClip.sampleRate

    /// 2.5 s of audio whose seconds have the values 1, 2 and 3 (the last half), so a piece says which one it is. The
    /// limit of 1 s cuts it into three pieces.
    private static let clip = AudioClip(
        samples: [Float](repeating: 1, count: rate) + [Float](repeating: 2, count: rate)
            + [Float](repeating: 3, count: rate / 2))
    private static let limit = Duration.seconds(1)

    private static func label(of piece: AudioClip) -> String {
        ["", "uno", "dos", "tres"][Int(piece.samples[0])]
    }

    private struct Failure: Error {}

    @Test("the pieces are joined in order even when they finish in another order")
    func joinedInOrder() async throws {
        let first = Gate()
        let sut = ChunkedTranscriber(limit: Self.limit, concurrency: 3)
        let transcript = try await sut.transcribe(Self.clip) { piece in
            // The first piece waits until the other two are done.
            if Self.label(of: piece) == "uno" {
                await first.wait()
            } else if Self.label(of: piece) == "tres" {
                first.open()
            }
            return RawTranscript(text: Self.label(of: piece))
        }

        #expect(transcript.text == "uno dos tres")
    }

    @Test("with one piece at a time the pieces are transcribed in order")
    func sequential() async throws {
        let order = Mutex<[String]>([])
        let sut = ChunkedTranscriber(limit: Self.limit)
        let transcript = try await sut.transcribe(Self.clip) { piece in
            order.withLock { $0.append(Self.label(of: piece)) }
            return RawTranscript(text: Self.label(of: piece))
        }

        #expect(order.withLock { $0 } == ["uno", "dos", "tres"])
        #expect(transcript.text == "uno dos tres")
    }

    @Test("a clip within the limit, or with no limit, is transcribed whole in one call")
    func oneCall() async throws {
        let calls = Mutex<[AudioClip]>([])
        for limit in [Duration?.none, .seconds(10)] {
            let transcript = try await ChunkedTranscriber(limit: limit).transcribe(Self.clip) { piece in
                calls.withLock { $0.append(piece) }
                return RawTranscript(text: "todo")
            }
            #expect(transcript.text == "todo")
        }

        #expect(calls.withLock { $0 } == [Self.clip, Self.clip])
    }

    @Test("blank pieces add nothing to the text")
    func blankPieces() async throws {
        let transcript = try await ChunkedTranscriber(limit: Self.limit).transcribe(Self.clip) { piece in
            RawTranscript(text: Self.label(of: piece) == "dos" ? "  " : " \(Self.label(of: piece)) ")
        }

        #expect(transcript.text == "uno tres")
    }

    @Test("cancelling during a piece starts no further piece")
    func cancellationStopsFurtherPieces() async {
        let started = Mutex(0)
        let entered = Gate()
        let hold = Gate()
        let sut = ChunkedTranscriber(limit: Self.limit)
        let work = Task {
            try await sut.transcribe(Self.clip) { piece in
                started.withLock { $0 += 1 }
                entered.open()
                await hold.wait()  // returns when the task is cancelled
                try Task.checkCancellation()
                return RawTranscript(text: Self.label(of: piece))
            }
        }
        await entered.wait()
        work.cancel()
        let result = await work.result

        #expect(started.withLock { $0 } == 1)
        if case .failure(let error) = result {
            #expect(error is CancellationError)
        } else {
            Issue.record("a cancelled transcription returned a text")
        }
    }

    @Test("a piece that fails fails the clip, and the pieces after it are not started")
    func failure() async {
        let started = Mutex(0)
        let sut = ChunkedTranscriber(limit: Self.limit)

        await #expect(throws: Failure.self) {
            try await sut.transcribe(Self.clip) { piece in
                started.withLock { $0 += 1 }
                if Self.label(of: piece) == "uno" { throw Failure() }
                return RawTranscript(text: "x")
            }
        }
        #expect(started.withLock { $0 } == 1)
    }
}
