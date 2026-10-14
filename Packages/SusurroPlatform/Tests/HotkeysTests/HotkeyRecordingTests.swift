import AppKit
import Domain
import KeyboardShortcuts
import Testing

@testable import Hotkeys

@MainActor
@Suite("Hotkey recording", .serialized, .timeLimit(.minutes(1)))
struct HotkeyRecordingTests {
    private static let d: UInt16 = 2
    private static let f5: UInt16 = 96
    private static let returnKey: UInt16 = 36
    private static let rightArrow: UInt16 = 124

    private func event(
        _ type: NSEvent.EventType, code: UInt16, flags: NSEvent.ModifierFlags = [], isRepeat: Bool = false
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: isRepeat, keyCode: code))
    }

    // MARK: Events

    @Test("a key that goes down is a key with the modifiers held, and the keyboard's own flags are not modifiers")
    func keyDown() throws {
        let down = try event(.keyDown, code: Self.d, flags: [.control, .option, .capsLock, .numericPad])

        #expect(HotkeyCaptureInput(down) == .key(code: Int(Self.d), modifiers: [.control, .option]))
    }

    @Test("a key that repeats while it is held is heard once")
    func repeatedKey() throws {
        let repeated = try event(.keyDown, code: Self.d, flags: .control, isRepeat: true)

        #expect(HotkeyCaptureInput(repeated) == nil)
    }

    @Test("a key that goes up says nothing")
    func keyUp() throws {
        #expect(HotkeyCaptureInput(try event(.keyUp, code: Self.d, flags: .control)) == nil)
    }

    @Test("a change of the modifier keys carries the modifiers that are down, fn among them")
    func flagsChanged() throws {
        let changed = try event(.flagsChanged, code: 63, flags: [.function, .shift])

        #expect(HotkeyCaptureInput(changed) == .modifiers([.function, .shift]))
    }

    // MARK: The live source

    @Test("the live source hears the keys sent to the app and switches the hotkeys off while it listens")
    func liveSource() async throws {
        let source = NSEventHotkeyCaptureSource()
        let reading = Task { @MainActor in
            var heard: [HotkeyCaptureInput] = []
            for await input in source.inputs() {
                heard.append(input)
                if heard.count == 2 { break }
            }
            return heard
        }
        while KeyboardShortcuts.isEnabled { await Task.yield() }  // it is listening: the hotkeys are off

        NSApplication.shared.sendEvent(try event(.flagsChanged, code: 63, flags: .function))
        NSApplication.shared.sendEvent(try event(.keyDown, code: Self.d, flags: .control))

        #expect(
            await reading.value == [.modifiers(.function), .key(code: Int(Self.d), modifiers: .control)])
        while !KeyboardShortcuts.isEnabled { await Task.yield() }  // it stopped: the hotkeys are back
        #expect(KeyboardShortcuts.isEnabled)
    }

    @Test(
        "the live source ends, and gives the hotkeys back, when the window loses the keys or the app is left",
        arguments: [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification])
    func liveSourceEnds(leaving: Notification.Name) async {
        let source = NSEventHotkeyCaptureSource()
        let reading = Task { @MainActor in
            var heard: [HotkeyCaptureInput] = []
            for await input in source.inputs() { heard.append(input) }
            return heard
        }
        while KeyboardShortcuts.isEnabled { await Task.yield() }

        NotificationCenter.default.post(name: leaving, object: nil)

        #expect(await reading.value.isEmpty)
        while !KeyboardShortcuts.isEnabled { await Task.yield() }
        #expect(KeyboardShortcuts.isEnabled)
    }

    // MARK: Key caps

    @Test("the caps of a hotkey are its modifiers, in the order of the menus, and then its key")
    func caps() {
        let hotkey = HotkeyConfiguration(
            kind: .keyed, combo: HotkeyCombo(keyCode: Int(Self.f5), modifiers: [.command, .control]))

        #expect(HotkeyKeyCaps.caps(for: hotkey) == ["⌃", "⌘", "F5"])
    }

    @Test("a hotkey of modifier keys has no key cap but its modifiers")
    func modifierOnlyCaps() {
        let fn = HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: .function))
        let chord = HotkeyConfiguration(
            kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: [.control, .option]))

        #expect(HotkeyKeyCaps.caps(for: fn) == ["fn"])
        #expect(HotkeyKeyCaps.caps(for: chord) == ["⌃", "⌥"])
    }

    @Test("keys that are not letters are named by their symbol")
    func namedKeys() {
        #expect(HotkeyKeyCaps.keyName(Int(Self.returnKey)) == "↩")
        #expect(HotkeyKeyCaps.keyName(Int(Self.rightArrow)) == "→")
    }

    @Test("a key the system has no name for is named by its code")
    func unnamedKey() {
        #expect(HotkeyKeyCaps.keyName(200) == "Key 200")
    }

    // MARK: System shortcuts

    @Test("a combo with no key is taken by nothing, and neither is one that no shortcut of the system uses")
    func systemShortcuts() {
        let noKey = HotkeyCombo(keyCode: nil, modifiers: [.control, .option])
        let unused = HotkeyCombo(keyCode: 80, modifiers: [.control, .option, .command, .shift])  // F19

        #expect(!SystemShortcuts.isTaken(noKey))
        #expect(!SystemShortcuts.isTaken(unused))
    }
}
