import CoreTestSupport
import Domain
import Testing
import TextShaping

@testable import Pipeline

/// The deterministic passes of the cleanup stage: snippets, fillers, and replacements, with and without a cleaner.
@Suite("Cleanup stage rules")
struct CleanupRulesTests {
    private static let rules = TranscriptRules(
        snippets: [
            VoiceSnippet(trigger: "mi firma", text: "Un saludo,\nClaudio"),
            VoiceSnippet(trigger: "Saludo largo", text: "Hola a todos"),
        ],
        replacements: [ReplacementRule(spoken: "jira", written: "Jira")],
        removesFillers: true)

    private func stage(_ cleaner: FakeCleaner?, enabled: Bool = true) -> CleanupStage {
        CleanupStage(
            isEnabled: { enabled }, cleaner: { cleaner }, rules: { Self.rules },
            sleep: { try await ManualClock().sleep(for: $0) })
    }

    private func input(_ transcript: String, tone: Tone = .neutral, cursor: CursorContext? = nil) -> CleanupInput {
        CleanupInput(
            transcript: transcript, style: StyleProfile(category: .document, tone: tone, source: .default),
            cursor: cursor)
    }

    @Test("a dictation that is a trigger inserts the snippet as written, and no cleaner runs")
    func wholeSnippet() async throws {
        let cleaner = FakeCleaner()
        let result = try await stage(cleaner).run(input("Mi firma."))
        #expect(result.finalText == "Un saludo,\nClaudio")
        #expect(result.raw == "Mi firma.")
        #expect(result.cleaned == nil)
        #expect(result.fallbackReason == nil)
        #expect(cleaner.callCount == 0)
    }

    @Test("a snippet gets the space the field needs, and keeps its case mid-sentence")
    func snippetSpacing() async throws {
        let result = try await stage(nil, enabled: false).run(
            input("mi firma", cursor: CursorContext(before: "Gracias.", after: "")))
        #expect(result.finalText == " Un saludo,\nClaudio")
        let mid = try await stage(nil, enabled: false).run(
            input("saludo largo", cursor: CursorContext(before: "y", after: "")))
        #expect(mid.finalText == " Hola a todos")
    }

    @Test("with cleanup off, fillers and replacements still run and the raw transcript is kept")
    func passesWithoutCleaner() async throws {
        let result = try await stage(nil, enabled: false).run(input("Eh, abre jira a las 2, no, a las 3."))
        #expect(result.finalText == "Abre Jira a las 3.")
        #expect(result.raw == "Eh, abre jira a las 2, no, a las 3.")
        #expect(result.cleaned == nil)
    }

    @Test("with cleanup on, the cleaner is given the text after the passes")
    func cleanerGetsShapedText() async throws {
        let cleaner = FakeCleaner(answer: .compute { (try? $0.requireLocal().transcript) ?? "" })
        let result = try await stage(cleaner).run(input("eh abre jira"))
        let request = try #require(cleaner.payloads.first).requireLocal()
        #expect(request.transcript == "abre Jira")
        #expect(result.finalText == "abre Jira")
        #expect(result.raw == "eh abre jira")
    }

    @Test("a cleaner that fails falls back to the text after the passes, not the raw one")
    func fallbackKeepsPasses() async throws {
        let cleaner = FakeCleaner(answer: .failure(.failed("boom")))
        let result = try await stage(cleaner).run(input("eh abre jira"))
        #expect(result.finalText == "abre Jira")
        #expect(result.fallbackReason == .providerFailure)
    }

    @Test("a snippet expanded inside a dictation keeps the cleaner away from its text")
    func inlineSnippetSkipsCleaner() async throws {
        let cleaner = FakeCleaner()
        let result = try await stage(cleaner).run(input("Gracias por todo. mi firma"))
        #expect(result.finalText == "Gracias por todo. Un saludo,\nClaudio")
        #expect(cleaner.callCount == 0)
        #expect(result.fallbackReason == nil)
    }

    @Test("a verbatim dictation keeps its fillers but gets the replacements")
    func verbatim() async throws {
        let result = try await stage(FakeCleaner()).run(input("eh abre jira", tone: .verbatim))
        #expect(result.finalText == "eh abre Jira")
    }

    @Test("over the settings, the rules are read from the store and fillers are removed by default")
    func settingsRules() async throws {
        let settings = InMemorySettingsStore()
        let stage = CleanupStage(
            settings: settings, registry: CleanerRegistry(settings: settings, entries: []),
            sleep: { try await ManualClock().sleep(for: $0) })
        #expect(try await stage.run(input("eh abre jira")).finalText == "abre jira")

        settings.set([ReplacementRule(spoken: "jira", written: "Jira")], for: TextRuleSettings.replacements)
        settings.set([VoiceSnippet(trigger: "firma", text: "Claudio")], for: TextRuleSettings.snippets)
        settings.set(false, for: TextRuleSettings.removeFillers)
        #expect(try await stage.run(input("eh abre jira")).finalText == "eh abre Jira")
        #expect(try await stage.run(input("Firma.")).finalText == "Claudio")
    }
}
