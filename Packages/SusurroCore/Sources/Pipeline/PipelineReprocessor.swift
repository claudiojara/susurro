import Domain
import Foundation

/// Runs a stored recording through the stages of the pipeline again, for the retry in the history: voice detection, then
/// the recognizer with the same waiting, timeouts, fallback, and language guard as a new dictation. It produces the raw
/// transcript and never inserts it: the history decides what to do with the text.
public struct PipelineReprocessor: DictationReprocessing {
    private let detector: any VoiceActivityDetector
    private let runner: RecognitionRunner

    public init(detector: any VoiceActivityDetector, runner: RecognitionRunner) {
        self.detector = detector
        self.runner = runner
    }

    public func reprocess(_ clip: AudioClip, for record: DictationRecord) async throws -> ReprocessOutcome {
        // A detector that fails sends the clip whole, as in a new dictation.
        let found = try? await detector.analyze(clip)
        let wholeClip = VADResult(segments: [SpeechSegment(start: .zero, end: clip.duration)])
        guard SilenceClassifier.classify(clip, result: found ?? wholeClip) == .speech else { return .noSpeech }

        let input = found.flatMap { SpeechSpan.input(from: clip, result: $0) } ?? clip
        let recognition = try await runner.run(input) { _ in }
        guard !recognition.isBlank else { return .noSpeech }
        let text = recognition.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return .text(
            ReprocessedText(
                rawText: text, finalText: text, asrProvider: recognition.provider,
                fallbackReason: recognition.fallbackReason))
    }
}
