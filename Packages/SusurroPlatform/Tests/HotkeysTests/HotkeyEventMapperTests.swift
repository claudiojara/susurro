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
