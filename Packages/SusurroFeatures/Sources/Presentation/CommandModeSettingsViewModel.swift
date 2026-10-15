import Domain
import Observation
import SusurroUI

/// The command mode card of the settings: the switch (`command.enabled`), the command hotkey as key caps, a warning
/// when Apple Intelligence cannot rewrite on this Mac, and one when the command hotkey is made only of modifier keys and
/// Input Monitoring is not allowed, so it is not listened to, or when it clashes with another shortcut of the app. The
/// recorder of the command hotkey is a `HotkeyRecorderViewModel` for the command role, in the card's slot.
@MainActor
@Observable
public final class CommandModeSettingsViewModel: CommandModeSettingsModeling {
    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let shortcut: @MainActor (HotkeyConfiguration) -> [String]
    @ObservationIgnored private let modelAvailable: @Sendable () async -> Bool
    @ObservationIgnored private let permissions: (any PermissionsChecker)?

    private var isModelAvailable = true
    /// Granted until it has been read, so the card does not flash a warning.
    private var inputMonitoring: PermissionStatus = .granted
    /// The Input Monitoring status has been read at least once.
    private(set) var hasReadPermissions = false
    /// Counts the changes of the settings the card shows. `state` reads it, so the card is drawn again after each of
    /// them, though the settings store is not observable.
    private var revision = 0

    /// - Parameters:
    ///   - shortcut: The key caps of a hotkey, which the platform knows.
    ///   - modelAvailable: Whether Apple's on-device model can take a request on this Mac.
    ///   - permissions: Where the Input Monitoring status is read and asked for. Without it no warning is shown.
    public init(
        settings: any SettingsStore, shortcut: @escaping @MainActor (HotkeyConfiguration) -> [String],
        modelAvailable: @escaping @Sendable () async -> Bool, permissions: (any PermissionsChecker)? = nil
    ) {
        self.settings = settings
        self.shortcut = shortcut
        self.modelAvailable = modelAvailable
        self.permissions = permissions
    }

    public var state: CommandModeSettingsState {
        _ = revision
        let isEnabled = settings.value(for: CommandSettings.enabled)
        let configuration = settings.hotkeyConfiguration(for: .command)
        // The same rule as the hotkey service: a modifier-only hotkey is not armed until Input Monitoring is granted.
        let status = HotkeyStatus.evaluate(configuration, inputMonitoring: inputMonitoring, secureInputActive: false)
        let permissionWarning: HotkeyWarning? =
            isEnabled && status.arming == .needsInputMonitoring
            ? HotkeyWarning(
                message: SettingsCopy.inputMonitoringWarning, actionTitle: SettingsCopy.allowInputMonitoring)
            : nil
        return CommandModeSettingsState(
            isEnabled: isEnabled, shortcut: shortcut(configuration),
            warning: isModelAvailable ? nil : CommandModeCopy.modelUnavailable, permissionWarning: permissionWarning,
            hotkeyWarning: settings.commandHotkeyClashes ? CommandModeCopy.hotkeyOverlap : nil)
    }

    public func setEnabled(_ enabled: Bool) {
        settings.set(enabled, for: CommandSettings.enabled)
        revision &+= 1
    }

    public func requestInputMonitoring() async {
        guard let permissions else { return }
        await permissions.request(.inputMonitoring)
        await readInputMonitoring()
    }

    public func follow() async {
        let changes = settings.changes()
        isModelAvailable = await modelAvailable()
        await readInputMonitoring()
        for await change in changes
        where ["command.", "hotkey.", "pasteLast."].contains(where: change.name.hasPrefix) {
            // The permission may have been granted in System Settings since it was read.
            await readInputMonitoring()
        }
    }

    private func readInputMonitoring() async {
        if let permissions { inputMonitoring = await permissions.status(.inputMonitoring) }
        hasReadPermissions = true
        revision &+= 1
    }
}

enum CommandModeCopy {
    static var modelUnavailable: String {
        L10n.string(
            "settings.command.modelUnavailable",
            "Apple Intelligence is not available on this Mac now, so command mode cannot rewrite text.")
    }

    static var hotkeyOverlap: String {
        L10n.string(
            "settings.command.hotkeyOverlap", "This shortcut overlaps another Susurro shortcut; choose a different one."
        )
    }
}
