import Domain
import Testing

@testable import FluidAudioASR

/// A blank result is a transcript, not an error: the coordinator ends the attempt as no speech.
@Suite("Parakeet blank transcripts", .timeLimit(.minutes(1)))
struct ParakeetBlankTranscriptTests {
    @Test("a clip below the engine's minimum is blank and never reaches the engine")
    func clipBelowTheMinimum() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount - 1)

        let transcript = try await recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(transcript == RawTranscript(text: ""))
        #expect(engine.transcriptions.isEmpty)
    }

    @Test("an empty clip is blank and never reaches the engine")
    func emptyClip() async throws {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)

        let transcript = try await recognizer.transcribe(AudioClip(samples: []), options: RecognitionOptions())

        #expect(transcript == RawTranscript(text: ""))
        #expect(engine.transcriptions.isEmpty)
    }

    @Test(
        "text the engine returns as nothing or as whitespace is blank, with no error", arguments: ["", "   ", "\n \t"])
    func blankEngineText(text: String) async throws {
        let engine = FakeParakeetEngine(respond: { _ in text })
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount)

        let transcript = try await recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(transcript.text.allSatisfy { $0.isWhitespace })
        #expect(engine.transcriptions.count == 1)
    }
}
