import Domain
import Observation

/// The state behind the menu bar menu. The permissions come from the monitor, which reads them every second and when the
/// app becomes active, so a permission granted or revoked in System Settings shows without the menu reading anything.
/// The model line follows the readiness the speech recognizer reports.
@MainActor
@Observable
public final class MenuModel {
    @ObservationIgnored private let monitor: PermissionsMonitor
    private var readiness = RecognizerReadiness.loading(progress: 0)

    public init(monitor: PermissionsMonitor) {
        self.monitor = monitor
    }

    /// What the menu shows now. It reads the monitor's statuses, which are observable, so a view that reads it is drawn
    /// again when a permission changes.
    public var content: MenuContent {
        MenuContent.make(
            microphone: monitor.statuses[.microphone] ?? .notDetermined,
            accessibility: monitor.statuses[.accessibility] ?? .notDetermined,
            disabledReason: monitor.disabledReason,
            readiness: readiness)
    }

    /// Follows the readiness of the speech model until the stream ends.
    public func observe(_ changes: AsyncStream<RecognizerReadiness>) async {
        for await value in changes { readiness = value }
    }

    /// Opens the System Settings pane of the permission, through the monitor, which then follows the permission until
    /// its status changes.
    public func openSettings(for permission: Permission) {
        monitor.openSettings(for: permission)
    }
}
