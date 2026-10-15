import CoreTestSupport
import Domain
import Testing

@testable import FluidAudioASR

/// A partial transcript is for display while the user speaks. It runs only when the engine is free, so it never makes a
/// transcript that will be pasted wait in the queue behind it.
@Suite("Parakeet partial transcripts", .timeLimit(.minutes(1)))
struct ParakeetPartialTests {
    @Test("an idle engine transcribes the clip with the language and no dictionary terms")
    func idleEngineTranscribes() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)

        let text = try await recognizer.transcribePartial(.ramp(samples: 8_000), language: "es")

        #expect(text == "samples:8000")
        #expect(engine.transcriptions == [.init(samples: AudioClip.ramp(samples: 8_000).samples, language: "es")])
    }

    @Test("before the model is ready there is no partial, and no error")
    func notReady() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = ParakeetRecognizer(engine: engine)

        #expect(try await recognizer.transcribePartial(.ramp(samples: 8_000), language: nil) == nil)
        #expect(engine.transcriptions.isEmpty)
    }

    @Test("a partial gives way at once to a transcription that runs, and does not queue behind it")
    func busyEngineGivesNothing() async throws {
        let engine = FakeParakeetEngine(gatedTranscription: true)
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let final = Task { try await recognizer.transcribe(.ramp(samples: 5_000), options: RecognitionOptions()) }
        await engine.entered.wait()

        let partial = try await recognizer.transcribePartial(.ramp(samples: 8_000), language: nil)

        #expect(partial == nil)
        #expect(await recognizer.queuedTranscriptions == 0)
        engine.releaseTranscription()
        #expect(try await final.value.text == "samples:5000")
        #expect(engine.transcriptions.map(\.samples.count) == [5_000])
    }

    @Test("a transcription that arrives while a partial runs goes next, and the two never overlap")
    func finalRunsAfterThePartial() async throws {
        let engine = FakeParakeetEngine(gatedTranscription: true)
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let partial = Task { try await recognizer.transcribePartial(.ramp(samples: 8_000), language: nil) }
        await engine.entered.wait()
        let final = Task { try await recognizer.transcribe(.ramp(samples: 5_000), options: RecognitionOptions()) }
        while await recognizer.queuedTranscriptions != 1 { await Task.yield() }

        for _ in 0..<2 { engine.releaseTranscription() }

        #expect(try await partial.value == "samples:8000")
        #expect(try await final.value.text == "samples:5000")
        #expect(engine.peakActiveTranscriptions == 1)
    }

    @Test("a clip too short for the engine is blank")
    func shortClipIsBlank() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)

        #expect(try await recognizer.transcribePartial(.ramp(samples: 100), language: nil) == "")
        #expect(engine.transcriptions.isEmpty)
    }
}
