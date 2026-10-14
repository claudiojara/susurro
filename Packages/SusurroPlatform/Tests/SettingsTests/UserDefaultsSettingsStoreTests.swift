import CoreTestSupport
import Domain
import Foundation
import Testing

@testable import Settings

@Suite("User defaults settings store", .timeLimit(.minutes(1)))
struct UserDefaultsSettingsStoreTests {
    @Test("each value is stored in its own form under the key's name")
    func storedForms() throws {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let raw = scratch.makeDefaults()
        let store = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())
        let combo = SampleCombo(keyCode: 40, modifiers: ["command"])

        store.set(false, for: SampleKeys.launchAtLogin)
        store.set(30, for: SampleKeys.retentionDays)
        store.set(0.45, for: SampleKeys.holdThreshold)
        store.set("es", for: SampleKeys.language)
        store.set(.top, for: SampleKeys.overlayEdge)
        store.set(combo, for: SampleKeys.combo)

        #expect(raw.object(forKey: "general.launchAtLogin") as? Bool == false)
        #expect(raw.object(forKey: "history.retentionDays") as? Int == 30)
        #expect(raw.object(forKey: "hotkey.holdThreshold") as? Double == 0.45)
        #expect(raw.string(forKey: "speech.language") == "es")
        #expect(raw.string(forKey: "overlay.edge") == "screen-top")
        let json = try #require(raw.data(forKey: "hotkey.combo"))
        #expect(try JSONDecoder().decode(SampleCombo.self, from: json) == combo)
    }

    @Test("what was set is there after a relaunch")
    func survivesARelaunch() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let combo = SampleCombo(keyCode: 40, modifiers: ["command"])
        let before = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())
        before.set(false, for: SampleKeys.launchAtLogin)
        before.set(.top, for: SampleKeys.overlayEdge)
        before.set(combo, for: SampleKeys.combo)

        let after = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())

        #expect(after.value(for: SampleKeys.launchAtLogin) == false)
        #expect(after.value(for: SampleKeys.overlayEdge) == .top)
        #expect(after.value(for: SampleKeys.combo) == combo)
        #expect(after.value(for: SampleKeys.retentionDays) == 7)
    }

    @Test("a value whose number looks like another kind still reads back as its own kind, also after a relaunch")
    func lookalikeNumbersRoundTrip() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let asFlag = SettingKey<Bool>(area: "lookalike", name: "flag", default: true)
        let asCount = SettingKey<Int>(area: "lookalike", name: "count", default: 7)
        let asSeconds = SettingKey<Double>(area: "lookalike", name: "seconds", default: 0.3)
        let before = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())

        before.set(false, for: asFlag)
        before.set(1, for: asCount)
        before.set(2.0, for: asSeconds)
        let after = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())

        for store in [before, after] {
            #expect(store.value(for: asFlag) == false)
            #expect(store.value(for: asCount) == 1)
            #expect(store.value(for: asSeconds) == 2.0)
        }
        before.set(0, for: asCount)
        before.set(1.0, for: asSeconds)
        #expect(UserDefaultsSettingsStore(defaults: scratch.makeDefaults()).value(for: asCount) == 0)
        #expect(UserDefaultsSettingsStore(defaults: scratch.makeDefaults()).value(for: asSeconds) == 1.0)
    }

    @Test("a corrupt key reads as its default, the other keys are not affected, and a set repairs it")
    func corruptKeyIsIsolated() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let raw = scratch.makeDefaults()
        let store = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())
        store.set(30, for: SampleKeys.retentionDays)
        store.set("es", for: SampleKeys.language)
        raw.set("maybe", forKey: "general.launchAtLogin")
        raw.set("diagonal", forKey: "overlay.edge")
        raw.set(Data("{".utf8), forKey: "hotkey.combo")
        raw.set("fast", forKey: "hotkey.holdThreshold")

        #expect(store.value(for: SampleKeys.launchAtLogin) == true)
        #expect(store.value(for: SampleKeys.overlayEdge) == .bottom)
        #expect(store.value(for: SampleKeys.combo) == SampleKeys.defaultCombo)
        #expect(store.value(for: SampleKeys.holdThreshold) == 0.3)
        #expect(store.value(for: SampleKeys.retentionDays) == 30)
        #expect(store.value(for: SampleKeys.language) == "es")

        store.set(false, for: SampleKeys.launchAtLogin)
        #expect(store.value(for: SampleKeys.launchAtLogin) == false)
    }

    @Test("every corrupt key is reported by its name, and what it held is not in the report")
    func corruptKeysAreReported() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let raw = scratch.makeDefaults()
        let diagnostics = RecordingDiagnostics()
        let store = UserDefaultsSettingsStore(defaults: scratch.makeDefaults(), diagnostics: diagnostics)
        raw.set("maybe-secret", forKey: "general.launchAtLogin")
        raw.set("diagonal-secret", forKey: "overlay.edge")
        raw.set(Data("{secret".utf8), forKey: "hotkey.combo")
        raw.set("fast-secret", forKey: "hotkey.holdThreshold")

        _ = store.value(for: SampleKeys.launchAtLogin)
        _ = store.value(for: SampleKeys.overlayEdge)
        _ = store.value(for: SampleKeys.combo)
        _ = store.value(for: SampleKeys.holdThreshold)
        _ = store.value(for: SampleKeys.retentionDays)

        #expect(
            diagnostics.events == [
                .settingUnreadable(key: "general.launchAtLogin"), .settingUnreadable(key: "overlay.edge"),
                .settingUnreadable(key: "hotkey.combo"), .settingUnreadable(key: "hotkey.holdThreshold"),
            ])
        #expect(!String(describing: diagnostics.events).contains("secret"))
    }

    @Test("removing a key deletes it from the preferences instead of storing its default")
    func removeDeletesTheKey() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let raw = scratch.makeDefaults()
        let store = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())
        store.set(30, for: SampleKeys.retentionDays)
        store.set("es", for: SampleKeys.language)

        store.remove(SampleKeys.retentionDays)

        #expect(raw.object(forKey: "history.retentionDays") == nil)
        #expect(raw.string(forKey: "speech.language") == "es")
        #expect(UserDefaultsSettingsStore(defaults: scratch.makeDefaults()).value(for: SampleKeys.retentionDays) == 7)
    }

    @Test("cleanup is off for a fresh install, and a switch that was stored as on while it was the default stays on")
    func cleanupSwitchSurvivesTheNewDefault() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        #expect(
            UserDefaultsSettingsStore(defaults: scratch.makeDefaults()).value(for: CleanupSettings.enabled) == false)

        // What an earlier version, or the user, wrote under the key's name.
        scratch.makeDefaults().set(true, forKey: "cleanup.enabled")
        #expect(UserDefaultsSettingsStore(defaults: scratch.makeDefaults()).value(for: CleanupSettings.enabled))
    }

    @Test("a key that was never written is not created by reading it")
    func readingWritesNothing() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let raw = scratch.makeDefaults()
        let store = UserDefaultsSettingsStore(defaults: scratch.makeDefaults())

        _ = store.value(for: SampleKeys.launchAtLogin)

        #expect(raw.object(forKey: "general.launchAtLogin") == nil)
    }
}
