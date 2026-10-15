import CoreTestSupport
import Domain
import Testing

@testable import Hotkeys

@Suite("Hotkey service with command mode", .timeLimit(.minutes(1)))
struct CommandHotkeyServiceTests {
    @Test("with command mode off only the dictation hotkey is listened to")
    func offListensToDictationOnly() async {
        let rig = HotkeyRig()

        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)
        await Task.yield()

        #expect(rig.source.subscriptions == [.standard])
        withExtendedLifetime(events) {}
    }

    @Test("with command mode on both hotkeys are listened to, and each event says which one it was")
    func bothHotkeysAreTagged() async {
        let rig = HotkeyRig()
        rig.settings.set(true, for: CommandSettings.enabled)
        var events = rig.service.events().makeAsyncIterator()
        await rig.source.waitForSubscriptions(2)
        #expect(
            Set(rig.source.subscriptions.map(\.combo.modifiers)) == [
                [.control, .option], [.control, .option, .shift],
            ])

        rig.clock.set(.milliseconds(10))
        rig.source.send(.down, to: .command)
        #expect(await events.next() == .down(at: .milliseconds(10), role: .command))
        rig.source.send(.down, to: .standard)
        #expect(await events.next() == .down(at: .milliseconds(10), role: .dictate))
        rig.source.send(.up, to: .command)
        #expect(await events.next() == .up(at: .milliseconds(10), role: .command))
    }

    @Test("turning command mode on listens to its hotkey without a relaunch, and turning it off lets it go")
    func followsTheSwitch() async {
        let rig = HotkeyRig()
        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)

        rig.settings.set(true, for: CommandSettings.enabled)
        await rig.waitForSubscription(to: .command)
        rig.settings.set(false, for: CommandSettings.enabled)
        await rig.source.stoppedListening.wait()

        #expect(rig.source.subscriptions == [.standard, .command])
        withExtendedLifetime(events) {}
    }

    @Test("a command hotkey equal to the dictation one is not listened to")
    func equalCombosAreRefused() async {
        let rig = HotkeyRig()
        rig.settings.set(true, for: CommandSettings.enabled)
        rig.settings.setHotkey(.standard, for: .command)

        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)
        await Task.yield()

        #expect(rig.source.subscriptions == [.standard])
        withExtendedLifetime(events) {}
    }

    @Test("a command hotkey whose modifiers nest with the dictation one is not listened to; dictation wins")
    func overlappingCombosAreRefused() async {
        let rig = HotkeyRig(permissions: [.inputMonitoring: .granted])
        let dictation = HotkeyConfiguration(
            kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: [.control, .option]))
        rig.settings.set(true, for: CommandSettings.enabled)
        rig.settings.setHotkey(dictation, for: .dictate)

        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)
        await Task.yield()

        #expect(rig.source.subscriptions == [dictation])
        withExtendedLifetime(events) {}
    }
}
