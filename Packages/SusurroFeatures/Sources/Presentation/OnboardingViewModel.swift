import Domain
import SusurroUI

/// Adapts the permissions monitor to the onboarding screen's contract. It holds no state of its own: the rows, the
/// waiting state and the stale guidance are the monitor's, so what the screen shows cannot drift from what the menu and
/// the overlay say.
@MainActor
public final class OnboardingViewModel: OnboardingViewModeling {
    private let monitor: PermissionsMonitor

    public init(monitor: PermissionsMonitor) {
        self.monitor = monitor
    }

    public var state: OnboardingViewState {
        OnboardingViewState(
            rows: monitor.requested.map(row(for:)),
            isDoneEnabled: monitor.isOnboardingComplete,
            restrictionMessage: monitor.restriction?.message
        )
    }

    public func request(_ permission: OnboardingPermission) async {
        await monitor.request(permission.permission)
    }

    public func openSettings(_ permission: OnboardingPermission) {
        monitor.openSettings(for: permission.permission)
    }

    public func recheck() async {
        await monitor.refresh()
    }

    // MARK: Rows

    private func row(for permission: Permission) -> OnboardingRowState {
        Self.row(
            for: permission, status: monitor.statuses[permission] ?? .notDetermined,
            followUp: monitor.followUps[permission])
    }

    /// The row of a permission with the given status and follow-up. The step is `PermissionStep`'s, the rule the menu
    /// follows too.
    static func row(
        for permission: Permission, status: PermissionStatus, followUp: PermissionsMonitor.FollowUp?
    ) -> OnboardingRowState {
        let step = PermissionStep.make(permission: permission, status: status, followUp: followUp)
        return OnboardingRowState(
            id: OnboardingPermission(permission),
            title: permission.displayName,
            why: OnboardingCopy.why(permission),
            requirement: OnboardingCopy.requirement(permission),
            status: OnboardingCopy.status(step.standing, for: permission),
            action: step.action.map { OnboardingCopy.action($0, for: permission) }
        )
    }
}

extension OnboardingPermission {
    init(_ permission: Permission) {
        switch permission {
        case .microphone: self = .microphone
        case .accessibility: self = .accessibility
        case .inputMonitoring: self = .inputMonitoring
        case .screenRecording: self = .screenRecording
        }
    }

    var permission: Permission {
        switch self {
        case .microphone: .microphone
        case .accessibility: .accessibility
        case .inputMonitoring: .inputMonitoring
        case .screenRecording: .screenRecording
        }
    }
}
