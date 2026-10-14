import CoreTestSupport
import Domain
import Testing

@testable import Pipeline

@Suite("Cleanup stage")
struct CleanupStageTests {
    private static let neutral = StyleProfile(category: .document, tone: .neutral, source: .default)

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
            transcript: transcript, style: StyleProfile(category: .document, tone: tone, source: .default),
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

    /// (transcript characters, limit in milliseconds): 1.2 s and 8 ms for each character, up to 6 s.
    @Test(
        "a local call gets 1.2 s plus 8 ms a character, up to 6 s, then the raw transcript is used and a late answer is ignored",
        arguments: [(30, 1_440), (79, 1_832), (300, 3_600), (599, 5_992), (600, 6_000), (2_500, 6_000)])
    func localTimeout(characters: Int, milliseconds: Int) async throws {
        let clock = ManualClock()
        let cleaner = FakeCleaner(gated: true)
        let stage = stage(cleaner, clock: clock)
        let transcript = String(repeating: "a", count: characters)
        let running = Task { try await stage.run(input(transcript)) }
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(milliseconds - 1))
        #expect(cleaner.callCount == 1)
        #expect(clock.pendingSleeps == 1)
        clock.advance(by: .milliseconds(1))
        let result = try await running.value
        #expect(result.finalText == transcript)
        #expect(result.fallbackReason == .timeout)
        #expect(result.cleaned == nil)
        cleaner.releaseCleaning()
        #expect(result.fallbackReason == .timeout)
    }

    @Test("a cloud call gets 6 s whatever the length of the transcript, then the raw transcript is used")
    func cloudTimeout() async throws {
        for characters in [11, 3_000] {
            let clock = ManualClock()
            let cleaner = FakeCleaner(id: CleanerProviderID("cloud"), locality: .cloud, gated: true)
            let stage = stage(cleaner, clock: clock)
            let transcript = String(repeating: "a", count: characters)
            let running = Task { try await stage.run(input(transcript)) }
            await clock.waitForSleeps(1)
            clock.advance(by: .seconds(4))
            #expect(cleaner.callCount == 1)
            clock.advance(by: .milliseconds(1_999))
            #expect(clock.pendingSleeps == 1)
            clock.advance(by: .milliseconds(1))
            let result = try await running.value
            #expect(result.fallbackReason == .timeout)
            #expect(result.finalText == transcript)
        }
    }

    // MARK: Prewarm

    @Test("a prewarm gets the cleaner ready while cleanup is on")
    func prewarmWhenEnabled() async {
        let cleaner = FakeCleaner()
        await stage(cleaner).prewarm()
        #expect(cleaner.prewarmCount == 1)
        #expect(cleaner.callCount == 0)
    }

    @Test("a prewarm does nothing while cleanup is off or when there is no cleaner")
    func prewarmSkipped() async {
        let cleaner = FakeCleaner()
        await stage(cleaner, enabled: false).prewarm()
        #expect(cleaner.prewarmCount == 0)
        await stage(nil).prewarm()
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
        let answer = String(repeating: "El informe de ventas incluye todas las regiones. ", count: 12)
        let cleaner = FakeCleaner(answer: .text(answer))
        let result = try await stage(cleaner).run(
            input("el informe de ventas", cursor: CursorContext(before: "Q:", after: "")))
        #expect(result.cleaned == nil)
        #expect(result.fallbackReason == .expansion)
        #expect(result.raw == "el informe de ventas")
        #expect(result.finalText == " el informe de ventas")
    }

    @Test("a model that answers a short dictated question gives the raw transcript and the reason answered")
    func answeredQuestion() async throws {
        let cleaner = FakeCleaner(answer: .text("La capital de Francia es París."))
        let result = try await stage(cleaner).run(input("qué es la capital de francia"))
        #expect(result.cleaned == nil)
        #expect(result.fallbackReason == .answered)
        #expect(result.provider == .appleIntelligence)
        #expect(result.finalText == "qué es la capital de francia")
    }

    @Test("a cleaned question is kept, and a term of the vocabulary or the context is not taken for an answer")
    func cleanedQuestionIsKept() async throws {
        let cleaned = FakeCleaner(answer: .text("¿Qué es la capital de Francia?"))
        let kept = try await stage(cleaned).run(input("qué es la capital de francia"))
        #expect(kept.cleaned == "¿Qué es la capital de Francia?")
        #expect(kept.fallbackReason == nil)

        let term = FakeCleaner(answer: .text("¿Dónde está Kaelthorn?"))
        let fromVocabulary = try await stage(term).run(
            input("dime donde esta kael thorn", vocabulary: ["Kaelthorn"]))
        #expect(fromVocabulary.fallbackReason == nil)
        let fromContext = try await stage(term).run(
            input(
                "dime donde esta kael thorn", cursor: CursorContext(before: "Kaelthorn", after: "")))
        #expect(fromContext.fallbackReason == nil)
        let unknown = try await stage(term).run(input("dime donde esta kael thorn"))
        #expect(unknown.fallbackReason == .answered)
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
        #expect(request.style == StyleProfile(category: .document, tone: .neutral, source: .default))
    }

    @Test("lines of the context or the vocabulary that the model copied to the start of its reply are dropped")
    func copiedReference() async throws {
        let cleaner = FakeCleaner(answer: .text("Asunto: reunión\nAcme\nHola equipo, la reunión es a las tres."))
        let result = try await stage(cleaner).run(
            input(
                "hola equipo la reunión es a las tres", vocabulary: ["Acme"],
                cursor: CursorContext(before: "Asunto: reunión", after: "")))
        #expect(result.cleaned == "Hola equipo, la reunión es a las tres.")
        #expect(result.fallbackReason == nil)
    }

    @Test("a reply that only repeats the request tags falls back to the raw transcript")
    func echoedTags() async throws {
        let cleaner = FakeCleaner(answer: .text("<STYLE category=\"document\" tone=\"neutral\"/>"))
        let result = try await stage(cleaner).run(input("what is the capital of france"))
        #expect(result.cleaned == nil)
        #expect(result.fallbackReason == .emptyOutput)
        #expect(result.finalText == "what is the capital of france")
    }
}
