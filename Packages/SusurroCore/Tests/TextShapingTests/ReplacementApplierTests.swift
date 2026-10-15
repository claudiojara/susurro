import Domain
import Testing

@testable import TextShaping

@Suite("Replacement rules")
struct ReplacementApplierTests {
    private func apply(_ text: String, _ rules: [(String, String)]) -> String {
        ReplacementApplier(rules: rules.map { ReplacementRule(spoken: $0.0, written: $0.1) }).apply(text)
    }

    @Test("a spoken form is written as the rule says, whatever its case")
    func caseInsensitive() {
        #expect(apply("abre un ticket en jira", [("jira", "Jira")]) == "abre un ticket en Jira")
        #expect(apply("JIRA está caído. Jira también.", [("jira", "Jira")]) == "Jira está caído. Jira también.")
    }

    @Test("only whole words match")
    func wholeWords() {
        #expect(apply("la jirafa come", [("jira", "Jira")]) == "la jirafa come")
        #expect(apply("superjira", [("jira", "Jira")]) == "superjira")
        #expect(apply("jira's board", [("jira", "Jira")]) == "jira's board")
    }

    @Test("accents and case are ignored on both sides, and ñ stays a letter of its own")
    func accents() {
        #expect(apply("la pagina web", [("página web", "website")]) == "la website")
        #expect(apply("la página web", [("pagina web", "website")]) == "la website")
        #expect(apply("Última versión", [("ultima version", "v2")]) == "v2")
        #expect(apply("el año pasado", [("ano", "X")]) == "el año pasado")
        #expect(apply("el ano", [("año", "X")]) == "el ano")
    }

    @Test("a phrase of several words matches across any spacing, and the longest rule wins")
    func phrases() {
        #expect(apply("escribe a punto com", [("punto com", ".com")]) == "escribe a .com")
        #expect(
            apply("visual  studio code", [("visual studio", "VS"), ("visual studio code", "VS Code")]) == "VS Code")
        #expect(apply("visual studio", [("visual studio", "VS"), ("visual studio code", "VS Code")]) == "VS")
    }

    @Test("punctuation around a match stays, and a replaced text is not matched again")
    func punctuationAndSinglePass() {
        #expect(apply("¿Viste jira?", [("jira", "Jira")]) == "¿Viste Jira?")
        #expect(apply("uno dos", [("uno", "dos"), ("dos", "tres")]) == "dos tres")
    }

    @Test("no rules, or a blank rule, change nothing")
    func noRules() {
        #expect(apply("hola equipo", []) == "hola equipo")
        #expect(apply("hola equipo", [("  ", "x")]) == "hola equipo")
    }
}
