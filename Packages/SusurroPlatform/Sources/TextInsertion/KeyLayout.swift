import Carbon.HIToolbox
import CoreGraphics

/// Finds the key that types "v" on the keyboard layout in use. The paste shortcut is matched by the character a key
/// types, not by where the key is, so Command+V needs the key code of "v" on this layout: 9 on a US layout and another
/// one on Dvorak.
enum KeyLayout {
    /// The character that a key types, or nil when it types none. `commandHeld` asks for what the key types with Command
    /// down, because some layouts, such as Dvorak - QWERTY Command, type something else then.
    typealias Translate = (_ keyCode: CGKeyCode, _ commandHeld: Bool) -> String?

    /// The first key code, looking at Command-down characters before plain ones, that types `character`. Nil when the
    /// layout has no such key, as with a layout for another script.
    static func keyCode(typing character: String, using translate: Translate) -> CGKeyCode? {
        for commandHeld in [true, false] {
            if let found = (0..<128).first(where: { translate(CGKeyCode($0), commandHeld) == character }) {
                return CGKeyCode(found)
            }
        }
        return nil
    }

    /// The key code of "v" on the layout in use. A layout without a "v", such as one for another script, falls back to
    /// the ASCII-capable layout that the system keeps for shortcuts, and then to the key code of the US layout.
    @MainActor
    static func pasteKeyCode() -> CGKeyCode {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        ]
        for source in sources.compactMap({ $0 }) {
            if let translate = translator(for: source), let code = keyCode(typing: "v", using: translate) {
                return code
            }
        }
        return PasteChord.ansiVKeyCode
    }

    /// A translator over the layout data of an input source, or nil for a source with no layout data.
    @MainActor
    static func translator(for source: TISInputSource) -> Translate? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let keyboardType = UInt32(LMGetKbdType())
        return { keyCode, commandHeld in
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let modifiers = commandHeld ? UInt32(cmdKey >> 8) & 0xFF : 0
            let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
                UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDown), modifiers, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
            }
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
