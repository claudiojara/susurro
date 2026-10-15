import Domain
import Testing
import TextShaping

@testable import AppleIntelligenceCleaner

@Suite("Apple Intelligence rewriter", .timeLimit(.minutes(1)))
struct AppleIntelligenceRewriterTests {
    private let request = LocalCommandRequest(instruction: "hazlo más formal", selection: "hola, qué tal")

    @Test("it runs on this Mac")
    func local() {
        #expect(AppleIntelligenceRewriter(engine: FakeFoundationModelsEngine()).locality == .local)
    }

    @Test("availability is the model's: available, or unavailable for any reason")
    func availability() async {
        #expect(await AppleIntelligenceRewriter(engine: FakeFoundationModelsEngine()).availability() == .available)
        let off = AppleIntelligenceRewriter(
            engine: FakeFoundationModelsEngine(availability: .unavailable(.appleIntelligenceNotEnabled)))
        #expect(await off.availability() == .unavailable("Apple Intelligence is turned off in System Settings."))
    }

    @Test(
        "the request is the command prompt, sampled greedily, with a reply as long as the selection and a little more")
    func requestShape() async throws {
        let engine = FakeFoundationModelsEngine(answer: "Buenos días, ¿cómo está usted?")
        let rewriter = AppleIntelligenceRewriter(engine: engine)

        let reply = try await rewriter.rewrite(request)

        let prompt = try CommandPromptBuilder.build(request)
        #expect(reply == "Buenos días, ¿cómo está usted?")
        #expect(
            engine.requests == [
                EngineRequest(
                    instructions: prompt.system, prompt: prompt.user, sampling: .greedy,
                    maximumResponseTokens: request.selection.count + 64)
            ])
    }

    @Test("a request over the caps never reaches the model")
    func capsAreChecked() async {
        let engine = FakeFoundationModelsEngine()
        let rewriter = AppleIntelligenceRewriter(engine: engine)
        let long = LocalCommandRequest(
            instruction: "x", selection: String(repeating: "a", count: CommandLimits.maxSelection + 1))

        await #expect(throws: CommandPromptError.inputTooLarge) { try await rewriter.rewrite(long) }
        #expect(engine.requests.isEmpty)
    }

    @Test("a cancelled rewrite reaches the model, which leaves at once")
    func cancellation() async throws {
        let engine = FakeFoundationModelsEngine(gated: true)
        let rewriter = AppleIntelligenceRewriter(engine: engine)
        let request = request
        let task = Task { try await rewriter.rewrite(request) }
        await engine.entered.wait()

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.wasCancelledOnResume == true)
    }
}
