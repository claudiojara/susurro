import Domain
import Observation

/// The state behind the menu bar menu. It re-reads the permission statuses when asked, which the app does when it
/// becomes active and on a slow timer, so a permission granted in System Settings shows without a relaunch. The model
/// line follows the readiness the speech recognizer reports.
@MainActor
@Observable
public final class MenuModel {
    public private(set) var content: MenuContent

    @ObservationIgnored private let permissions: any PermissionsChecker
    @ObservationIgnored private let openSettingsAction: @MainActor (Permission) -> Void
    @ObservationIgnored private let refreshInterval: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    private var microphone = PermissionStatus.notDetermined
    private var accessibility = PermissionStatus.notDetermined
    private var readiness = RecognizerReadiness.loading(progress: 0)

    /// - Parameters:
    ///   - openSettings: Opens the System Settings pane where the user changes a permission.
    ///   - refreshInterval: The pause between reads of the statuses in `keepRefreshing`.
    public init(
        permissions: any PermissionsChecker,
        openSettings: @escaping @MainActor (Permission) -> Void,
        refreshInterval: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.permissions = permissions
        openSettingsAction = openSettings
        self.refreshInterval = refreshInterval
        self.sleep = sleep
        content = MenuContent.make(
            microphone: .notDetermined, accessibility: .notDetermined, readiness: .loading(progress: 0))
    }

    /// Reads both statuses again.
    public func refresh() async {
        microphone = await permissions.status(.microphone)
        accessibility = await permissions.status(.accessibility)
        rebuild()
    }

    /// Reads the statuses now and every `refreshInterval` after, until the task is cancelled.
    public func keepRefreshing() async {
        while !Task.isCancelled {
            await refresh()
            do { try await sleep(refreshInterval) } catch { return }
        }
    }

    /// Follows the readiness of the speech model until the stream ends.
    public func observe(_ changes: AsyncStream<RecognizerReadiness>) async {
        for await value in changes {
            readiness = value
            rebuild()
        }
    }

    public func openSettings(for permission: Permission) {
        openSettingsAction(permission)
    }

    private func rebuild() {
        content = MenuContent.make(microphone: microphone, accessibility: accessibility, readiness: readiness)
    }
}
