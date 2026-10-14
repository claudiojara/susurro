import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Overlapping dictations", .timeLimit(.minutes(1)))
struct OverlappingDictationTests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime
    private static let first = DictationCoordinatorTests.audio(0.1)
    private static let second = DictationCoordinatorTests.audio(0.7)

    /// Presses, speaks and releases a second dictation while the first is still being processed.
    private static func dictateSecond(_ h: inout Harness) async {
        await h.sut.handle(.down(at: pressTime + .milliseconds(1300)))
        h.capture.emit(AudioChunk(samples: second))
        _ = await h.read(through: .recording(.hold))
        await h.sut.handle(.up(at: pressTime + .milliseconds(2500)))
    }

    @Test("a dictation spoken while another is processed is inserted after it, and each has its own record")
    func firstThenSecond() async throws {
        let recognizer = FakeRecognizer(transcripts: ["uno", "dos"], gated: true)
        var h = await Harness(recognizer: recognizer)
        await h.startProcessing()
        await Self.dictateSecond(&h)
        recognizer.releaseTranscription()
        recognizer.releaseTranscription()
        let rest = await h.read(through: .idle)

        #expect(h.inserter.insertedTexts == ["uno", "dos"])
        #expect(recognizer.transcribedClips == [AudioClip(samples: Self.first), AudioClip(samples: Self.second)])
        #expect(rest.filter { $0 == .inserted }.count == 2)
        #expect(h.capture.startCount == 2)
        let records = try await h.history.page(offset: 0, limit: 10)
        #expect(Set(records.map(\.id)).count == 2)
        #expect(records.map(\.status) == [.succeeded, .succeeded])
        #expect(Set(records.compactMap(\.rawText)) == ["uno", "dos"])
    }

    @Test("a press while a dictation is processed starts a recording at once, and the dictation carries on")
    func pressWhileProcessing() async {
        let recognizer = FakeRecognizer(transcripts: ["uno", "dos"], gated: true)
        var h = await Harness(recognizer: recognizer)
        await h.startProcessing()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))

        #expect(h.capture.startCount == 2)
        #expect(await h.read(through: .starting) == [.starting])
        h.capture.emit(AudioChunk(samples: Self.second))
        _ = await h.read(through: .recording(.hold))
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(2500)))
        recognizer.releaseTranscription()
        recognizer.releaseTranscription()
        _ = await h.read(through: .idle)

        #expect(h.inserter.insertedTexts == ["uno", "dos"])
    }

    @Test("while the next dictation is recorded, the result of the earlier one shows and the recording comes back")
    func resultDoesNotHideTheRecording() async {
        let recognizer = FakeRecognizer(transcripts: ["uno", "dos"], gated: true)
        var h = await Harness(recognizer: recognizer)
        await h.startProcessing()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        h.capture.emit(AudioChunk(samples: Self.second))
        _ = await h.read(through: .recording(.hold))
        recognizer.releaseTranscription()

        #expect(await h.read(through: .recording(.hold)) == [.inserted, .recording(.hold)])
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(2500)))
        recognizer.releaseTranscription()
        _ = await h.read(through: .idle)
        #expect(h.inserter.insertedTexts == ["uno", "dos"])
    }

    @Test("a press while the text is being inserted starts the next recording")
    func pressWhileInserting() async {
        let inserter = FakeTextInserter(gated: true)
        var h = await Harness(inserter: inserter)
        await h.startRecording()
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(1200)))
        await inserter.entered.wait()
        await Self.dictateSecond(&h)
        inserter.releaseInsertion()
        inserter.releaseInsertion()
        _ = await h.read(through: .idle)

        #expect(h.capture.startCount == 2)
        #expect(h.inserter.insertedTexts.count == 2)
    }

}
