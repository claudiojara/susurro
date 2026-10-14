import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Testing

@Suite("Pipeline reprocessor", .timeLimit(.minutes(1)))
struct PipelineReprocessorTests {
    private static let clip = AudioClip(samples: [Float](repeating: 0.1, count: 2 * AudioClip.sampleRate))
    private static let record = DictationRecord(createdAt: Date(), duration: .seconds(2))

    private static func reprocessor(
        recognizer: FakeRecognizer = FakeRecognizer(transcript: " hola ", id: .parakeetV3),
        vad: FakeVoiceActivityDetector = FakeVoiceActivityDetector()
    ) -> PipelineReprocessor {
        let settings = InMemorySettingsStore()
        let sleeper = FakeSleeper()
        let registry = RecognizerRegistry(providers: [recognizer], defaultProvider: .parakeetV3, settings: settings)
        return PipelineReprocessor(
            detector: vad,
            runner: RecognitionRunner(
                registry: registry, language: SettingsLanguagePreference(settings: settings),
                sleep: { try await sleeper.sleep($0) }))
    }

    @Test("a stored recording gives its raw text, trimmed, with the provider that wrote it")
    func text() async throws {
        let outcome = try await Self.reprocessor().reprocess(Self.clip, for: Self.record)

        #expect(outcome == .text(ReprocessedText(rawText: "hola", finalText: "hola", asrProvider: .parakeetV3)))
    }

    @Test("the recognizer hears the speech span, not the whole recording")
    func speechSpan() async throws {
        let recognizer = FakeRecognizer(transcript: "hola", id: .parakeetV3)
        let vad = FakeVoiceActivityDetector(segments: [
            SpeechSegment(start: .milliseconds(900), end: .milliseconds(1000))
        ])
        _ = try await Self.reprocessor(recognizer: recognizer, vad: vad).reprocess(Self.clip, for: Self.record)

        #expect(recognizer.transcribedClips.map(\.duration) == [.milliseconds(1_000)])
    }

    @Test("no speech, a silent recording, and a blank transcript are no speech")
    func noSpeech() async throws {
        let silent = AudioClip(samples: [Float](repeating: 0, count: AudioClip.sampleRate))
        let none = FakeVoiceActivityDetector(segments: [])
        let blank = FakeRecognizer(transcript: "  ", id: .parakeetV3)

        #expect(try await Self.reprocessor(vad: none).reprocess(Self.clip, for: Self.record) == .noSpeech)
        #expect(try await Self.reprocessor().reprocess(silent, for: Self.record) == .noSpeech)
        #expect(try await Self.reprocessor(recognizer: blank).reprocess(Self.clip, for: Self.record) == .noSpeech)
    }

    @Test("a detector that fails sends the whole recording")
    func detectorFailure() async throws {
        struct Failure: Error {}
        let recognizer = FakeRecognizer(transcript: "hola", id: .parakeetV3)
        _ = try await Self.reprocessor(recognizer: recognizer, vad: FakeVoiceActivityDetector(failure: Failure()))
            .reprocess(Self.clip, for: Self.record)

        #expect(recognizer.transcribedClips == [Self.clip])
    }

    @Test("a recognizer that fails throws the pipeline error, for the history to report")
    func failure() async {
        struct Failure: Error {}
        let recognizer = FakeRecognizer(failure: Failure(), id: .parakeetV3)

        await #expect(throws: PipelineError.recognitionFailed(String(describing: Failure()))) {
            try await Self.reprocessor(recognizer: recognizer).reprocess(Self.clip, for: Self.record)
        }
    }
}
