import Domain
import Observation

/// The state behind the menu bar menu. The permissions come from the monitor, which reads them every second and when the
/// app becomes active, so a permission granted or revoked in System Settings shows without the menu reading anything.
/// The model line follows the readiness the speech recognizer reports.
@MainActor
@Observable
public final class MenuModel {
    @ObservationIgnored private let monitor: PermissionsMonitor
    @ObservationIgnored private let showOnboarding: @MainActor () -> Void
    @ObservationIgnored private let showSettings: (@MainActor () -> Void)?
    private var readiness = RecognizerReadiness.loading(progress: 0)

    /// - Parameters:
    ///   - showOnboarding: Opens the onboarding window, for the item that sets Susurro up.
    ///   - showSettings: Opens the settings window, for the Settings item. With none, the menu has no such item.
    public init(
        monitor: PermissionsMonitor, showOnboarding: @escaping @MainActor () -> Void = {},
        showSettings: (@MainActor () -> Void)? = nil
    ) {
        self.monitor = monitor
        self.showOnboarding = showOnboarding
        self.showSettings = showSettings
    }

    /// What the menu shows now. It reads the monitor's statuses, which are observable, so a view that reads it is drawn
    /// again when a permission changes.
    public var content: MenuContent {
        MenuContent.make(
            microphone: monitor.statuses[.microphone] ?? .notDetermined,
            accessibility: monitor.statuses[.accessibility] ?? .notDetermined,
            followUps: monitor.followUps,
            restriction: monitor.restriction,
            readiness: readiness)
    }

    /// Follows the readiness of the speech model until the stream ends.
    public func observe(_ changes: AsyncStream<RecognizerReadiness>) async {
        for await value in changes { readiness = value }
    }

    /// Asks the system for the permission, through the monitor, which then follows it until its status changes. The
    /// system prompt may be up until the user answers.
    public func request(_ permission: Permission) async {
        await monitor.request(permission)
    }

    /// Opens the System Settings pane of the permission, through the monitor, which then follows the permission until
    /// its status changes.
    public func openSettings(for permission: Permission) {
        monitor.openSettings(for: permission)
    }

    /// Opens the onboarding, where the missing permissions are asked for.
    public func setUp() {
        showOnboarding()
    }

    /// Whether the menu has a Settings item.
    public var hasSettings: Bool { showSettings != nil }

    /// Opens the settings window.
    public func openSettingsWindow() {
        showSettings?()
    }
}
