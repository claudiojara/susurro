import Carbon.HIToolbox
import CoreGraphics
import Testing

@testable import TextInsertion

@MainActor
@Suite("Key layout", .timeLimit(.minutes(1)))
struct KeyLayoutTests {
    /// Where the keys of a layout are, as the characters they type. A key that is not listed types nothing.
    private static func layout(_ keys: [CGKeyCode: String]) -> KeyLayout.Translate {
        { keyCode, _ in keys[keyCode] }
    }

    private static let qwerty = layout([0: "a", 9: "v", 11: "b"])
    private static let dvorak = layout([0: "a", 9: ";", 47: "v"])
    /// A layout that is Dvorak until Command goes down, then QWERTY, as "Dvorak - QWERTY Command" does.
    private static let dvorakQwertyCommand: KeyLayout.Translate = { keyCode, commandHeld in
        commandHeld ? qwerty(keyCode, true) : dvorak(keyCode, false)
    }
    private static let cyrillic = layout([0: "ф", 9: "м"])

    @Test("on QWERTY the V key is where the US layout has it")
    func qwertyLayout() {
        #expect(KeyLayout.keyCode(typing: "v", using: Self.qwerty) == 9)
    }

    @Test("on Dvorak the key that types V is another one")
    func dvorakLayout() {
        #expect(KeyLayout.keyCode(typing: "v", using: Self.dvorak) == 47)
    }

    @Test("a layout that types QWERTY with Command down is asked what Command types")
    func commandLayout() {
        #expect(KeyLayout.keyCode(typing: "v", using: Self.dvorakQwertyCommand) == 9)
    }

    @Test("a layout with no V has no key for it")
    func noV() {
        #expect(KeyLayout.keyCode(typing: "v", using: Self.cyrillic) == nil)
    }

    // The system's own layouts, which ship with macOS. The layout data decides the key, so these pin the translation
    // against the real thing.

    private func systemLayout(_ id: String) -> KeyLayout.Translate? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard
            let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
            let source = list.first
        else { return nil }
        return KeyLayout.translator(for: source)
    }

    @Test(
        "the system's own layouts put V where the layout data says",
        arguments: [("com.apple.keylayout.US", CGKeyCode(9)), ("com.apple.keylayout.Dvorak", CGKeyCode(47))]
    )
    func systemLayouts(id: String, expected: CGKeyCode) {
        guard let translate = systemLayout(id) else { return }  // the layout is not installed on this machine
        #expect(KeyLayout.keyCode(typing: "v", using: translate) == expected)
    }

    @Test("the layout in use always gives a key code")
    func currentLayout() {
        #expect(KeyLayout.pasteKeyCode() < 128)
    }
}
