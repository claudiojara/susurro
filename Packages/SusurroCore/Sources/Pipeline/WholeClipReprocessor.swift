import Domain
import Foundation

/// Reprocesses a stored recording by handing the whole clip to the speech recognizer: no voice detection, no chunking, no
/// cleanup, so the text is the raw transcript. It is the retry's reprocessor until the dictation pipeline offers its own
/// stages, which run the full chain; both are a `DictationReprocessing`.
public struct WholeClipReprocessor: DictationReprocessing {
    private let recognizer: any SpeechRecognizer
    private let providerID: ASRProviderID?
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - providerID: The name the record keeps as the provider that wrote the text.
    ///   - sleep: Pauses for a duration, on the app's clock. The transcription is abandoned if it takes longer than
    ///     `DictationLimits.transcriptionTimeout(forClip:)`.
    public init(
        recognizer: any SpeechRecognizer, providerID: ASRProviderID? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.recognizer = recognizer
        self.providerID = providerID
        self.sleep = sleep
    }

    public func reprocess(_ clip: AudioClip, for record: DictationRecord) async throws -> ReprocessOutcome {
        switch await recognizer.readiness() {
        case .ready: break
        case .notInstalled: throw PipelineError.recognizerNotInstalled
        case .loading: throw PipelineError.recognizerUnavailable("The speech model is still loading.", retryable: true)
        case .unavailable(let reason, let retryable):
            throw PipelineError.recognizerUnavailable(reason, retryable: retryable)
        }
        let recognizer = recognizer
        let transcript: RawTranscript
        do {
            transcript = try await withDeadline(
                DictationLimits.transcriptionTimeout(forClip: clip.duration), stage: .transcription, sleep: sleep
            ) {
                try await recognizer.transcribe(clip, options: RecognitionOptions())
            }
        } catch let error as PipelineError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PipelineError.recognitionFailed(String(describing: error))
        }
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .noSpeech }
        return .text(ReprocessedText(rawText: text, finalText: text, asrProvider: providerID))
    }
}
