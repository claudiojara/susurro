import Activation
import Domain
import Testing

@Suite("Role gate")
struct RoleGateTests {
    private typealias Phase = ActivationMachine.State.Phase

    @Test("a press of either hotkey is let through while nothing is under way")
    func idlePress() {
        var dictate = RoleGate()
        var command = RoleGate()

        #expect(dictate.decide(.down(at: .zero, role: .dictate), phase: .idle) == .admit)
        #expect(command.decide(.down(at: .zero, role: .command), phase: .idle) == .admit)
        #expect(command.held == .command)
    }

    @Test("while the dictation key is held, the command key goes nowhere, and its release cannot finish the hold")
    func otherRoleIsDroppedWhileHeld() {
        var sut = RoleGate()
        _ = sut.decide(.down(at: .zero, role: .dictate), phase: .idle)
        let recording = Phase.pressed(at: .zero)

        #expect(sut.decide(.down(at: .milliseconds(100), role: .command), phase: recording) == .drop)
        #expect(sut.decide(.up(at: .milliseconds(200), role: .command), phase: recording) == .drop)
        #expect(sut.decide(.up(at: .milliseconds(900), role: .dictate), phase: recording) == .admit)
        #expect(sut.held == nil)
    }

    @Test("the dictation key goes nowhere while a command is held")
    func dictationIsDroppedDuringACommand() {
        var sut = RoleGate()
        _ = sut.decide(.down(at: .zero, role: .command), phase: .idle)

        #expect(sut.decide(.down(at: .milliseconds(50), role: .dictate), phase: .pressed(at: .zero)) == .drop)
        #expect(sut.decide(.up(at: .milliseconds(60), role: .dictate), phase: .pressed(at: .zero)) == .drop)
    }

    @Test("a hands-free dictation is stopped only by its own key: the command key cannot stop it")
    func handsFreeBelongsToItsRole() {
        var sut = RoleGate()
        _ = sut.decide(.down(at: .zero, role: .dictate), phase: .idle)
        _ = sut.decide(.up(at: .milliseconds(100), role: .dictate), phase: .pressed(at: .zero))
        let handsFree = Phase.handsFree(ignoreNextUp: false)

        #expect(sut.decide(.down(at: .seconds(2), role: .command), phase: handsFree) == .drop)
        #expect(sut.decide(.down(at: .seconds(3), role: .dictate), phase: handsFree) == .admit)
    }

    @Test("a press of the other key in the double-tap window closes the window first, then starts its own press")
    func otherRoleClosesTheWindow() {
        var sut = RoleGate()
        _ = sut.decide(.down(at: .zero, role: .dictate), phase: .idle)
        _ = sut.decide(.up(at: .milliseconds(100), role: .dictate), phase: .pressed(at: .zero))
        let window = Phase.awaitingSecondTap(releasedAt: .milliseconds(100))

        #expect(sut.decide(.down(at: .milliseconds(200), role: .command), phase: window) == .closeWindowThenAdmit)
        #expect(sut.held == .command)
    }

    @Test("Esc always goes through: it cancels whatever is under way")
    func escapePasses() {
        var sut = RoleGate()
        _ = sut.decide(.down(at: .zero, role: .command), phase: .idle)

        #expect(sut.decide(.escape, phase: .pressed(at: .zero)) == .admit)
    }

    @Test("a release with no press of its own is dropped")
    func strayRelease() {
        var sut = RoleGate()

        #expect(sut.decide(.up(at: .zero, role: .command), phase: .idle) == .drop)
    }
}
