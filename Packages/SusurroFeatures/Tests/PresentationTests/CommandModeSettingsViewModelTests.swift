import CoreTestSupport
import Domain
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Command mode settings view model", .timeLimit(.minutes(1)))
struct CommandModeSettingsViewModelTests {
    private let settings = InMemorySettingsStore()

    private let permissions = MutablePermissionsChecker([.inputMonitoring: .denied])

    private func model(available: Bool = true) -> CommandModeSettingsViewModel {
        CommandModeSettingsViewModel(
            settings: settings, shortcut: { $0.combo.modifiers.caps + ($0.combo.keyCode.map { ["#\($0)"] } ?? []) },
            modelAvailable: { available }, permissions: permissions)
    }

    private func useModifierOnlyCommandHotkey() {
        settings.setHotkey(
            HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: [.command, .option])),
            for: .command)
    }

    private static let inputMonitoringWarning = HotkeyWarning(
        message: SettingsCopy.inputMonitoringWarning, actionTitle: SettingsCopy.allowInputMonitoring)

    private func until(_ condition: @MainActor () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    @Test("a fresh install shows command mode off, with the default command hotkey")
    func defaults() {
        #expect(
            model().state == CommandModeSettingsState(isEnabled: false, shortcut: ["⌃", "⌥", "⇧", "#2"], warning: nil))
    }

    @Test("the switch writes command.enabled and shows at once")
    func setEnabled() {
        let sut = model()

        sut.setEnabled(true)

        #expect(settings.value(for: CommandSettings.enabled))
        #expect(sut.state.isEnabled)
    }

    @Test("a Mac without Apple Intelligence gets a warning once the card is on screen")
    func warning() async {
        let sut = model(available: false)
        let following = Task { await sut.follow() }

        await until { sut.state.warning != nil }

        #expect(sut.state.warning == CommandModeCopy.modelUnavailable)
        following.cancel()
    }

    @Test("a change made in the menu, or a new command hotkey, shows while the card is on screen")
    func followsTheSettings() async {
        let sut = model()
        let following = Task { await sut.follow() }
        await Task.yield()

        settings.set(true, for: CommandSettings.enabled)
        await until { sut.state.isEnabled }
        settings.setHotkey(
            HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: 96, modifiers: [])), for: .command)
        await until { sut.state.shortcut == ["#96"] }

        following.cancel()
    }

    @Test("a modifier-only command hotkey without Input Monitoring says it is off, with the button that asks for it")
    func inputMonitoringWarning() async {
        settings.set(true, for: CommandSettings.enabled)
        useModifierOnlyCommandHotkey()
        let sut = model()
        let following = Task { await sut.follow() }

        await until { sut.state.permissionWarning != nil }
        #expect(sut.state.permissionWarning == Self.inputMonitoringWarning)

        permissions.set(.inputMonitoring, to: .granted)
        await sut.requestInputMonitoring()
        #expect(permissions.requested == [.inputMonitoring])
        #expect(sut.state.permissionWarning == nil)
        following.cancel()
    }

    @Test("no Input Monitoring warning for a keyed command hotkey, or while command mode is off")
    func noInputMonitoringWarning() async {
        let sut = model()
        let following = Task { await sut.follow() }
        await until { sut.hasReadPermissions }
        #expect(sut.state.permissionWarning == nil)

        useModifierOnlyCommandHotkey()
        await Task.yield()
        #expect(sut.state.permissionWarning == nil)

        settings.set(true, for: CommandSettings.enabled)
        await until { sut.state.permissionWarning != nil }
        following.cancel()
    }

    @Test("turning command mode on with a stored command hotkey that clashes with another shortcut warns on the card")
    func overlapWarning() async {
        settings.setHotkey(.command, for: .dictate)
        let sut = model()
        let following = Task { await sut.follow() }
        await until { sut.hasReadPermissions }
        #expect(sut.state.hotkeyWarning == nil, "off: the command hotkey is not listened to")

        settings.set(true, for: CommandSettings.enabled)
        await until { sut.state.hotkeyWarning != nil }
        #expect(sut.state.hotkeyWarning == CommandModeCopy.hotkeyOverlap)

        settings.resetHotkey(for: .dictate)
        await until { sut.state.hotkeyWarning == nil }
        following.cancel()
    }
}
