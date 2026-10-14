import CoreTestSupport
import Domain
import Foundation
import Testing

@testable import Settings

@Suite("Style settings repository", .timeLimit(.minutes(1)))
struct StyleSettingsRepositoryTests {
    @Test("every category reads as its default tone until the user changes it", arguments: StoreKind.allCases)
    func defaults(kind: StoreKind) async {
        await kind.withStore { store in
            let repository = StyleSettingsRepository(store: store)

            for category in AppCategory.allCases {
                #expect(repository.tone(for: category) == category.defaultTone)
            }
            #expect(repository.settings(for: [.bundle("com.apple.Notes")]) == .default)
        }
    }

    @Test("a tone that was edited can be brought back to its default", arguments: StoreKind.allCases)
    func resetTone(kind: StoreKind) async {
        await kind.withStore { store in
            let repository = StyleSettingsRepository(store: store)

            repository.setTone(.casual, for: .email)
            #expect(repository.tone(for: .email) == .casual)
            repository.resetTone(for: .email)

            #expect(repository.tone(for: .email) == .formal)
        }
    }

    @Test("editing the tone of email persists across a relaunch")
    func editedToneSurvivesARelaunch() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        StyleSettingsRepository(store: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
            .setTone(.casual, for: .email)

        let relaunched = StyleSettingsRepository(store: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))

        #expect(relaunched.tone(for: .email) == .casual)
        #expect(relaunched.settings(for: []).tones == [.email: .casual])
    }

    @Test("overrides of a category, a tone, and both read back", arguments: StoreKind.allCases)
    func overridesReadBack(kind: StoreKind) async {
        await kind.withStore { store in
            let repository = StyleSettingsRepository(store: store)

            repository.setOverride(StyleOverride(category: .email), for: .bundle("com.apple.Notes"))
            repository.setOverride(StyleOverride(tone: .casual), for: .bundle("com.apple.Mail"))
            repository.setOverride(StyleOverride(category: .aiChat, tone: .verbatim), for: .host("claude.ai"))

            #expect(repository.override(for: .bundle("com.apple.Notes")) == StyleOverride(category: .email))
            #expect(repository.override(for: .bundle("com.apple.Mail")) == StyleOverride(tone: .casual))
            #expect(
                repository.override(for: .host("claude.ai")) == StyleOverride(category: .aiChat, tone: .verbatim))
            #expect(repository.override(for: .bundle("com.apple.Terminal")) == nil)
        }
    }

    @Test("an override is stored apart for the app and the site of the same name", arguments: StoreKind.allCases)
    func bundleAndHostAreApart(kind: StoreKind) async {
        await kind.withStore { store in
            let repository = StyleSettingsRepository(store: store)

            repository.setOverride(StyleOverride(tone: .formal), for: .bundle("example.app"))

            #expect(repository.override(for: .host("example.app")) == nil)
        }
    }

    @Test("an override can be removed, and one that sets nothing removes it", arguments: StoreKind.allCases)
    func overridesAreRemovable(kind: StoreKind) async {
        await kind.withStore { store in
            let repository = StyleSettingsRepository(store: store)
            repository.setOverride(StyleOverride(category: .email, tone: .casual), for: .bundle("com.apple.Notes"))
            repository.setOverride(StyleOverride(tone: .casual), for: .host("claude.ai"))

            repository.removeOverride(for: .bundle("com.apple.Notes"))
            repository.setOverride(StyleOverride(), for: .host("claude.ai"))

            #expect(repository.override(for: .bundle("com.apple.Notes")) == nil)
            #expect(repository.override(for: .host("claude.ai")) == nil)
        }
    }

    @Test("an override persists across a relaunch")
    func overrideSurvivesARelaunch() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        StyleSettingsRepository(store: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
            .setOverride(StyleOverride(tone: .casual), for: .bundle("com.apple.Notes"))

        let relaunched = StyleSettingsRepository(store: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))

        #expect(relaunched.override(for: .bundle("com.apple.Notes")) == StyleOverride(tone: .casual))
    }

    @Test("each value has a key of its own, and the target is escaped so that no key part holds a dot")
    func perKeyStorage() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let raw = scratch.makeDefaults()
        let repository = StyleSettingsRepository(store: UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))

        repository.setTone(.casual, for: .email)
        repository.setOverride(StyleOverride(category: .document, tone: .formal), for: .bundle("com.apple.Notes"))

        #expect(raw.string(forKey: "style.tone-email") == "casual")
        #expect(raw.string(forKey: "style.override-category-bundle-com%2Eapple%2ENotes") == "document")
        #expect(raw.string(forKey: "style.override-tone-bundle-com%2Eapple%2ENotes") == "formal")
    }

    @Test("targets that differ only by a dot or a percent sign do not share a key")
    func escapingIsInjective() {
        #expect(StyleSettingsRepository.escaped("a.b") != StyleSettingsRepository.escaped("a%2Eb"))
        #expect(StyleSettingsRepository.escaped("a.b") == "a%2Eb")
    }

    @Test("an unreadable stored category reads as no override instead of failing", arguments: StoreKind.allCases)
    func damagedValue(kind: StoreKind) async {
        await kind.withStore { store in
            let repository = StyleSettingsRepository(store: store)
            let key = SettingKey<String>(
                area: "style", name: "override-category-bundle-com%2Eapple%2ENotes", default: "")
            store.set("not_a_category", for: key)

            #expect(repository.override(for: .bundle("com.apple.Notes")) == nil)
        }
    }

    @Test("the settings of a dictation hold the edited tones and the overrides of the targets asked for")
    func settingsForTargets() {
        let store = InMemorySettingsStore()
        let repository = StyleSettingsRepository(store: store)
        repository.setTone(.casual, for: .email)
        repository.setOverride(StyleOverride(tone: .verbatim), for: .host("slack.com"))
        repository.setOverride(StyleOverride(tone: .formal), for: .bundle("com.apple.Notes"))

        let settings = repository.settings(for: [.host("app.slack.com"), .host("slack.com")])

        #expect(
            settings
                == StyleSettings(
                    tones: [.email: .casual], overrides: [.host("slack.com"): StyleOverride(tone: .verbatim)]))
    }
}
