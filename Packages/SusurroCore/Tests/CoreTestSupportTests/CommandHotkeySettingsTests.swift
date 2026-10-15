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

    @Test("the hotkeys of the other roles and the paste last shortcut are the ones a new hotkey must not repeat")
    func others() {
        let store = InMemorySettingsStore()

        #expect(store.shortcutsInUse(except: .command) == [.standard])
        #expect(store.shortcutsInUse(except: .dictate) == [.command])

        let pasteLast = HotkeyCombo(keyCode: 9, modifiers: [.control, .option])
        store.set(pasteLast, for: PasteLastSettings.combo)
        #expect(
            store.shortcutsInUse(except: .dictate) == [.command, HotkeyConfiguration(kind: .keyed, combo: pasteLast)])
    }
}
