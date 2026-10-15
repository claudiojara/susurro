import Testing

@testable import SusurroUI

@Suite("Dictionary search")
struct DictionarySearchTests {
    @Test("an empty or blank search matches everything")
    func emptyMatchesAll() {
        #expect(DictionarySearch.matches("", "Acme"))
        #expect(DictionarySearch.matches("   ", "Acme"))
    }

    @Test("a search matches any of the texts, ignoring case and accents")
    func matches() {
        #expect(DictionarySearch.matches("acm", "Acme"))
        #expect(DictionarySearch.matches("PAGINA", "página web"))
        #expect(DictionarySearch.matches(" jira ", "ji", "Jira"))
        #expect(DictionarySearch.matches("claudio", "mi firma", "Un saludo,\nClaudio"))
        #expect(!DictionarySearch.matches("zeta", "Acme", "Beta"))
    }
}
