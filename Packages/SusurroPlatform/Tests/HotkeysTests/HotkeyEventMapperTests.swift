import Domain
import Testing

@testable import Hotkeys

@Suite("Hotkey event mapper")
struct HotkeyEventMapperTests {
    @Test("a press and its release become down and up events that keep their own timestamps")
    func pressAndRelease() {
        var sut = HotkeyEventMapper()

        #expect(sut.map(.down, at: .milliseconds(1_200)) == .down(at: .milliseconds(1_200)))
        #expect(sut.map(.up, at: .milliseconds(1_850)) == .up(at: .milliseconds(1_850)))
    }

    @Test("a repeated down while the key is held is ignored and does not move the press time")
    func duplicateDownWhileHeld() {
        var sut = HotkeyEventMapper()

        #expect(sut.map(.down, at: .milliseconds(100)) == .down(at: .milliseconds(100)))
        #expect(sut.map(.down, at: .milliseconds(130)) == nil)
        #expect(sut.map(.down, at: .milliseconds(160)) == nil)
        #expect(sut.map(.up, at: .milliseconds(400)) == .up(at: .milliseconds(400)))
    }

    @Test("an up without a down is ignored, and a later press still works")
    func upWithoutDown() {
        var sut = HotkeyEventMapper()

        #expect(sut.map(.up, at: .milliseconds(50)) == nil)
        #expect(sut.map(.down, at: .milliseconds(80)) == .down(at: .milliseconds(80)))
    }

    @Test("a second up after the release is ignored")
    func duplicateUpAfterRelease() {
        var sut = HotkeyEventMapper()
        _ = sut.map(.down, at: .milliseconds(10))

        #expect(sut.map(.up, at: .milliseconds(20)) == .up(at: .milliseconds(20)))
        #expect(sut.map(.up, at: .milliseconds(25)) == nil)
    }

    @Test("a press after a release is a new press")
    func pressAfterRelease() {
        var sut = HotkeyEventMapper()
        _ = sut.map(.down, at: .milliseconds(10))
        _ = sut.map(.up, at: .milliseconds(20))

        #expect(sut.map(.down, at: .milliseconds(500)) == .down(at: .milliseconds(500)))
        #expect(sut.map(.up, at: .milliseconds(900)) == .up(at: .milliseconds(900)))
    }
}

@Suite("Hotkey event mapper for modifier-only hotkeys")
struct ModifierOnlyMapperTests {
    @Test("the flags of the hotkey alone are a press, and no flags are the release")
    func fnPressAndRelease() {
        var sut = HotkeyEventMapper(modifierTarget: .function)

        #expect(sut.map(.flags([]), at: .milliseconds(5)) == nil)  // nothing was held
        #expect(sut.map(.flags(.function), at: .milliseconds(100)) == .down(at: .milliseconds(100)))
        #expect(sut.map(.flags(.function), at: .milliseconds(120)) == nil)  // flags that repeat do not press again
        #expect(sut.map(.flags([]), at: .milliseconds(900)) == .up(at: .milliseconds(900)))
        #expect(sut.map(.flags([]), at: .milliseconds(950)) == nil)
    }

    @Test("a chord of modifiers is down while they are held exactly, and a modifier added or let go ends it")
    func chord() {
        var sut = HotkeyEventMapper(modifierTarget: [.control, .option])

        #expect(sut.map(.flags(.control), at: .milliseconds(10)) == nil)  // not all of them yet
        #expect(sut.map(.flags([.control, .option]), at: .milliseconds(20)) == .down(at: .milliseconds(20)))
        #expect(sut.map(.flags([.control, .option, .shift]), at: .milliseconds(30)) == .up(at: .milliseconds(30)))
        #expect(sut.map(.flags([.control, .option]), at: .milliseconds(40)) == .down(at: .milliseconds(40)))
        #expect(sut.map(.flags(.option), at: .milliseconds(50)) == .up(at: .milliseconds(50)))
    }

    @Test("a keyed hotkey ignores the modifier flags")
    func keyedIgnoresFlags() {
        var sut = HotkeyEventMapper()

        #expect(sut.map(.flags(.function), at: .zero) == nil)
        #expect(sut.map(.down, at: .milliseconds(1)) == .down(at: .milliseconds(1)))
        #expect(sut.map(.flags([]), at: .milliseconds(2)) == nil)  // no flag ends a keyed press
        #expect(sut.map(.up, at: .milliseconds(3)) == .up(at: .milliseconds(3)))
    }
}
