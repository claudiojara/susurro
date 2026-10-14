import CoreTestSupport
import Domain
import Testing

@testable import Pipeline

@Suite("Cleanup stage")
struct CleanupStageTests {
    private static let neutral = StyleProfile(category: .document, tone: .neutral)

    private func stage(
        _ cleaner: FakeCleaner?, enabled: Bool = true, clock: ManualClock = ManualClock()
    ) -> CleanupStage {
        CleanupStage(
            isEnabled: { enabled }, cleaner: { cleaner },
            sleep: { try await clock.sleep(for: $0) })
    }

    private func input(
        _ transcript: String = "hola equipo", tone: Tone = .neutral, vocabulary: [String] = [],
        cursor: CursorContext? = nil
    ) -> CleanupInput {
        CleanupInput(
            transcript: transcript, style: StyleProfile(category: .document, tone: tone),
            vocabulary: vocabulary, cursor: cursor)
    }

    // MARK: Skip rules

    @Test("a skipped cleanup makes no call and uses the raw transcript")
    func skipRules() async throws {
        let unavailable = FakeCleaner(availability: .unavailable("Apple Intelligence is off"))
        let cases:
            [(name: String, cleaner: FakeCleaner?, enabled: Bool, input: CleanupInput, reason: FallbackReason?)] = [
                ("disabled", FakeCleaner(), false, input(), nil),
                ("verbatim tone", FakeCleaner(), true, input(tone: .verbatim), nil),
                ("empty transcript", FakeCleaner(), true, input(""), nil),
                ("blank transcript", FakeCleaner(), true, input("   \n"), nil),
                ("unavailable", unavailable, true, input(), .providerUnavailable),
                ("no usable cleaner", nil, true, input(), .providerUnavailable),
            ]
        for testCase in cases {
            let result = try await stage(testCase.cleaner, enabled: testCase.enabled).run(testCase.input)
            #expect(result.finalText == testCase.input.transcript, "\(testCase.name)")
            #expect(result.raw == testCase.input.transcript, "\(testCase.name)")
            #expect(result.cleaned == nil, "\(testCase.name)")
            #expect(result.fallbackReason == testCase.reason, "\(testCase.name)")
            #expect(testCase.cleaner?.callCount ?? 0 == 0, "\(testCase.name)")
        }
    }

    @Test("a verbatim dictation still gets the spacing of the field")
    func verbatimIsShaped() async throws {
        let cleaner = FakeCleaner()
        let result = try await stage(cleaner).run(
            input("The report", tone: .verbatim, cursor: CursorContext(before: "Please send me", after: "")))
        #expect(result.finalText == " the report")
        #expect(result.cleaned == nil)
        #expect(cleaner.callCount == 0)
    }

    // MARK: Budgets

    @Test("FoundationModels takes 2,500 characters and refuses 2,501")
    func foundationModelsBudget() async throws {
        let echo = FakeCleaner.Answer.compute { payload in
            (try? payload.requireLocal().transcript) ?? ""
        }
        let exact = FakeCleaner(answer: echo)
        let atLimit = String(repeating: "a", count: 2_500)
        let accepted = try await stage(exact).run(input(atLimit))
        #expect(exact.callCount == 1)
        #expect(accepted.cleaned == atLimit)
        #expect(accepted.fallbackReason == nil)

        let over = FakeCleaner(answer: echo)
        let overLimit = String(repeating: "a", count: 2_501)
        let refused = try await stage(over).run(input(overLimit))
        #expect(over.callCount == 0)
        #expect(refused.finalText == overLimit)
        #expect(refused.cleaned == nil)
        #expect(refused.fallbackReason == .inputTooLarge)
    }

    @Test("the text before the cursor is trimmed before the transcript is refused")
    func beforeTextIsTrimmedFirst() async throws {
        let cleaner = FakeCleaner(answer: .compute { payload in (try? payload.requireLocal().transcript) ?? "" })
        let transcript = String(repeating: "a", count: 2_400)
        let cursor = CursorContext(before: String(repeating: "b", count: 500), after: "")
        let result = try await stage(cleaner).run(input(transcript, cursor: cursor))
        #expect(result.fallbackReason == nil)
        let request = try #require(cleaner.payloads.first).requireLocal()
        #expect(request.beforeCursor.count == 400)
    }

    @Test("a cloud cleaner takes 6,000 characters and refuses 6,001")
    func cloudBudget() async throws {
        let echo = FakeCleaner.Answer.compute { payload in (try? payload.requireCloud().transcript) ?? "" }
        let cloud = FakeCleaner(id: CleanerProviderID("cloud"), locality: .cloud, answer: echo)
        let exact = String(repeating: "a", count: 6_000)
        let accepted = try await stage(cloud).run(input(exact))
        #expect(cloud.callCount == 1)
        #expect(accepted.cleaned == exact)

        let tooLong = String(repeating: "a", count: 6_001)
        let refused = try await stage(cloud).run(input(tooLong))
        #expect(cloud.callCount == 1)
        #expect(refused.finalText == tooLong)
        #expect(refused.fallbackReason == .inputTooLarge)
    }

    // MARK: Failures

    @Test("a cleaner that throws gives the raw transcript and a reason")
    func providerFailure() async throws {
        let cases: [(CleanerError, FallbackReason)] = [
            (.failed("boom"), .providerFailure), (.unavailable("gone"), .providerFailure),
            (.guardrail, .guardrail), (.contextWindowExceeded, .inputTooLarge),
        ]
        for (error, reason) in cases {
            let cleaner = FakeCleaner(answer: .failure(error))
            let result = try await stage(cleaner).run(input())
            #expect(result.finalText == "hola equipo")
            #expect(result.cleaned == nil)
            #expect(result.fallbackReason == reason)
            #expect(result.provider == cleaner.id)
        }
    }

    @Test("a local timeout of 4 s gives the raw transcript, and a late answer is ignored")
    func localTimeout() async throws {
        let clock = ManualClock()
        let cleaner = FakeCleaner(gated: true)
        let stage = stage(cleaner, clock: clock)
        let running = Task { try await stage.run(input()) }
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(3_999))
        #expect(cleaner.callCount == 1)
        clock.advance(by: .milliseconds(1))
        let result = try await running.value
        #expect(result.finalText == "hola equipo")
        #expect(result.fallbackReason == .timeout)
        #expect(result.cleaned == nil)
        cleaner.releaseCleaning()
        #expect(result.fallbackReason == .timeout)
    }

    @Test("a cloud timeout of 6 s gives the raw transcript")
    func cloudTimeout() async throws {
        let clock = ManualClock()
        let cleaner = FakeCleaner(id: CleanerProviderID("cloud"), locality: .cloud, gated: true)
        let stage = stage(cleaner, clock: clock)
        let running = Task { try await stage.run(input()) }
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(4))
        #expect(cleaner.callCount == 1)
        clock.advance(by: .seconds(2))
        let result = try await running.value
        #expect(result.fallbackReason == .timeout)
        #expect(result.finalText == "hola equipo")
    }

    @Test("cancelling the dictation during cleanup ends the stage with no text")
    func cancellation() async throws {
        let cleaner = FakeCleaner(gated: true)
        let stage = stage(cleaner)
        let running = Task { try await stage.run(input()) }
        await cleaner.entered.wait()
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
    }

    // MARK: Records and flow

    @Test("cleaned text is kept apart from the shaped final text")
    func recordsAndShaping() async throws {
        let cleaner = FakeCleaner(answer: .text("Hola, equipo."))
        let result = try await stage(cleaner).run(
            input("hola equipo", cursor: CursorContext(before: "Dear team,", after: "")))
        #expect(result.raw == "hola equipo")
        #expect(result.cleaned == "Hola, equipo.")
        #expect(result.fallbackReason == nil)
        #expect(result.provider == .appleIntelligence)
        #expect(result.finalText == " hola, equipo.")
    }

    @Test("a fallback keeps cleaned nil and shapes the raw transcript")
    func fallbackRecords() async throws {
        let answer = String(repeating: "Paris is the capital of France. ", count: 12)
        let cleaner = FakeCleaner(answer: .text(answer))
        let result = try await stage(cleaner).run(
            input("what is the capital of france", cursor: CursorContext(before: "Q:", after: "")))
        #expect(result.cleaned == nil)
        #expect(result.fallbackReason == .expansion)
        #expect(result.raw == "what is the capital of france")
        #expect(result.finalText == " what is the capital of france")
    }

    @Test("the model's wrapper is stripped before the checks")
    func sanitizes() async throws {
        let cleaner = FakeCleaner(answer: .text("Here is the text: ```Hola, equipo.```"))
        let result = try await stage(cleaner).run(input("hola equipo"))
        #expect(result.cleaned == "Hola, equipo.")
        #expect(result.finalText == "Hola, equipo.")
    }

    @Test("the request carries the style, the vocabulary, and the bounded text before the cursor")
    func requestContents() async throws {
        let cleaner = FakeCleaner(answer: .text("Hola, Maria."))
        _ = try await stage(cleaner).run(
            input("hola maria", vocabulary: ["Maria"], cursor: CursorContext(before: "Hi", after: "x")))
        let request = try #require(cleaner.payloads.first).requireLocal()
        #expect(request.transcript == "hola maria")
        #expect(request.vocabulary == ["Maria"])
        #expect(request.beforeCursor == "Hi")
        #expect(request.style == StyleProfile(category: .document, tone: .neutral))
    }
}
