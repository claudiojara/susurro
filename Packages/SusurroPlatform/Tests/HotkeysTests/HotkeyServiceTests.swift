import CoreTestSupport
import Domain
import Testing

@testable import Hotkeys

@Suite("Hotkey service", .timeLimit(.minutes(1)))
struct HotkeyServiceTests {
    @Test("each transition is stamped with the time it is read")
    func stampsTransitions() async {
        let rig = HotkeyRig()
        var events = rig.service.events().makeAsyncIterator()
        await rig.source.waitForSubscriptions(1)

        rig.clock.set(.milliseconds(1_000))
        rig.source.send(.down)
        #expect(await events.next() == .down(at: .milliseconds(1_000)))

        rig.clock.set(.milliseconds(1_350))
        rig.source.send(.up)
        #expect(await events.next() == .up(at: .milliseconds(1_350)))
    }

    @Test("repeated downs and a stray up are dropped, and the stream ends when the source does")
    func filtersRepeatsAndEnds() async {
        let rig = HotkeyRig()
        rig.clock.set(.milliseconds(5))
        let stream = rig.service.events()
        await rig.source.waitForSubscriptions(1)

        for transition in [KeyTransition.up, .down, .down, .up, .up] { rig.source.send(transition) }
        rig.source.finish()

        var seen: [HotkeyEvent] = []
        for await event in stream { seen.append(event) }

        #expect(seen == [.down(at: .milliseconds(5)), .up(at: .milliseconds(5))])
    }

    @Test("the source is released when the consumer stops listening")
    func releasesSourceWhenConsumerStops() async {
        let rig = HotkeyRig()

        let reader = Task {
            var events = rig.service.events().makeAsyncIterator()
            return await events.next()
        }
        await rig.source.waitForSubscriptions(1)
        rig.source.send(.down)

        #expect(await reader.value == .down(at: .zero))
        await rig.source.stoppedListening.wait()
    }

    @Test("nothing is listened to before events() is called, and the default hotkey is listened to after")
    func subscribesWhenEventsIsCalled() async {
        let rig = HotkeyRig()
        #expect(rig.source.subscriptions.isEmpty)

        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)

        #expect(rig.source.subscriptions == [.standard])
        withExtendedLifetime(events) {}
    }

    @Test("a hotkey the user changes is listened to without a relaunch")
    func followsTheSettings() async {
        let rig = HotkeyRig(permissions: [.inputMonitoring: .granted])
        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)

        rig.chooseModifierOnly(.function)
        let fn = HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: .function))
        await rig.waitForSubscription(to: fn)

        #expect(rig.source.subscriptions.first == .standard)
        #expect(rig.source.subscriptions.last == fn)
        withExtendedLifetime(events) {}
    }
}
