import DesignSystem
import Foundation
import Testing

@testable import SusurroUI

/// Every word of the views is in the string catalog of the module, in English and in Spanish, with the same placeholders
/// in both. A word left without a translation, or a key the code no longer uses, fails here.
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
        .appendingPathComponent("Sources/SusurroUI/Resources/Localizable.xcstrings")

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
}

/// The words of the views come in the language the user picked. A task pins the language, so these run beside the
/// English snapshots.
@MainActor
@Suite("Spanish words of the views", .timeLimit(.minutes(1)))
struct SpanishViewCopyTests {
    @Test("the tabs of the settings are named in Spanish, and in English outside the pinned task")
    func tabs() {
        InterfaceLocale.$override.withValue("es") {
            #expect(
                SettingsTab.allCases.map(\.title) == [
                    "General", "Proveedores", "Atajo", "Estilo", "Diccionario", "Apariencia",
                ])
        }
        #expect(SettingsTab.general.title == "General")
        #expect(SettingsTab.providers.title == "Providers")
    }
}
