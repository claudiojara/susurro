import Carbon.HIToolbox
import CoreTestSupport
import Domain
import KeyboardShortcuts
import Testing

@testable import Hotkeys

@Suite("Hotkey configuration", .timeLimit(.minutes(1)))
struct HotkeyConfigurationTests {
    private static let fn = HotkeyConfiguration(
        kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: .function))

    @Test("the default is a keyed combination that is armed without Input Monitoring")
    func defaultNeedsNoPermission() async {
        let rig = HotkeyRig(permissions: [.inputMonitoring: .denied])
        let events = rig.service.events()
        await rig.source.waitForSubscriptions(1)

        #expect(await rig.service.status() == HotkeyStatus(arming: .armed, secureInputWarning: false))
        #expect(rig.permissions.statusReads == 0)  // a keyed hotkey never asks
        withExtendedLifetime(events) {}
    }

    @Test("a modifier-only hotkey without Input Monitoring is not armed, and the status says what is missing")
    func modifierOnlyWithoutPermission() async {
        let rig = HotkeyRig(permissions: [.inputMonitoring: .denied])
        rig.chooseModifierOnly(.function)

        let events = rig.service.events()
        await rig.sleeper.entered(rig.recheckInterval).wait()  // it is waiting to look again

        #expect(await rig.service.status() == HotkeyStatus(arming: .needsInputMonitoring, secureInputWarning: false))
        #expect(rig.source.subscriptions.isEmpty)
        withExtendedLifetime(events) {}
    }

    @Test("once Input Monitoring is granted the modifier-only hotkey arms")
    func armsOnceGranted() async {
        let rig = HotkeyRig(permissions: [.inputMonitoring: .denied])
        rig.chooseModifierOnly(.function)
        var events = rig.service.events().makeAsyncIterator()
        await rig.sleeper.entered(rig.recheckInterval).wait()
        #expect(rig.source.subscriptions.isEmpty)

        rig.permissions.set(.inputMonitoring, to: .granted)
        rig.sleeper.fire(rig.recheckInterval)
        await rig.source.waitForSubscriptions(1)

        #expect(rig.source.subscriptions == [Self.fn])
        #expect(await rig.service.status().arming == .armed)
        // The flags of fn alone are a press, and anything else ends it.
        rig.clock.set(.milliseconds(40))
        rig.source.send(.flags(.function))
        #expect(await events.next() == .down(at: .milliseconds(40)))
        rig.clock.set(.milliseconds(900))
        rig.source.send(.flags([]))
        #expect(await events.next() == .up(at: .milliseconds(900)))
    }

    @Test("a hotkey that is switched back to a keyed combination arms at once, and stops waiting")
    func switchingBackToKeyed() async {
        let rig = HotkeyRig(permissions: [.inputMonitoring: .denied])
        rig.chooseModifierOnly(.function)
        let events = rig.service.events()
        await rig.sleeper.entered(rig.recheckInterval).wait()

        rig.settings.remove(HotkeySettings.kind)
        rig.settings.remove(HotkeySettings.combo)
        await rig.waitForSubscription(to: .standard)

        #expect(await rig.service.status().arming == .armed)
        withExtendedLifetime(events) {}
    }

    @Test("an active Secure Event Input exposes the warning")
    func secureInputWarning() async {
        let rig = HotkeyRig(secureInput: true)

        #expect(await rig.service.status() == HotkeyStatus(arming: .armed, secureInputWarning: true))
    }

    /// Changing the default is deliberate: re-run the macOS shortcut collision check in ADR 0005 first.
    @Test("the default hotkey is Control+Option+D")
    func defaultIsControlOptionD() {
        let expected = KeyboardShortcuts.Shortcut(carbonKeyCode: kVK_ANSI_D, carbonModifiers: controlKey | optionKey)

        #expect(KeyboardShortcuts.Shortcut(HotkeyConfiguration.standard.combo) == expected)
    }

    @Test("a combo becomes a shortcut with its modifiers, and a combo without a key becomes none")
    func comboBecomesAShortcut() {
        let combo = HotkeyCombo(keyCode: kVK_ANSI_K, modifiers: [.command, .shift, .control, .option])

        #expect(
            KeyboardShortcuts.Shortcut(combo)
                == KeyboardShortcuts.Shortcut(
                    carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey | shiftKey | controlKey | optionKey))
        #expect(KeyboardShortcuts.Shortcut(HotkeyCombo(keyCode: nil, modifiers: .function)) == nil)
    }
}
