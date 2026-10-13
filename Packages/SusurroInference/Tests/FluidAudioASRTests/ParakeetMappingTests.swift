import Domain
import Testing

@testable import FluidAudioASR

@Suite("Parakeet mapping", .timeLimit(.minutes(1)))
struct ParakeetMappingTests {
    private struct Failure: Error, Equatable {
        let reason: String
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
        "the whole clip reaches the engine unchanged, from the shortest accepted to a minute and more",
        arguments: [0, 1, 5, 20, 60]
    )
    func wholeClipReachesTheEngine(extraSeconds: Int) async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let count = engine.minimumSampleCount + extraSeconds * AudioClip.sampleRate
        let clip = AudioClip.ramp(samples: count)

        let transcript = try await recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(engine.transcriptions == [.init(samples: clip.samples, language: nil)])
        #expect(transcript == RawTranscript(text: "samples:\(count)"))
    }

    @Test(
        "the language is automatic unless it is pinned",
        arguments: [(String?.none, String?.none), ("es", "es"), ("en", "en")]
    )
    func languageIsPassedThrough(pinned: String?, expected: String?) async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount)

        _ = try await recognizer.transcribe(clip, options: RecognitionOptions(language: pinned))

        #expect(engine.transcriptions.map(\.language) == [expected])
    }

    @Test("vocabulary terms are ignored without an error")
    func vocabularyIsIgnored() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount)
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
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount)

        await #expect(throws: RecognitionError.engineFailed(String(describing: Failure(reason: reason)))) {
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
    }
}
