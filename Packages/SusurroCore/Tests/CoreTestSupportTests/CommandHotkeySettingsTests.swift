import CoreTestSupport
import Domain
import Testing

@Suite("Command hotkey settings")
struct CommandHotkeySettingsTests {
    @Test("the command hotkey and the switch are stored under their own names, and no key shares one")
    func names() throws {
        #expect(HotkeySettings.commandKind.storageName == "hotkey.commandKind")
        #expect(HotkeySettings.commandCombo.storageName == "hotkey.commandCombo")
        #expect(CommandSettings.enabled.storageName == "command.enabled")
        try requireUniqueStorageNames(HotkeySettings.all + CommandSettings.all)
    }

    @Test("command mode is off by default, and its hotkey is the dictation one plus Shift")
    func defaults() {
        let store = InMemorySettingsStore()

        #expect(store.value(for: CommandSettings.enabled) == false)
        #expect(store.hotkeyConfiguration(for: .command) == .command)
        #expect(HotkeyConfiguration.command.combo == HotkeyCombo(keyCode: 2, modifiers: [.control, .option, .shift]))
        #expect(store.hotkeyConfiguration(for: .dictate) == .standard)
    }

    @Test("each role keeps its own hotkey: setting the command one leaves the dictation one alone")
    func rolesAreSeparate() {
        let store = InMemorySettingsStore()
        let f5 = HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: 96, modifiers: []))

        store.setHotkey(f5, for: .command)

        #expect(store.hotkeyConfiguration(for: .command) == f5)
        #expect(store.hotkeyConfiguration() == .standard)
        store.resetHotkey(for: .command)
        #expect(store.hotkeyConfiguration(for: .command) == .command)
    }

    @Test("the active hotkeys of the other roles and the paste last shortcut are the ones a new hotkey must not repeat")
    func others() {
        let store = InMemorySettingsStore()

        #expect(store.shortcutsInUse(except: .command) == [.standard])
        #expect(store.shortcutsInUse(except: .dictate) == [], "the command hotkey is not listened to while it is off")

        store.set(true, for: CommandSettings.enabled)
        #expect(store.shortcutsInUse(except: .dictate) == [.command])

        let pasteLast = HotkeyCombo(keyCode: 9, modifiers: [.control, .option])
        store.set(pasteLast, for: PasteLastSettings.combo)
        #expect(
            store.shortcutsInUse(except: .dictate) == [.command, HotkeyConfiguration(kind: .keyed, combo: pasteLast)])
    }

    @Test("a command hotkey stored while command mode was off clashes with another shortcut only once it is turned on")
    func commandClash() {
        let store = InMemorySettingsStore()
        store.setHotkey(.command, for: .dictate)

        #expect(store.commandHotkeyClashes == false, "off: nothing is listened to, so nothing clashes")

        store.set(true, for: CommandSettings.enabled)
        #expect(store.commandHotkeyClashes, "the same hotkey as dictation")

        let chord = HotkeyConfiguration(
            kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: [.control, .option]))
        store.setHotkey(chord, for: .command)
        #expect(store.commandHotkeyClashes, "its modifiers are held on the way to the dictation hotkey")

        store.resetHotkey(for: .dictate)
        store.setHotkey(.command, for: .command)
        #expect(store.commandHotkeyClashes == false)

        store.set(HotkeyConfiguration.command.combo, for: PasteLastSettings.combo)
        #expect(store.commandHotkeyClashes, "the same keys as the paste last shortcut")
    }
}
