import Domain
import Foundation
import Testing

@testable import TextShaping

@Suite("Transcript rules")
struct TranscriptRulesTests {
    private static let signature = VoiceSnippet(trigger: "mi firma", text: "Un saludo,\nClaudio Jara")
    private static let address = VoiceSnippet(trigger: "Dirección", text: "Calle Mayor 1, Madrid")

    private func rules(
        snippets: [VoiceSnippet] = [signature, address], replacements: [ReplacementRule] = [],
        removesFillers: Bool = true
    ) -> TranscriptRules {
        TranscriptRules(snippets: snippets, replacements: replacements, removesFillers: removesFillers)
    }

    // MARK: Whole-dictation snippets

    @Test("a dictation that is only a trigger is the snippet, whatever its case, accents and punctuation")
    func wholeDictation() {
        for spoken in ["mi firma", "Mi firma.", "MI FIRMA", "  mi   firma!  ", "Mi, firma"] {
            #expect(rules().snippet(matching: spoken) == "Un saludo,\nClaudio Jara", "\(spoken)")
        }
        #expect(rules().snippet(matching: "direccion") == "Calle Mayor 1, Madrid")
        #expect(rules().snippet(matching: "Dirección.") == "Calle Mayor 1, Madrid")
    }

    @Test("a dictation that says more than a trigger is not a whole-dictation snippet")
    func notWhole() {
        #expect(rules().snippet(matching: "mi firma nueva") == nil)
        #expect(rules().snippet(matching: "firma") == nil)
        #expect(rules().snippet(matching: "") == nil)
        #expect(rules(snippets: []).snippet(matching: "mi firma") == nil)
    }

    // MARK: Inline snippets

    @Test("a trigger of two words or more inside a dictation is expanded where it is said")
    func inline() {
        let result = rules().apply(to: "Gracias por todo. mi firma")
        #expect(result.text == "Gracias por todo. Un saludo,\nClaudio Jara")
        #expect(result.expandedSnippet)
    }

    @Test("a one-word trigger is expanded only when it is the whole dictation")
    func oneWordTriggerInline() {
        let result = rules().apply(to: "Cambia la dirección del envío")
        #expect(result.text == "Cambia la dirección del envío")
        #expect(result.expandedSnippet == false)
    }

    @Test("an inline trigger matches only as the exact phrase, not split by punctuation")
    func inlineExactPhrase() {
        #expect(rules().apply(to: "es mi, firma").text == "es mi, firma")
        #expect(rules().apply(to: "es mi firmamento").text == "es mi firmamento")
    }

    @Test("the snippet text is kept as written: fillers and replacements do not touch it")
    func snippetProtected() {
        let snippet = VoiceSnippet(trigger: "nota legal", text: "Eh, este texto menciona jira.")
        let result = rules(
            snippets: [snippet], replacements: [ReplacementRule(spoken: "jira", written: "Jira")]
        ).apply(to: "eh, abre jira y pon nota legal")
        #expect(result.text == "abre Jira y pon Eh, este texto menciona jira.")
    }

    // MARK: Order

    @Test("fillers go before replacements, and the switch turns fillers off")
    func order() {
        let replacements = [
            ReplacementRule(spoken: "eh jira", written: "WRONG"), .init(spoken: "jira", written: "Jira"),
        ]
        #expect(rules(replacements: replacements).apply(to: "abre eh jira").text == "abre Jira")
        #expect(
            rules(replacements: replacements, removesFillers: false).apply(to: "abre eh jira").text == "abre WRONG")
    }

    @Test("with no rules the text is returned as it came")
    func none() {
        #expect(TranscriptRules.none.apply(to: "Eh, hola jira").text == "Eh, hola jira")
        #expect(TranscriptRules.none.snippet(matching: "mi firma") == nil)
    }

    // MARK: Latency

    @Test("the passes over a 200-word dictation take under 5 ms")
    func latency() {
        let sentence =
            "Eh, quería decirte que la reunión con el equipo de jira es a las 2, no, a las 3 en la sala grande, "
            + "erm, and please bring the visual studio code notes, I mean, the final ones, para revisar este informe. "
        let words = sentence.split(separator: " ")
        let text = (0..<200).map { String(words[$0 % words.count]) }.joined(separator: " ")
        let replacements =
            (0..<50).map { ReplacementRule(spoken: "term\($0)", written: "Term\($0)") } + [
                ReplacementRule(spoken: "jira", written: "Jira"),
                ReplacementRule(spoken: "visual studio code", written: "VS Code"),
            ]
        let snippets = (0..<20).map { VoiceSnippet(trigger: "snippet number \($0)", text: "Text \($0)") }
        let rules = TranscriptRules(snippets: snippets, replacements: replacements, removesFillers: true)
        _ = rules.apply(to: text)
        let clock = ContinuousClock()
        var fastest = Duration.seconds(1)
        for _ in 0..<5 {
            let elapsed = clock.measure {
                _ = rules.snippet(matching: text)
                _ = rules.apply(to: text)
            }
            fastest = min(fastest, elapsed)
        }
        #expect(fastest < .milliseconds(5), "took \(fastest)")
    }
}
