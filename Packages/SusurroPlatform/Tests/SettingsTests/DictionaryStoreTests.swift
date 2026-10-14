import CoreTestSupport
import Domain
import Foundation
import Settings
import Testing

@Suite("Dictionary store")
struct DictionaryStoreTests {
    @Test("terms are added in order and persist across a relaunch")
    func addPersists() throws {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let store = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        try store.add("Acme")
        try store.add("Maria Gonzalez")

        let relaunched = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        #expect(relaunched.terms() == ["Acme", "Maria Gonzalez"])
    }

    @Test("an edit and a removal persist across a relaunch")
    func editAndRemovePersist() throws {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let store = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        for term in ["Acme", "Beta", "Gamma"] { try store.add(term) }
        try store.replace("Beta", with: "Delta")
        store.remove("Gamma")

        let relaunched = DictionaryStore(settings: StoreKind.userDefaults.make(scratch: scratch))
        #expect(relaunched.terms() == ["Acme", "Delta"])
    }

    @Test("an empty term is refused, and so is a blank one")
    func emptyIsRefused() {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        #expect(throws: DictionaryError.empty) { try store.add("") }
        #expect(throws: DictionaryError.empty) { try store.add("   \n") }
        #expect(store.terms().isEmpty)
    }

    @Test("a duplicate is refused without regard to case or surrounding space")
    func duplicateIsRefused() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        try store.add("Acme")
        #expect(throws: DictionaryError.duplicate) { try store.add("acme") }
        #expect(throws: DictionaryError.duplicate) { try store.add(" ACME ") }
        #expect(store.terms() == ["Acme"])
    }

    @Test("a term of more than 40 characters is refused")
    func tooLongIsRefused() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        #expect(throws: DictionaryError.tooLong) { try store.add(String(repeating: "a", count: 41)) }
        try store.add(String(repeating: "a", count: 40))
        #expect(store.terms().count == 1)
    }

    @Test("an edit may change only the case of a term, but not collide with another")
    func editRules() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        try store.add("acme")
        try store.add("Beta")
        try store.replace("acme", with: "Acme")
        #expect(store.terms() == ["Acme", "Beta"])
        #expect(throws: DictionaryError.duplicate) { try store.replace("Acme", with: "beta") }
        #expect(throws: DictionaryError.empty) { try store.replace("Acme", with: " ") }
        #expect(throws: DictionaryError.notFound) { try store.replace("Missing", with: "Other") }
        #expect(store.terms() == ["Acme", "Beta"])
    }

    @Test("terms are trimmed when they are added")
    func trimmed() throws {
        let store = DictionaryStore(settings: InMemorySettingsStore())
        try store.add("  Acme\n")
        #expect(store.terms() == ["Acme"])
    }

    @Test("the dictionary is one list under one key")
    func oneKey() throws {
        let settings = InMemorySettingsStore()
        let store = DictionaryStore(settings: settings)
        try store.add("Acme")
        #expect(settings.value(for: DictionarySettings.terms) == ["Acme"])
        #expect(DictionarySettings.terms.storageName == "dictionary.terms")
    }
}
