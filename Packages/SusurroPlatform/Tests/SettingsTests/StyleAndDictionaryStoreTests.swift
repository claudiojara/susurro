import CoreTestSupport
import Domain
import Foundation
import Testing

@testable import Settings

@Suite("Style preferences", .timeLimit(.minutes(1)))
struct StylePreferencesTests {
    @Test("a fresh install has the default tone of every category")
    func defaults() {
        let style = SettingsStylePreferences(settings: InMemorySettingsStore())
        #expect(style.tone(for: .email) == .formal)
        #expect(style.tone(for: .workChat) == .casual)
        #expect(style.tone(for: .personalMessaging) == .veryCasual)
        #expect(style.tone(for: .document) == .neutral)
        #expect(style.tone(for: .terminal) == .verbatim)
        #expect(style.tone(for: .aiChat) == .neutral)
        #expect(style.tone(for: .other) == .neutral)
        #expect(AppCategory.allCases.allSatisfy { !style.isEdited($0) })
    }

    @Test("an edited tone is there after a relaunch, and the other categories are untouched")
    func editedTable() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let before = SettingsStylePreferences(settings: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
        before.setTone(.casual, for: .email)

        let after = SettingsStylePreferences(settings: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
        #expect(after.tone(for: .email) == .casual)
        #expect(after.isEdited(.email))
        #expect(after.tone(for: .workChat) == .casual)
        #expect(!after.isEdited(.workChat))
    }

    @Test("setting the default tone back is the same as never having edited")
    func backToDefault() {
        let style = SettingsStylePreferences(settings: InMemorySettingsStore())
        style.setTone(.casual, for: .email)
        style.setTone(.formal, for: .email)
        #expect(!style.isEdited(.email))
        #expect(style.tone(for: .email) == .formal)
    }

    @Test("overrides of category, tone, or both are kept in order and survive a relaunch")
    func overrides() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let before = SettingsStylePreferences(settings: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
        let slack = StyleOverride(target: .app(bundleID: "com.tinyspeck.slackmacgap"), category: .personalMessaging)
        let notes = StyleOverride(target: .app(bundleID: "com.apple.Notes"), tone: .casual)
        let docs = StyleOverride(target: .site(host: "docs.google.com"), category: .document, tone: .formal)
        [slack, notes, docs].forEach(before.setOverride)

        let after = SettingsStylePreferences(settings: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
        #expect(after.overrides() == [slack, notes, docs])
    }

    @Test("an override for the same app replaces the old one, and removing it removes it")
    func replaceAndRemove() {
        let style = SettingsStylePreferences(settings: InMemorySettingsStore())
        let target = StyleTarget.app(bundleID: "com.apple.Notes")
        style.setOverride(StyleOverride(target: target, tone: .casual))
        style.setOverride(StyleOverride(target: target, category: .document))
        #expect(style.overrides() == [StyleOverride(target: target, category: .document)])
        style.removeOverride(for: target)
        #expect(style.overrides().isEmpty)
    }

    @Test("an override that changes nothing removes the existing one")
    func emptyOverride() {
        let style = SettingsStylePreferences(settings: InMemorySettingsStore())
        let target = StyleTarget.site(host: "example.com")
        style.setOverride(StyleOverride(target: target, tone: .casual))
        style.setOverride(StyleOverride(target: target))
        #expect(style.overrides().isEmpty)
    }

    @Test("an app and a site with the same text are different targets")
    func appVersusSite() {
        let style = SettingsStylePreferences(settings: InMemorySettingsStore())
        style.setOverride(StyleOverride(target: .app(bundleID: "slack.com"), tone: .casual))
        style.setOverride(StyleOverride(target: .site(host: "slack.com"), tone: .formal))
        #expect(style.overrides().count == 2)
    }

    @Test("no two keys share a storage name")
    func uniqueKeys() throws {
        try requireUniqueStorageNames(SettingsStylePreferences.keys + SettingsDictionaryTerms.keys)
    }
}

@Suite("Dictionary terms", .timeLimit(.minutes(1)))
struct DictionaryTermsTests {
    @Test("added, edited, and removed terms persist across a relaunch")
    func persists() throws {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let before = SettingsDictionaryTerms(settings: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
        try before.add("Acme")
        try before.add("Maria Gonzalez")
        try before.add("kubectl")
        try before.edit("Acme", to: "ACME Corp")
        before.remove("kubectl")

        let after = SettingsDictionaryTerms(settings: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
        #expect(after.terms() == ["ACME Corp", "Maria Gonzalez"])
    }

    @Test("a term is trimmed, and an empty one is refused")
    func empty() throws {
        let terms = SettingsDictionaryTerms(settings: InMemorySettingsStore())
        try terms.add("  Acme  ")
        #expect(terms.terms() == ["Acme"])
        #expect(throws: DictionaryTermError.empty) { try terms.add("   ") }
        #expect(throws: DictionaryTermError.empty) { try terms.edit("Acme", to: "") }
        #expect(terms.terms() == ["Acme"])
    }

    @Test("a term that repeats another when case is ignored is refused, also when editing")
    func duplicates() throws {
        let terms = SettingsDictionaryTerms(settings: InMemorySettingsStore())
        try terms.add("Acme")
        try terms.add("Globex")
        #expect(throws: DictionaryTermError.duplicate) { try terms.add("ACME") }
        #expect(throws: DictionaryTermError.duplicate) { try terms.edit("Globex", to: "acme") }
        #expect(terms.terms() == ["Acme", "Globex"])
    }

    @Test("a term can be edited to a different case of itself")
    func recase() throws {
        let terms = SettingsDictionaryTerms(settings: InMemorySettingsStore())
        try terms.add("acme")
        try terms.edit("acme", to: "ACME")
        #expect(terms.terms() == ["ACME"])
    }

    @Test("a term longer than the limit is refused")
    func tooLong() {
        let terms = SettingsDictionaryTerms(settings: InMemorySettingsStore())
        let long = String(repeating: "a", count: SettingsDictionaryTerms.termLimit + 1)
        #expect(throws: DictionaryTermError.tooLong(limit: SettingsDictionaryTerms.termLimit)) { try terms.add(long) }
    }

    @Test("editing a term that is not there changes nothing")
    func missing() throws {
        let terms = SettingsDictionaryTerms(settings: InMemorySettingsStore())
        try terms.add("Acme")
        try terms.edit("Nope", to: "Other")
        #expect(terms.terms() == ["Acme"])
    }
}
