import DesignSystem
import Domain
import Foundation
import Testing

@testable import Presentation

/// Every word of the module is in its string catalog, in English and in Spanish, and the catalog says the same as the
/// English text in the code. A sentence that was edited in only one place, or left without a translation, fails here.
@Suite("String catalog", .timeLimit(.minutes(1)))
struct StringCatalogTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable {
                    let state: String
                    let value: String
                }
                let stringUnit: Unit
            }
            let localizations: [String: Localization]
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func catalog() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.sourceURL))
    }

    /// The catalog as it is in the source tree: the build compiles it into the bundle, and the source is what is edited.
    private static let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Presentation/Resources/Localizable.xcstrings")

    private func english(_ key: String) throws -> String {
        try #require(catalog().strings[key]?.localizations["en"]?.stringUnit.value, "no entry for \(key)")
    }

    @Test("the catalog is English, and every key has a translated English and Spanish sentence")
    func everyKeyIsTranslated() throws {
        let catalog = try catalog()
        #expect(catalog.sourceLanguage == "en")
        for (key, entry) in catalog.strings {
            for language in ["en", "es"] {
                let unit = entry.localizations[language]?.stringUnit
                #expect(unit?.state == "translated", "\(key) has no \(language) sentence")
                #expect(unit?.value.isEmpty == false, "\(key) is empty in \(language)")
            }
        }
    }

    @Test("a Spanish sentence takes the same values as the English one")
    func placeholdersAgree() throws {
        for (key, entry) in try catalog().strings {
            let english = entry.localizations["en"].map { Self.placeholders($0.stringUnit.value) }
            let spanish = entry.localizations["es"].map { Self.placeholders($0.stringUnit.value) }
            #expect(english == spanish, "\(key) has other placeholders in Spanish")
        }
    }

    @Test("every key the code looks up is in the catalog, and the catalog has no key the code does not use")
    func keysMatchTheCode() throws {
        let used = try Self.keysInSources()
        let listed = Set(try catalog().strings.keys)
        #expect(used.subtracting(listed).sorted() == [])
        #expect(listed.subtracting(used).sorted() == [])
    }

    /// The format specifiers of a sentence, `%%` left out, in order.
    private static func placeholders(_ text: String) -> [String] {
        text.replacing("%%", with: "").matches(of: /%(?:\d+\$)?(?:lld|ld|d|@|f)/).map { String($0.output) }
    }

    /// The keys of every `L10n.string("key", ...)` in the sources of the module.
    private static func keysInSources() throws -> Set<String> {
        let root = sourceURL.deletingLastPathComponent().deletingLastPathComponent()
        let files =
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var keys: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: /L10n\.string\(\s*"([^"]+)"/) { keys.insert(String(match.output.1)) }
        }
        return keys
    }

    @Test("a sentence of the code is the sentence of the catalog")
    func sentencesAgree() throws {
        #expect(OnboardingCopy.title == (try english("onboarding.title")))
        #expect(OnboardingCopy.subtitle == (try english("onboarding.subtitle")))
        #expect(OnboardingCopy.recheckTitle == (try english("onboarding.recheck")))
        #expect(OnboardingCopy.doneTitle == (try english("onboarding.done")))
        #expect(OnboardingCopy.openSettingsAction.title == (try english("onboarding.action.openSettings")))
        #expect(OnboardingCopy.why(.microphone) == (try english("onboarding.why.microphone")))
        #expect(OnboardingCopy.why(.accessibility) == (try english("onboarding.why.accessibility")))
        #expect(OnboardingCopy.why(.inputMonitoring) == (try english("onboarding.why.inputMonitoring")))
        #expect(OnboardingCopy.why(.screenRecording) == (try english("onboarding.why.screenRecording")))
        #expect(OnboardingCopy.statusText(.granted) == (try english("onboarding.status.granted")))
        #expect(OnboardingCopy.statusText(.waiting) == (try english("onboarding.status.waiting")))
        #expect(
            DictationRestriction(missing: [.microphone])?.message == (try english("restriction.microphone")))
        #expect(
            DictationRestriction(missing: [.accessibility])?.message == (try english("restriction.accessibility")))
    }

    @Test("a sentence with a name in it takes the name where the catalog puts the placeholder")
    func placeholders() throws {
        #expect(try english("onboarding.action.allow") == "Allow %@")
        #expect(OnboardingCopy.requestAction(.accessibility).title == "Allow Accessibility")
        #expect(
            OnboardingCopy.requirement(.screenRecording)
                == .optional(
                    featureNote: "Optional: only for reading on-screen text. Dictation works without it."))
    }
}

/// The words come in the language the user picked, whatever the system prefers. A task pins the language, so these run
/// beside the English tests.
@Suite("Spanish words", .timeLimit(.minutes(1)))
struct SpanishCopyTests {
    private func inSpanish<T>(_ body: () throws -> T) rethrows -> T {
        try InterfaceLocale.$override.withValue("es", operation: body)
    }

    @Test("the onboarding, the restriction and a permission name are in Spanish")
    func onboarding() {
        inSpanish {
            #expect(OnboardingCopy.title == "Configurar Susurro")
            #expect(OnboardingCopy.requestAction(.microphone).title == "Permitir Micrófono")
            #expect(
                DictationRestriction(missing: [.microphone])?.message
                    == "El dictado está desactivado hasta que se permita Micrófono.")
        }
    }

    @Test("a sentence with a number keeps the number and the percent sign")
    func numbers() {
        inSpanish {
            #expect(
                OverlayMapping.modelLoading(progress: 0.5)
                    == .transcribing(text: "Preparando el modelo de voz… 50%", progress: 0.5))
            #expect(SettingsCopy.loading(0.25) == "Cargando el modelo, 25 %.")
            #expect(SettingsCopy.termTooLong(64) == "Un término puede tener como máximo 64 caracteres.")
            #expect(HistoryCopy.audioNotDeleted(count: 3).hasPrefix("No se pudo eliminar el audio de 3 dictados"))
        }
    }

    @Test("the menu is in Spanish")
    func menu() {
        inSpanish {
            let content = MenuContent.make(
                microphone: .granted, accessibility: .denied, restriction: nil, readiness: .ready)
            #expect(content.microphone.title == "Micrófono: permitido")
            #expect(content.accessibility.title == "Accesibilidad: no permitido")
            #expect(content.modelLine == "Modelo de voz: listo")
            #expect(content.hotkeyHint == "Mantén Control-Opción-D para dictar")
        }
    }

    @Test("the same words are English again outside the pinned task")
    func englishByDefault() {
        #expect(OnboardingCopy.title == "Set up Susurro")
        #expect(HistoryCopy.title == "History")
    }
}
