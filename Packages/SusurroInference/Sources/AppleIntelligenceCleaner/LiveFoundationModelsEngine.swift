import FoundationModels

/// What the model is asked to produce: the cleaned text, and nothing around it. The structure keeps the model from
/// wrapping the text in a label, though the output is sanitized anyway.
@Generable
struct CleanedText {
    @Guide(description: "The cleaned text only, with no label, quotes, or explanation.")
    var text: String
}

/// The real model. Touching it needs Apple Intelligence on this Mac, so it is covered by the manual check, not by tests.
struct LiveFoundationModelsEngine: FoundationModelsEngine {
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
        // A new session for each call: a dictation must not see the one before it.
        let session = LanguageModelSession(instructions: request.instructions)
        let options =
            switch request.sampling {
            case .greedy: GenerationOptions(sampling: .greedy)
            }
        do {
            let response = try await session.respond(to: request.prompt, generating: CleanedText.self, options: options)
            return response.content.text
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
