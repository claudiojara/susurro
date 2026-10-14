/// Whether Apple's on-device language model can take a request, as the system reports it.
public enum EngineAvailability: Sendable, Equatable {
    case available
    case unavailable(UnavailableReason)

    public enum UnavailableReason: Sendable, Equatable {
        /// This Mac cannot run Apple Intelligence.
        case deviceNotEligible
        /// The user has not turned Apple Intelligence on in System Settings.
        case appleIntelligenceNotEnabled
        /// The model is still downloading or loading.
        case modelNotReady
        /// A reason the system added that this version does not know.
        case other
    }
}

/// How the model picks its next word. Cleaning must give the same text for the same input, so it never samples.
public enum EngineSampling: Sendable, Equatable {
    case greedy
}

/// One call to the model: the fixed instructions, the tagged request, and how to sample.
public struct EngineRequest: Sendable, Equatable {
    public let instructions: String
    public let prompt: String
    public let sampling: EngineSampling

    public init(instructions: String, prompt: String, sampling: EngineSampling) {
        self.instructions = instructions
        self.prompt = prompt
        self.sampling = sampling
    }
}

/// Why the model gave no text.
public enum EngineError: Error, Sendable, Equatable {
    /// The model's safety system refused the text.
    case guardrailViolation
    /// The request does not fit the model's context window.
    case contextWindowExceeded
    /// The model failed. The text is the underlying error, which can quote the dictation: it is never logged.
    case failed(String)
}

/// The seam between the cleaner and FoundationModels, so the cleaner is tested without the model. The live engine wraps
/// `SystemLanguageModel`.
public protocol FoundationModelsEngine: Sendable {
    func availability() -> EngineAvailability
    /// Generates the cleaned text. A cancelled call throws `CancellationError`.
    func generate(_ request: EngineRequest) async throws -> String
}
