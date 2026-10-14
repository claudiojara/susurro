import FoundationModels

/// The real model. Touching it needs Apple Intelligence on this Mac, so it is covered by the opt-in `RealModelTests` and
/// the manual check, not by the default tests.
///
/// The reply is plain text, not a `@Generable` structure. Measured on this model with the same instructions and the same
/// Spanish transcript, a structured reply came back without accents, capitals, or punctuation ("queria", "reunion"),
/// and the plain reply was correct ("Hola equipo, quería comentarles que la reunión ...").
///
/// A call uses a new session, so a dictation never sees the one before it. `prewarm` makes that session ahead of the
/// call, as the key goes down, and asks the system to load the model for it; the next `generate` with the same
/// instructions takes it, once.
final class LiveFoundationModelsEngine: FoundationModelsEngine {
    private let warm = WarmSlot<LanguageModelSession>()

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

    func prewarm(instructions: String) async {
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        warm.store(session, instructions: instructions)
    }

    func generate(_ request: EngineRequest) async throws -> String {
        // A new session for each call: a dictation must not see the one before it. A warm one has seen no request.
        let session =
            warm.take(instructions: request.instructions) ?? LanguageModelSession(instructions: request.instructions)
        let sampling: GenerationOptions.SamplingMode =
            switch request.sampling {
            case .greedy: .greedy
            }
        let options = GenerationOptions(samplingMode: sampling, maximumResponseTokens: request.maximumResponseTokens)
        do {
            return try await session.respond(to: request.prompt, options: options).content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: LanguageModelSession.GenerationError) -> EngineError {
        switch error {
        case .guardrailViolation, .refusal: .guardrailViolation
        case .exceededContextWindowSize: .contextWindowExceeded
        default: .failed(String(describing: error))
        }
    }
}
