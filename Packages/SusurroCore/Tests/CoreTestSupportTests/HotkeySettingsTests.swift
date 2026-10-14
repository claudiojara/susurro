import CoreTestSupport
import Domain
import Testing

@Suite("Hotkey and overlay settings")
struct HotkeySettingsTests {
    @Test("the keys are stored under their own names, and no key shares one")
    func names() throws {
        #expect(HotkeySettings.kind.storageName == "hotkey.kind")
        #expect(HotkeySettings.combo.storageName == "hotkey.combo")
        #expect(OverlaySettings.variant.storageName == "overlay.variant")
        #expect(OverlaySettings.edge.storageName == "overlay.edge")
        try requireUniqueStorageNames(HotkeySettings.all + OverlaySettings.all)
    }

    @Test("a store that holds nothing gives the default hotkey, a keyed Control+Option+D")
    func defaults() {
        let store = InMemorySettingsStore()

        #expect(store.hotkeyConfiguration() == .standard)
        #expect(store.hotkeyConfiguration().combo == HotkeyCombo(keyCode: 2, modifiers: [.control, .option]))
        #expect(store.value(for: OverlaySettings.edge) == .followTheme)
        #expect(store.value(for: OverlaySettings.variant) == "pill")
    }

    @Test("a configured hotkey comes back as it was stored")
    func roundTrip() {
        let store = InMemorySettingsStore()
        let fn = HotkeyCombo(keyCode: nil, modifiers: .function)

        store.set(HotkeyKind.modifierOnly, for: HotkeySettings.kind)
        store.set(fn, for: HotkeySettings.combo)

        #expect(store.hotkeyConfiguration() == HotkeyConfiguration(kind: .modifierOnly, combo: fn))
    }
}
