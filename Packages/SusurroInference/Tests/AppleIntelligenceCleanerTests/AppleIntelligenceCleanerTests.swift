import Domain
import Testing
import TextShaping

@testable import AppleIntelligenceCleaner

@Suite("Apple Intelligence cleaner", .timeLimit(.minutes(1)))
struct AppleIntelligenceCleanerTests {
    private let style = StyleProfile(category: .email, tone: .formal, source: .default)

    private func local(_ transcript: String = "hola equipo") -> CleanupPayload {
        .local(
            LocalCleanupRequest(
                transcript: transcript, style: style, vocabulary: ["Acme"], beforeCursor: "Dear team,"))
    }

    @Test("it is local, named Apple Intelligence, and budgeted for the on-device model")
    func identity() {
        let cleaner = AppleIntelligenceCleaner(engine: FakeFoundationModelsEngine())
        #expect(cleaner.id == .appleIntelligence)
        #expect(cleaner.locality == .local)
        #expect(cleaner.budget == .foundationModels)
    }

    @Test("availability maps what the system reports")
    func availabilityMapping() async {
        let cases: [(EngineAvailability, CleanerAvailability)] = [
            (.available, .available),
            (.unavailable(.deviceNotEligible), .unavailable("This Mac does not support Apple Intelligence.")),
            (
                .unavailable(.appleIntelligenceNotEnabled),
                .unavailable("Apple Intelligence is turned off in System Settings.")
            ),
            (.unavailable(.modelNotReady), .unavailable("The Apple Intelligence model is not ready yet.")),
            (.unavailable(.other), .unavailable("Apple Intelligence is not available.")),
        ]
        for (engine, expected) in cases {
            let cleaner = AppleIntelligenceCleaner(engine: FakeFoundationModelsEngine(availability: engine))
            #expect(await cleaner.availability() == expected)
        }
    }

    @Test("the request is the prompt builder's output, sampled greedily, and the answer comes back")
    func request() async throws {
        let engine = FakeFoundationModelsEngine(answer: "Hola, equipo.")
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        let payload = local()
        let text = try await cleaner.clean(payload)

        let expected = PromptBuilder.build(try payload.requireLocal())
        #expect(text == "Hola, equipo.")
        #expect(
            engine.requests == [
                EngineRequest(
                    instructions: expected.system, prompt: expected.user, sampling: .greedy,
                    maximumResponseTokens: 11 / 2 + 48)
            ])
    }

    @Test("the reply is cut at about half a token a character of the transcript, with a floor for short ones")
    func responseTokenLimit() {
        #expect(AppleIntelligenceCleaner.responseTokenLimit(forTranscriptCharacters: 0) == 48)
        #expect(AppleIntelligenceCleaner.responseTokenLimit(forTranscriptCharacters: 2_500) == 1_298)
    }

    // MARK: Prewarm

    @Test("a prewarm asks the model to get ready with the instructions that every request carries")
    func prewarmUsesTheInstructions() async {
        let engine = FakeFoundationModelsEngine()
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        await cleaner.prewarm()
        #expect(engine.prewarmed == [PromptBuilder.systemPrompt])
        #expect(engine.requests.isEmpty)
    }

    @Test("a prewarm and then a clean use the warm session once, and the next clean does not reuse it")
    func warmSessionIsUsedOnce() async throws {
        let engine = FakeFoundationModelsEngine()
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        await cleaner.prewarm()
        _ = try await cleaner.clean(local("one"))
        _ = try await cleaner.clean(local("two"))
        #expect(engine.usedWarmSession == [true, false])
    }

    @Test("a clean with no prewarm still works")
    func cleanWithoutPrewarm() async throws {
        let engine = FakeFoundationModelsEngine(answer: "Hola, equipo.")
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        #expect(try await cleaner.clean(local()) == "Hola, equipo.")
        #expect(engine.usedWarmSession == [false])
    }

    @Test("a second prewarm replaces the first: one session is left, and it is used once")
    func prewarmTwice() async throws {
        let engine = FakeFoundationModelsEngine()
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        await cleaner.prewarm()
        await cleaner.prewarm()
        _ = try await cleaner.clean(local("one"))
        _ = try await cleaner.clean(local("two"))
        #expect(engine.prewarmed.count == 2)
        #expect(engine.usedWarmSession == [true, false])
    }

    @Test("a model that is not available is not prewarmed")
    func noPrewarmWhenUnavailable() async {
        let engine = FakeFoundationModelsEngine(availability: .unavailable(.appleIntelligenceNotEnabled))
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        await cleaner.prewarm()
        #expect(engine.prewarmed.isEmpty)
    }

    @Test("a cloud payload is refused and the model is never called")
    func cloudPayloadThrows() async {
        let engine = FakeFoundationModelsEngine()
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        let payload = CleanupPayload.cloud(CloudCleanupRequest(transcript: "hola", style: style, vocabulary: []))
        await #expect(throws: CloudBoundaryViolation.self) { try await cleaner.clean(payload) }
        #expect(engine.requests.isEmpty)
    }

    @Test("model errors map to cleaner errors")
    func errorMapping() async {
        struct Other: Error {}
        let cases: [(any Error, CleanerError)] = [
            (EngineError.guardrailViolation, .guardrail),
            (EngineError.contextWindowExceeded, .contextWindowExceeded),
            (EngineError.failed("boom"), .failed("boom")),
            (Other(), .failed(String(describing: Other()))),
        ]
        for (failure, expected) in cases {
            let cleaner = AppleIntelligenceCleaner(engine: FakeFoundationModelsEngine(failure: failure))
            await #expect(throws: expected) { try await cleaner.clean(local()) }
        }
    }

    @Test("concurrent calls run one at a time, in the order they arrived")
    func calls() async throws {
        let engine = FakeFoundationModelsEngine(gated: true)
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        let first = Task { try await cleaner.clean(local("one")) }
        await engine.entered.wait()
        let second = Task { try await cleaner.clean(local("two")) }
        try #require(await waitForQueue(cleaner, count: 1))
        let third = Task { try await cleaner.clean(local("three")) }
        try #require(await waitForQueue(cleaner, count: 2))
        for _ in 0..<3 { engine.release() }
        _ = try await [first.value, second.value, third.value]

        #expect(engine.peakActive == 1)
        #expect(
            engine.requests.map {
                $0.prompt.contains("<TRANSCRIPT>one<") ? "one" : $0.prompt.contains(">two<") ? "two" : "three"
            } == ["one", "two", "three"])
    }

    @Test("a cancelled call leaves the queue at once")
    func cancelledWaiter() async throws {
        let engine = FakeFoundationModelsEngine(gated: true)
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        let first = Task { try await cleaner.clean(local("one")) }
        await engine.entered.wait()
        let second = Task { try await cleaner.clean(local("two")) }
        try #require(await waitForQueue(cleaner, count: 1))
        second.cancel()
        try #require(await waitForQueue(cleaner, count: 0))
        await #expect(throws: CancellationError.self) { try await second.value }
        engine.release()
        _ = try await first.value
        #expect(engine.requests.count == 1)
    }

    /// Waits until exactly `count` calls are queued behind the one running. False after ten seconds, so a regression
    /// fails instead of hanging.
    private func waitForQueue(_ cleaner: AppleIntelligenceCleaner, count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while await cleaner.queuedCalls != count {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            await Task.yield()
        }
        return true
    }
}
