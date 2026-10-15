import CoreTestSupport
import Domain
import Testing

@Suite("Microphone choice")
struct MicrophoneChoiceTests {
    private let builtIn = AudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
    private let usb = AudioInputDevice(uid: "AppleUSBAudioEngine:Yeti", name: "Yeti")

    @Test("no stored device is the system default")
    func systemDefault() {
        #expect(MicrophoneChoice.resolve(preferredUID: "", available: [builtIn, usb]) == .systemDefault)
    }

    @Test("a stored device that is connected is used")
    func connected() {
        #expect(MicrophoneChoice.resolve(preferredUID: usb.uid, available: [builtIn, usb]) == .device(uid: usb.uid))
    }

    @Test("a stored device that is not connected falls back to the system default")
    func missing() {
        #expect(MicrophoneChoice.resolve(preferredUID: usb.uid, available: [builtIn]) == .missing(uid: usb.uid))
    }

    @Test("the setting is empty by default, so nothing changes for a user who never chose")
    func defaultSetting() {
        #expect(InMemorySettingsStore().value(for: MicrophoneSettings.deviceUID) == "")
    }

    @Test("the new settings keys do not collide with any other")
    func uniqueKeys() throws {
        try requireUniqueStorageNames(
            MicrophoneSettings.all + MediaSettings.all + PasteLastSettings.all + HotkeySettings.all
                + OverlaySettings.all)
    }

    @Test("the paste last dictation shortcut is unassigned by default")
    func pasteLastDefault() {
        #expect(InMemorySettingsStore().value(for: PasteLastSettings.combo) == nil)
    }

    @Test("the pause media setting is off by default")
    func mediaDefault() {
        #expect(InMemorySettingsStore().value(for: MediaSettings.pauseWhileDictating) == false)
    }
}

@Suite("Paste last dictation shortcut validation")
struct PasteLastValidationTests {
    private let notTaken: (HotkeyCombo) -> Bool = { _ in false }

    @Test("a keyed combo that follows the hotkey rules and is not the dictation hotkey is allowed")
    func allowed() {
        let combo = HotkeyCombo(keyCode: 9, modifiers: [.control, .option])
        #expect(
            PasteLastValidation.rejection(
                of: HotkeyConfiguration(kind: .keyed, combo: combo), dictation: .standard, isTakenBySystem: notTaken)
                == nil)
    }

    @Test("modifier keys alone are refused, since a press of them is not a key to tap")
    func modifierOnly() {
        let configuration = HotkeyConfiguration(
            kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: .function))
        #expect(
            PasteLastValidation.rejection(of: configuration, dictation: .standard, isTakenBySystem: notTaken)
                == .needsKey)
    }

    @Test("the dictation hotkey cannot also paste")
    func sameAsDictation() {
        #expect(
            PasteLastValidation.rejection(of: .standard, dictation: .standard, isTakenBySystem: notTaken)
                == .sameAsDictation)
    }

    @Test("the general hotkey rules apply too")
    func generalRules() {
        let weak = HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: 9, modifiers: [.shift]))
        #expect(
            PasteLastValidation.rejection(of: weak, dictation: .standard, isTakenBySystem: notTaken)
                == .needsStrongerModifiers)
    }
}
