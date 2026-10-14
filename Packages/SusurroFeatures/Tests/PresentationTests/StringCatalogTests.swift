import Domain
import Foundation
import Testing

@testable import Presentation

/// The words of the onboarding and of the restriction are in the string catalog of the module, and the catalog says the
/// same as the English text in the code. A sentence that was edited in only one place fails here.
@Suite("String catalog", .timeLimit(.minutes(1)))
struct StringCatalogTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let value: String }
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

    @Test("the catalog is English and holds the sentences of the onboarding and of the restriction")
    func sourceLanguage() throws {
        #expect(try catalog().sourceLanguage == "en")
        #expect(try catalog().strings.keys.allSatisfy { $0.hasPrefix("onboarding.") || $0.hasPrefix("restriction.") })
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
