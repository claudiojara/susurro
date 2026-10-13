import Domain
import Testing

@testable import FluidAudioASR

@Suite("Parakeet mapping", .timeLimit(.minutes(1)))
struct ParakeetMappingTests {
    private struct Failure: Error, Equatable {
        let reason: String
    }

    private static func clip(samples count: Int) -> AudioClip {
        AudioClip(samples: (0..<count).map { Float($0 % 100) / 100 })
    }

    private static func readyRecognizer(_ engine: FakeParakeetEngine) async -> ParakeetRecognizer {
        let recognizer = ParakeetRecognizer(engine: engine)
        await recognizer.prepare()
        await recognizer.waitUntilReady()
        return recognizer
    }

    @Test(
        "an engine state maps to the readiness the port reports",
        arguments: [
            (ModelState.notLoaded, RecognizerReadiness.notInstalled),
            (.loading(progress: 0.4), .loading(progress: 0.4)),
            (.ready, .ready),
            (.failed, .notInstalled),
        ]
    )
    func engineStatesMapToReadiness(state: ModelState, readiness: RecognizerReadiness) {
        #expect(state.readiness == readiness)
    }

    @Test(
        "the whole clip reaches the engine unchanged, however long",
        arguments: [4_800, 70_000, 320_000, 960_000]
    )
    func wholeClipReachesTheEngine(count: Int) async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await Self.readyRecognizer(engine)
        let clip = Self.clip(samples: count)

        let transcript = try await recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(engine.transcriptions == [.init(samples: clip.samples, language: nil)])
        #expect(transcript == RawTranscript(text: "samples:\(count)"))
    }

    @Test("a clip shorter than the engine accepts is a blank transcript, not an error")
    func shortClipIsBlank() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await Self.readyRecognizer(engine)

        let transcript = try await recognizer.transcribe(Self.clip(samples: 4_799), options: RecognitionOptions())

        #expect(transcript == RawTranscript(text: ""))
        #expect(engine.transcriptions.isEmpty)
    }

    @Test(
        "the language is automatic unless it is pinned",
        arguments: [(String?.none, String?.none), ("es", "es"), ("en", "en")]
    )
    func languageIsPassedThrough(pinned: String?, expected: String?) async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await Self.readyRecognizer(engine)

        _ = try await recognizer.transcribe(Self.clip(samples: 5_000), options: RecognitionOptions(language: pinned))

        #expect(engine.transcriptions.map(\.language) == [expected])
    }

    @Test("vocabulary terms are ignored without an error")
    func vocabularyIsIgnored() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await Self.readyRecognizer(engine)
        let clip = Self.clip(samples: 5_000)
        let terms = ["Susurro", "FluidAudio", "Parakeet", "Xcode", "Claudio"]

        let plain = try await recognizer.transcribe(clip, options: RecognitionOptions())
        let biased = try await recognizer.transcribe(clip, options: RecognitionOptions(vocabulary: terms))

        #expect(biased == plain)
        #expect(engine.transcriptions.count == 2)
        #expect(engine.transcriptions[0] == engine.transcriptions[1])
    }

    @Test("an engine error becomes a recognition error", arguments: ["boom", "model is corrupt"])
    func engineErrorIsWrapped(reason: String) async {
        let engine = FakeParakeetEngine(respond: { _ in throw Failure(reason: reason) })
        let recognizer = await Self.readyRecognizer(engine)

        await #expect(throws: RecognitionError.engineFailed(String(describing: Failure(reason: reason)))) {
            try await recognizer.transcribe(Self.clip(samples: 5_000), options: RecognitionOptions())
        }
    }

    @Test("cancelling a transcription in the engine ends it with a cancellation, not a recognition error")
    func cancellationReachesTheEngine() async {
        let engine = FakeParakeetEngine(gatedTranscription: true)
        let recognizer = await Self.readyRecognizer(engine)
        let clip = Self.clip(samples: 5_000)
        let task = Task { try await recognizer.transcribe(clip, options: RecognitionOptions()) }
        await engine.entered.wait()

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.transcriptions.count == 1)
    }

    @Test("a transcription that starts cancelled never reaches the engine")
    func cancelledBeforeTheEngine() async {
        let engine = FakeParakeetEngine()
        let recognizer = await Self.readyRecognizer(engine)
        let clip = Self.clip(samples: 5_000)
        let start = Gate()
        let task = Task {
            await start.wait()
            return try await recognizer.transcribe(clip, options: RecognitionOptions())
        }

        task.cancel()
        start.open()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.transcriptions.isEmpty)
    }

    @Test("transcribing is refused until the model is loaded")
    func refusedUntilReady() async throws {
        let engine = FakeParakeetEngine(loads: [.init(gated: true)])
        let recognizer = ParakeetRecognizer(engine: engine)
        let clip = Self.clip(samples: 5_000)

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
        #expect(transcript == RawTranscript(text: "samples:5000"))
    }

    @Test("the recognizer names itself, runs locally, and has no clip limit")
    func identity() async {
        // Triangulation skipped: these are constants with one possible value.
        let recognizer = ParakeetRecognizer(engine: FakeParakeetEngine())

        #expect(recognizer.id == ASRProviderID("parakeet-v3"))
        #expect(recognizer.locality == .local)
        #expect(recognizer.maxClipDuration == nil)
    }
}
