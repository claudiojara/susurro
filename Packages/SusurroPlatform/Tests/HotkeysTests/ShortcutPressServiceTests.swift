import CoreTestSupport
import Domain
import Testing

@testable import Hotkeys

@Suite("Shortcut press service", .timeLimit(.minutes(1)))
struct ShortcutPressServiceTests {
    private let settings = InMemorySettingsStore()
    private let transitions = FakeTransitions()
    private let combo = HotkeyCombo(keyCode: 9, modifiers: [.control, .option])

    private func service() -> ShortcutPressService {
        ShortcutPressService(settings: settings, key: PasteLastSettings.combo, source: transitions)
    }

    @Test("an unassigned shortcut listens to nothing")
    func unassigned() async throws {
        let presses = service().presses()
        settings.set(combo, for: PasteLastSettings.combo)
        await transitions.waitForSubscriptions(1)

        // The only subscription is the one for the combo set after the stream began.
        #expect(transitions.subscriptions == [HotkeyConfiguration(kind: .keyed, combo: combo)])
        _ = presses
    }

    @Test("a press is the key going down; the release and a repeated down without a release are not presses")
    func presses() async throws {
        settings.set(combo, for: PasteLastSettings.combo)
        var presses = service().presses().makeAsyncIterator()
        await transitions.waitForSubscriptions(1)

        transitions.send(.down)
        transitions.send(.down)
        transitions.send(.up)
        transitions.send(.down)
        transitions.finish()

        var count = 0
        while await presses.next() != nil { count += 1 }
        #expect(count == 2)
    }

    @Test("a changed shortcut is listened to at once, and a removed one is no longer listened to")
    func followsTheSetting() async throws {
        settings.set(combo, for: PasteLastSettings.combo)
        let presses = service().presses()
        await transitions.waitForSubscriptions(1)

        let other = HotkeyCombo(keyCode: 35, modifiers: [.control, .option])
        settings.set(other, for: PasteLastSettings.combo)
        await transitions.waitForSubscriptions(2)
        #expect(transitions.subscriptions.last == HotkeyConfiguration(kind: .keyed, combo: other))

        settings.remove(PasteLastSettings.combo)
        await transitions.stoppedListening.wait()
        _ = presses
    }
}
