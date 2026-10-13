import Carbon.HIToolbox
import KeyboardShortcuts
import Testing

@testable import Hotkeys

@Suite("Default hotkey")
struct DefaultHotkeyTests {
    /// Changing the default is deliberate: re-run the macOS shortcut collision check in ADR 0005 first.
    @Test("hold-to-talk is Control+Option+D")
    func holdToTalkCombo() {
        let expected = KeyboardShortcuts.Shortcut(
            carbonKeyCode: kVK_ANSI_D,
            carbonModifiers: controlKey | optionKey
        )

        #expect(DefaultHotkey.holdToTalk == expected)
    }
}
