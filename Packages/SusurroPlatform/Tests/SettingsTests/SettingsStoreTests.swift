import Domain
import Testing

/// What every `SettingsStore` must do, run against the real store and against the in-memory fake that tests in other
/// packages use, so the fake cannot drift from the real thing.
@Suite("Settings stores", .timeLimit(.minutes(1)))
struct SettingsStoreTests {
    @Test("a key nobody set reads as its default", arguments: StoreKind.allCases)
    func unsetKeysReadAsTheirDefaults(kind: StoreKind) async {
        await kind.withStore { store in
            #expect(store.value(for: SampleKeys.launchAtLogin) == true)
            #expect(store.value(for: SampleKeys.retentionDays) == 7)
            #expect(store.value(for: SampleKeys.holdThreshold) == 0.3)
            #expect(store.value(for: SampleKeys.language) == "auto")
            #expect(store.value(for: SampleKeys.overlayEdge) == .bottom)
            #expect(store.value(for: SampleKeys.combo) == SampleKeys.defaultCombo)
        }
    }

    @Test("a value that was set reads back, and a later set replaces it", arguments: StoreKind.allCases)
    func setThenGet(kind: StoreKind) async {
        let combo = SampleCombo(keyCode: 40, modifiers: ["command"])
        await kind.withStore { store in
            store.set(false, for: SampleKeys.launchAtLogin)
            store.set(30, for: SampleKeys.retentionDays)
            store.set(0.45, for: SampleKeys.holdThreshold)
            store.set("es", for: SampleKeys.language)
            store.set(.top, for: SampleKeys.overlayEdge)
            store.set(combo, for: SampleKeys.combo)

            #expect(store.value(for: SampleKeys.launchAtLogin) == false)
            #expect(store.value(for: SampleKeys.retentionDays) == 30)
            #expect(store.value(for: SampleKeys.holdThreshold) == 0.45)
            #expect(store.value(for: SampleKeys.language) == "es")
            #expect(store.value(for: SampleKeys.overlayEdge) == .top)
            #expect(store.value(for: SampleKeys.combo) == combo)

            store.set("en", for: SampleKeys.language)
            #expect(store.value(for: SampleKeys.language) == "en")
        }
    }

    @Test("setting a key leaves every other key as it was", arguments: StoreKind.allCases)
    func keysAreIndependent(kind: StoreKind) async {
        await kind.withStore { store in
            store.set(30, for: SampleKeys.retentionDays)

            store.set("es", for: SampleKeys.language)

            #expect(store.value(for: SampleKeys.retentionDays) == 30)
            #expect(store.value(for: SampleKeys.launchAtLogin) == true)
        }
    }

    @Test("a key read as another type than it was set as reads as its default", arguments: StoreKind.allCases)
    func typeMismatch(kind: StoreKind) async {
        let asText = SettingKey<String>("general.launchAtLogin", default: "fallback")
        await kind.withStore { store in
            store.set(false, for: SampleKeys.launchAtLogin)

            #expect(store.value(for: asText) == "fallback")
            #expect(store.value(for: SampleKeys.launchAtLogin) == false)
        }
    }

    @Test(
        "a set emits the name of the key it changed, in order, and a read emits nothing", arguments: StoreKind.allCases)
    func changesFollowTheSets(kind: StoreKind) async {
        await kind.withStore { store in
            var changes = store.changes().makeAsyncIterator()

            _ = store.value(for: SampleKeys.retentionDays)
            store.set(false, for: SampleKeys.launchAtLogin)
            store.set(.top, for: SampleKeys.overlayEdge)

            #expect(await changes.next() == SettingChange(name: "general.launchAtLogin"))
            #expect(await changes.next() == SettingChange(name: "overlay.edge"))
        }
    }

    @Test(
        "a subscriber gets the changes made after it subscribed, and a set reaches every subscriber",
        arguments: StoreKind.allCases)
    func subscribers(kind: StoreKind) async {
        await kind.withStore { store in
            store.set(30, for: SampleKeys.retentionDays)
            var first = store.changes().makeAsyncIterator()
            var second = store.changes().makeAsyncIterator()

            store.set("es", for: SampleKeys.language)

            #expect(await first.next() == SettingChange(name: "speech.language"))
            #expect(await second.next() == SettingChange(name: "speech.language"))
        }
    }
}
