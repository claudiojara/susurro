// The contract between the command mode card of the settings and the code that drives it. The card draws this value and
// calls the intents; the view model in `SusurroFeatures` reads and writes the settings.

/// What the command mode card shows.
public nonisolated struct CommandModeSettingsState: Equatable, Sendable {
    /// Whether command mode is on, so that its hotkey is listened to.
    public let isEnabled: Bool
    /// The keys of the command hotkey, one cap each, such as `⌃`, `⌥`, `⇧`, `D`.
    public let shortcut: [String]
    /// Why command mode cannot work on this Mac, such as Apple Intelligence being off, or nil.
    public let warning: String?
    /// The command hotkey is made only of modifier keys and Input Monitoring is not allowed, so it is not listened to.
    public let permissionWarning: HotkeyWarning?
    /// Command mode is on but its hotkey repeats or nests with another shortcut of the app, so it is not listened to.
    public let hotkeyWarning: String?

    public init(
        isEnabled: Bool, shortcut: [String], warning: String?, permissionWarning: HotkeyWarning? = nil,
        hotkeyWarning: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.shortcut = shortcut
        self.warning = warning
        self.permissionWarning = permissionWarning
        self.hotkeyWarning = hotkeyWarning
    }
}

/// What the command mode card needs from the code behind it. A change is applied at once and shows in `state`.
@MainActor
public protocol CommandModeSettingsModeling: AnyObject {
    var state: CommandModeSettingsState { get }
    func setEnabled(_ enabled: Bool)
    /// Asks the system for Input Monitoring, which a modifier-only command hotkey needs.
    func requestInputMonitoring() async
    /// Follows the settings while the card is on screen, so a change made elsewhere (the menu) shows.
    func follow() async
}

/// What the card can ask for, as closures, so that the view is a pure function of its state and its actions.
public struct CommandModeActions {
    public var setEnabled: (Bool) -> Void
    public var requestInputMonitoring: () -> Void

    public static let none = CommandModeActions(setEnabled: { _ in })

    public init(setEnabled: @escaping (Bool) -> Void, requestInputMonitoring: @escaping () -> Void = {}) {
        self.setEnabled = setEnabled
        self.requestInputMonitoring = requestInputMonitoring
    }

    @MainActor
    public init(model: any CommandModeSettingsModeling) {
        self.init(
            setEnabled: { model.setEnabled($0) },
            requestInputMonitoring: { Task { await model.requestInputMonitoring() } })
    }
}
