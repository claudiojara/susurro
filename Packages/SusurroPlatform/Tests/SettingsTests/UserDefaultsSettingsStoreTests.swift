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
        let store = UserDefaultsSettingsStore(defaults: scratch.defaults)
        let combo = SampleCombo(keyCode: 40, modifiers: ["command"])

        store.set(false, for: SampleKeys.launchAtLogin)
        store.set(30, for: SampleKeys.retentionDays)
        store.set(0.45, for: SampleKeys.holdThreshold)
        store.set("es", for: SampleKeys.language)
        store.set(.top, for: SampleKeys.overlayEdge)
        store.set(combo, for: SampleKeys.combo)

        #expect(scratch.defaults.object(forKey: "general.launchAtLogin") as? Bool == false)
        #expect(scratch.defaults.object(forKey: "history.retentionDays") as? Int == 30)
        #expect(scratch.defaults.object(forKey: "hotkey.holdThreshold") as? Double == 0.45)
        #expect(scratch.defaults.string(forKey: "speech.language") == "es")
        #expect(scratch.defaults.string(forKey: "overlay.edge") == "top")
        let json = try #require(scratch.defaults.data(forKey: "hotkey.combo"))
        #expect(try JSONDecoder().decode(SampleCombo.self, from: json) == combo)
    }

    @Test("what was set is there after a relaunch")
    func survivesARelaunch() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let combo = SampleCombo(keyCode: 40, modifiers: ["command"])
        let before = UserDefaultsSettingsStore(defaults: scratch.defaults)
        before.set(false, for: SampleKeys.launchAtLogin)
        before.set(.top, for: SampleKeys.overlayEdge)
        before.set(combo, for: SampleKeys.combo)

        let after = UserDefaultsSettingsStore(defaults: scratch.reopened())

        #expect(after.value(for: SampleKeys.launchAtLogin) == false)
        #expect(after.value(for: SampleKeys.overlayEdge) == .top)
        #expect(after.value(for: SampleKeys.combo) == combo)
        #expect(after.value(for: SampleKeys.retentionDays) == 7)
    }

    @Test("a corrupt key reads as its default, the other keys are not affected, and a set repairs it")
    func corruptKeyIsIsolated() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let store = UserDefaultsSettingsStore(defaults: scratch.defaults)
        store.set(30, for: SampleKeys.retentionDays)
        store.set("es", for: SampleKeys.language)
        scratch.defaults.set("maybe", forKey: "general.launchAtLogin")
        scratch.defaults.set("diagonal", forKey: "overlay.edge")
        scratch.defaults.set(Data("{".utf8), forKey: "hotkey.combo")
        scratch.defaults.set("fast", forKey: "hotkey.holdThreshold")

        #expect(store.value(for: SampleKeys.launchAtLogin) == true)
        #expect(store.value(for: SampleKeys.overlayEdge) == .bottom)
        #expect(store.value(for: SampleKeys.combo) == SampleKeys.defaultCombo)
        #expect(store.value(for: SampleKeys.holdThreshold) == 0.3)
        #expect(store.value(for: SampleKeys.retentionDays) == 30)
        #expect(store.value(for: SampleKeys.language) == "es")

        store.set(false, for: SampleKeys.launchAtLogin)
        #expect(store.value(for: SampleKeys.launchAtLogin) == false)
    }

    @Test("a key that was never written is not created by reading it")
    func readingWritesNothing() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let store = UserDefaultsSettingsStore(defaults: scratch.defaults)

        _ = store.value(for: SampleKeys.launchAtLogin)

        #expect(scratch.defaults.object(forKey: "general.launchAtLogin") == nil)
    }
}
