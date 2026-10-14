import CoreTestSupport
import Domain
import Testing

@testable import Hotkeys

@Suite("Esc registration", .timeLimit(.minutes(1)))
struct EscapeRegistrationTests {
    @Test("Esc is not registered at launch, nor once the hotkey is being listened to")
    func notRegisteredAtLaunch() async {
        let rig = HotkeyRig()
        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)

        #expect(rig.escape.registrations == 0)
        #expect(!rig.escape.isRegistered)
        withExtendedLifetime(events) {}
    }

    @Test("arming registers the handler and disarming unregisters it")
    func armAndDisarm() {
        let rig = HotkeyRig()

        rig.service.setEscapeArmed(true)
        #expect(rig.escape.isRegistered)

        rig.service.setEscapeArmed(false)
        #expect(!rig.escape.isRegistered)
    }

    @Test("arming twice, and disarming twice, change nothing the second time")
    func idempotent() {
        let rig = HotkeyRig()

        rig.service.setEscapeArmed(true)
        rig.service.setEscapeArmed(true)
        #expect(rig.escape.registrations == 1)

        rig.service.setEscapeArmed(false)
        rig.service.setEscapeArmed(false)
        #expect(rig.escape.unregistrations == 1)
    }

    @Test("disarming what was never armed registers and unregisters nothing")
    func disarmWithoutArming() {
        let rig = HotkeyRig()

        rig.service.setEscapeArmed(false)

        #expect(rig.escape.registrations == 0)
        #expect(rig.escape.unregistrations == 0)
    }

    @Test("an Esc press while armed arrives on the events stream, and one after disarming does not")
    func pressArrivesAsAnEvent() async {
        let rig = HotkeyRig()
        var events = rig.service.events().makeAsyncIterator()
        await rig.source.waitForSubscriptions(1)

        rig.service.setEscapeArmed(true)
        rig.escape.press()
        #expect(await events.next() == .escape)

        rig.service.setEscapeArmed(false)
        rig.escape.press()  // the system gives Esc to the app in front: nothing is delivered
        rig.clock.set(.milliseconds(30))
        rig.source.send(.down)
        #expect(await events.next() == .down(at: .milliseconds(30)))
    }
}
