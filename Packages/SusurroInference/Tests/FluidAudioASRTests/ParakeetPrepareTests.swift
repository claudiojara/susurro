import Domain
import Testing

@testable import FluidAudioASR

@Suite("Parakeet model readiness", .timeLimit(.minutes(1)))
struct ParakeetPrepareTests {
    /// Reads published readiness values up to and including the first one that satisfies `isLast`.
    private static func read(
        _ changes: inout AsyncStream<RecognizerReadiness>.Iterator,
        through isLast: (RecognizerReadiness) -> Bool
    ) async -> [RecognizerReadiness] {
        var seen: [RecognizerReadiness] = []
        while let readiness = await changes.next() {
            seen.append(readiness)
            if isLast(readiness) { break }
        }
        return seen
    }

    @Test("a model that has not started loading reads as loading, not as missing")
    func loadingBeforePrepare() async {
        let recognizer = ParakeetRecognizer(engine: FakeParakeetEngine())

        #expect(await recognizer.readiness() == .loading(progress: 0))
    }

    @Test("transcribing is refused until the model is loaded")
    func refusedUntilReady() async throws {
        let engine = FakeParakeetEngine(loads: [.init(gated: true)])
        let recognizer = ParakeetRecognizer(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount)

        await #expect(throws: RecognitionError.notReady) {
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
        await recognizer.prepare()
        await #expect(throws: RecognitionError.notReady) {
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(engine.transcriptions.isEmpty)

        engine.releaseLoad()
        await recognizer.waitUntilReady()
        let transcript = try await recognizer.transcribe(clip, options: RecognitionOptions())
        #expect(transcript == RawTranscript(text: "samples:\(clip.samples.count)"))
    }

    @Test("prepare starts one load, however often it is called")
    func prepareIsIdempotent() async {
        let engine = FakeParakeetEngine(loads: [.init(gated: true)])
        let recognizer = ParakeetRecognizer(engine: engine)

        await recognizer.prepare()
        await recognizer.prepare()
        engine.releaseLoad()
        await recognizer.waitUntilReady()
        await recognizer.prepare()

        #expect(engine.loadCount == 1)
        #expect(await recognizer.readiness() == .ready)
    }

    @Test("readiness follows the load from not installed through progress to ready")
    func readinessFollowsTheLoad() async {
        let engine = FakeParakeetEngine(loads: [.init(progress: [0.25, 0.5], gated: true)])
        let recognizer = ParakeetRecognizer(engine: engine)
        var changes = await recognizer.readinessChanges().makeAsyncIterator()

        await recognizer.prepare()
        let whileLoading = await Self.read(&changes) { $0 == .loading(progress: 0.5) }
        #expect(await recognizer.readiness() == .loading(progress: 0.5))
        engine.releaseLoad()
        let finished = await Self.read(&changes) { $0 == .ready }

        #expect(
            whileLoading == [.loading(progress: 0), .loading(progress: 0.25), .loading(progress: 0.5)]
        )
        #expect(finished == [.ready])
    }

    @Test("a subscriber that arrives late starts from the current readiness")
    func lateSubscriberSeesTheCurrentValue() async {
        let recognizer = ParakeetRecognizer(engine: FakeParakeetEngine())
        await recognizer.prepare()
        await recognizer.waitUntilReady()

        var changes = await recognizer.readinessChanges().makeAsyncIterator()

        #expect(await changes.next() == .ready)
    }

    @Test("progress never goes backward and stays below complete until the load returns")
    func progressOnlyAdvances() async {
        let fractions = [0.2, 0.9, 0.5, 1.0, 0.4, 1.0]
        let engine = FakeParakeetEngine(loads: [.init(progress: fractions)])
        let recognizer = ParakeetRecognizer(engine: engine)
        var changes = await recognizer.readinessChanges().makeAsyncIterator()

        await recognizer.prepare()
        let seen = await Self.read(&changes) { $0 == .ready }

        #expect(
            seen == [
                .loading(progress: 0), .loading(progress: 0.2), .loading(progress: 0.9), .loading(progress: 0.99),
                .ready,
            ]
        )
    }

    @Test(
        "load progress keeps the highest fraction, in steps, and caps it below complete",
        arguments: [
            ([0.1, 0.3, 0.2], [0.1, 0.3]),
            ([0.5, 1.0, 0.5, 1.0], [0.5, 0.99]),
            ([Double.nan, 0.4, -1, 2], [0.4, 0.99]),
            // A download reports thousands of tiny steps. Only a step of a hundredth or more is worth publishing.
            ([0.004, 0.009, 0.012, 0.015, 0.025], [0.012, 0.025]),
        ]
    )
    func loadProgressObserve(fractions: [Double], advances: [Double]) {
        var progress = LoadProgress()

        let reported = fractions.compactMap { progress.observe($0) }

        #expect(reported == advances)
    }
}
