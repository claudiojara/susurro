import CoreTestSupport
import Testing

@testable import Domain

@Suite("Interface language")
struct InterfaceLanguageTests {
    @Test("a fresh install follows the system, and the user's choice is kept")
    func persistence() {
        let store = InMemorySettingsStore()
        #expect(store.value(for: GeneralSettings.interfaceLanguage) == .system)
        store.set(.spanish, for: GeneralSettings.interfaceLanguage)
        #expect(store.value(for: GeneralSettings.interfaceLanguage) == .spanish)
        store.set(.english, for: GeneralSettings.interfaceLanguage)
        #expect(store.value(for: GeneralSettings.interfaceLanguage) == .english)
    }

    @Test("the setting is stored apart from the dictation language")
    func separateFromDictation() throws {
        #expect(GeneralSettings.interfaceLanguage.storageName != SpeechSettings.languageMode.storageName)
        try requireUniqueStorageNames(SpeechSettings.all + CleanupSettings.all + GeneralSettings.all)
    }

    @Test("a chosen language is used whatever the system prefers")
    func chosen() {
        #expect(InterfaceLanguage.english.resolved(preferredLanguages: ["es-CL"]) == "en")
        #expect(InterfaceLanguage.spanish.resolved(preferredLanguages: ["en-US"]) == "es")
    }

    @Test(
        "the system choice takes the first preferred language the app has, else English",
        arguments: [
            (["es-CL", "en-US"], "es"), (["en-GB", "es"], "en"), (["fr-FR", "es-419"], "es"), (["de-DE"], "en"),
            ([], "en"), (["ES"], "es"),
        ])
    func system(preferred: [String], expected: String) {
        #expect(InterfaceLanguage.system.resolved(preferredLanguages: preferred) == expected)
    }
}
