import CoreTestSupport
import Domain
import Testing

@testable import FluidAudioASR

@Suite("Parakeet serializes inference", .timeLimit(.minutes(1)))
struct ParakeetSerializationTests {
    private static func clip(samples count: Int) -> AudioClip {
        AudioClip(samples: [Float](repeating: 0.1, count: count))
    }

    private static func transcribe(
        _ recognizer: ParakeetRecognizer,
        samples count: Int
    ) -> Task<RawTranscript, any Error> {
        Task { try await recognizer.transcribe(clip(samples: count), options: RecognitionOptions()) }
    }

    /// Waits until exactly `count` transcriptions are queued behind the one running. Returns false if that does not
    /// happen within ten seconds, so a regression fails instead of hanging.
    private static func waitForQueue(_ recognizer: ParakeetRecognizer, count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while await recognizer.queuedTranscriptions != count {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            await Task.yield()
        }
        return true
    }

    private static func readyRecognizer(_ engine: FakeParakeetEngine) async -> ParakeetRecognizer {
        let recognizer = ParakeetRecognizer(engine: engine)
        await recognizer.prepare()
        await recognizer.waitUntilReady()
        return recognizer
    }

    @Test("overlapping transcriptions run one at a time, in the order they arrived")
    func oneAtATimeInOrder() async throws {
        let engine = FakeParakeetEngine(gatedTranscription: true)
        let recognizer = await Self.readyRecognizer(engine)

        let first = Self.transcribe(recognizer, samples: 5_000)
        await engine.entered.wait()
        let second = Self.transcribe(recognizer, samples: 6_000)
        try #require(await Self.waitForQueue(recognizer, count: 1))
        let third = Self.transcribe(recognizer, samples: 7_000)
        try #require(await Self.waitForQueue(recognizer, count: 2))
        for _ in 0..<3 { engine.releaseTranscription() }

        let texts = try await [first.value, second.value, third.value].map(\.text)
        #expect(texts == ["samples:5000", "samples:6000", "samples:7000"])
        #expect(engine.transcriptions.map(\.samples.count) == [5_000, 6_000, 7_000])
        #expect(engine.peakActiveTranscriptions == 1)
    }

    @Test("a cancelled transcription leaves the queue at once and the next one still runs")
    func cancelledWaiterLeavesTheQueue() async throws {
        let engine = FakeParakeetEngine(gatedTranscription: true)
        let recognizer = await Self.readyRecognizer(engine)

        let first = Self.transcribe(recognizer, samples: 5_000)
        await engine.entered.wait()
        let second = Self.transcribe(recognizer, samples: 6_000)
        try #require(await Self.waitForQueue(recognizer, count: 1))
        let third = Self.transcribe(recognizer, samples: 7_000)
        try #require(await Self.waitForQueue(recognizer, count: 2))

        second.cancel()
        try #require(await Self.waitForQueue(recognizer, count: 1))
        await #expect(throws: CancellationError.self) { try await second.value }

        for _ in 0..<2 { engine.releaseTranscription() }
        #expect(try await first.value.text == "samples:5000")
        #expect(try await third.value.text == "samples:7000")
        #expect(engine.transcriptions.map(\.samples.count) == [5_000, 7_000])
    }
}
