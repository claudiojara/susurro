import CoreTestSupport
import Domain
import Foundation
import Settings
import Testing

@Suite("Replacement rules and snippets in the dictionary store")
struct TextRulesStoreTests {
    private func rule(_ spoken: String, _ written: String) -> ReplacementRule {
        ReplacementRule(spoken: spoken, written: written)
    }

    // MARK: Replacements

    @Test("rules are added in order, trimmed, and persist across a relaunch")
    func replacementsPersist() throws {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let store = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        try store.addReplacement(rule(" jira ", "Jira\n"))
        try store.addReplacement(rule("punto com", ".com"))

        let relaunched = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        #expect(relaunched.replacements() == [rule("jira", "Jira"), rule("punto com", ".com")])
    }

    @Test("a rule needs both forms, within the length limit, and a spoken form no other rule has")
    func replacementValidation() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        #expect(throws: DictionaryError.empty) { try store.addReplacement(rule(" ", "Jira")) }
        #expect(throws: DictionaryError.empty) { try store.addReplacement(rule("jira", "")) }
        #expect(throws: DictionaryError.tooLong) {
            try store.addReplacement(rule(String(repeating: "a", count: 81), "x"))
        }
        try store.addReplacement(rule("página", "page"))
        #expect(throws: DictionaryError.duplicate) { try store.addReplacement(rule("PAGINA", "other")) }
        #expect(store.replacements() == [rule("página", "page")])
    }

    @Test("an edit replaces a rule in place, and a rule that is gone changes nothing")
    func replacementEdit() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        try store.addReplacement(rule("jira", "Jira"))
        try store.addReplacement(rule("github", "GitHub"))
        try store.editReplacement("jira", to: rule("jira", "JIRA"))
        try store.editReplacement("missing", to: rule("x", "y"))
        #expect(throws: DictionaryError.duplicate) { try store.editReplacement("jira", to: rule("GitHub", "z")) }
        #expect(store.replacements() == [rule("jira", "JIRA"), rule("github", "GitHub")])
        store.removeReplacement("JIRA")
        #expect(store.replacements() == [rule("github", "GitHub")])
    }

    @Test("the written forms with a letter join the vocabulary after the terms, without repeats")
    func vocabulary() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        try store.add("Acme")
        try store.addReplacement(rule("jira", "Jira"))
        try store.addReplacement(rule("acme", "ACME"))
        try store.addReplacement(rule("arroba", "@"))
        #expect(store.vocabularyTerms() == ["Acme", "Jira"])
        #expect(store.terms() == ["Acme"])
    }

    // MARK: Snippets

    @Test("snippets keep their lines, are added in order, and persist across a relaunch")
    func snippetsPersist() throws {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let store = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        try store.addSnippet(VoiceSnippet(trigger: " mi firma ", text: "Un saludo,\nClaudio\n"))
        try store.addSnippet(VoiceSnippet(trigger: "dirección", text: "Calle Mayor 1"))

        let relaunched = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        #expect(
            relaunched.snippets() == [
                VoiceSnippet(trigger: "mi firma", text: "Un saludo,\nClaudio"),
                VoiceSnippet(trigger: "dirección", text: "Calle Mayor 1"),
            ])
    }

    @Test("a snippet needs a trigger and a text within their limits, and a trigger no other snippet has")
    func snippetValidation() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        #expect(throws: DictionaryError.empty) { try store.addSnippet(VoiceSnippet(trigger: "", text: "x")) }
        #expect(throws: DictionaryError.empty) { try store.addSnippet(VoiceSnippet(trigger: "firma", text: " \n")) }
        #expect(throws: DictionaryError.tooLong) {
            try store.addSnippet(VoiceSnippet(trigger: "firma", text: String(repeating: "a", count: 2_001)))
        }
        try store.addSnippet(VoiceSnippet(trigger: "Dirección", text: "Calle"))
        #expect(throws: DictionaryError.duplicate) {
            try store.addSnippet(VoiceSnippet(trigger: "direccion", text: "Otra"))
        }
    }

    @Test("a snippet is edited in place and removed by its trigger")
    func snippetEdit() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        try store.addSnippet(VoiceSnippet(trigger: "firma", text: "Claudio"))
        try store.editSnippet("firma", to: VoiceSnippet(trigger: "mi firma", text: "Claudio Jara"))
        #expect(store.snippets() == [VoiceSnippet(trigger: "mi firma", text: "Claudio Jara")])
        store.removeSnippet("Mi Firma")
        #expect(store.snippets().isEmpty)
    }

    @Test("rules and snippets live under their own keys")
    func keys() throws {
        let settings = InMemorySettingsStore()
        let store = DictionaryStore(settings: settings)
        try store.addReplacement(rule("jira", "Jira"))
        try store.addSnippet(VoiceSnippet(trigger: "firma", text: "Claudio"))
        #expect(settings.value(for: TextRuleSettings.replacements) == [rule("jira", "Jira")])
        #expect(settings.value(for: TextRuleSettings.snippets) == [VoiceSnippet(trigger: "firma", text: "Claudio")])
        #expect(TextRuleSettings.replacements.storageName == "dictionary.replacements")
        #expect(TextRuleSettings.snippets.storageName == "snippets.items")
        #expect(TextRuleSettings.removeFillers.storageName == "cleanup.removeFillers")
        #expect(settings.value(for: TextRuleSettings.removeFillers))
    }
}
