import FoundationModels

/// The real model. Touching it needs Apple Intelligence on this Mac, so it is covered by the opt-in `RealModelTests` and
/// the manual check, not by the default tests.
///
/// The reply is plain text, not a `@Generable` structure. Measured on this model with the same instructions and the same
/// Spanish transcript, a structured reply came back without accents, capitals, or punctuation ("queria", "reunion"),
/// and the plain reply was correct ("Hola equipo, quería comentarles que la reunión ...").
///
/// A call uses a new session, so a dictation never sees the one before it. The session is a local of the call: when the
/// call ends, cancelled or not, nothing holds it.
///
/// The reply is read as a stream and not with `respond`. Both honor the cancellation of the task that awaits them, but
/// measured on this model, a `respond` that was cancelled in the middle of a long reply came back 3 to 6 s later, when
/// the model had finished writing and the call threw `CancellationError`, while a stream ends in under a millisecond.
/// The cleaner's deadline cancels the call that ran out of time, and the next call waits for this one to leave, so a
/// call that lingers would hold the queue for seconds. Whether the model itself stops writing when the stream is dropped
/// is not something the framework shows, so a call that timed out can still load the machine for a moment (ADR 0015).
final class LiveFoundationModelsEngine: FoundationModelsEngine {
    func availability() -> EngineAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable:
            return .unavailable(.other)
        }
    }

    func generate(_ request: EngineRequest) async throws -> String {
        let session = LanguageModelSession(instructions: request.instructions)
        let sampling: GenerationOptions.SamplingMode =
            switch request.sampling {
            case .greedy: .greedy
            }
        let options = GenerationOptions(samplingMode: sampling, maximumResponseTokens: request.maximumResponseTokens)
        var text = ""
        do {
            for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                text = snapshot.content
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
        // A stream that is cancelled ends without an error, with the text written so far, which is not an answer.
        try Task.checkCancellation()
        return text
    }

    private static func map(_ error: LanguageModelSession.GenerationError) -> EngineError {
        switch error {
        case .guardrailViolation, .refusal: .guardrailViolation
        case .exceededContextWindowSize: .contextWindowExceeded
        default: .failed(String(describing: error))
        }
    }
}
