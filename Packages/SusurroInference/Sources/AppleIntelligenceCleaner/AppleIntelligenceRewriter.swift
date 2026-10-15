import Domain
import TextShaping

/// Rewrites a selection with Apple's on-device model, for command mode: nothing leaves the Mac. The prompt is
/// `CommandPromptBuilder`'s, and the model samples greedily. The reply is collected whole: the engine reads the model as
/// a stream only so that a cancelled call leaves at once (ADR 0015), and nothing is streamed into the app.
///
/// Calls are not queued here: the dictation pipeline runs one job at a time, and a command is a job.
public struct AppleIntelligenceRewriter: SelectionRewriter {
    public let locality = Locality.local
    private let engine: any FoundationModelsEngine

    public init() {
        self.init(engine: LiveFoundationModelsEngine())
    }

    public init(engine: any FoundationModelsEngine) {
        self.engine = engine
    }

    public func availability() async -> CleanerAvailability {
        await AppleIntelligenceCleaner(engine: engine).availability()
    }

    /// Throws `CommandPromptError.inputTooLarge` for a request over the caps, `CancellationError` when cancelled, and the
    /// engine's error when the model fails.
    public func rewrite(_ request: LocalCommandRequest) async throws -> String {
        let prompt = try CommandPromptBuilder.build(request)
        return try await engine.generate(
            EngineRequest(
                instructions: prompt.system, prompt: prompt.user, sampling: .greedy,
                maximumResponseTokens: CommandPromptBuilder.responseTokenLimit(
                    forSelectionCharacters: request.selection.count)))
    }
}
