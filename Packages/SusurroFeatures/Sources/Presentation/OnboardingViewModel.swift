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
            dictationDisabledMessage: monitor.disabledReason?.message
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
        let (status, action) = standing(of: permission)
        return OnboardingRowState(
            id: OnboardingPermission(permission),
            title: permission.displayName,
            why: OnboardingCopy.why(permission),
            requirement: OnboardingCopy.requirement(permission),
            status: status,
            action: action
        )
    }

    /// Where the permission stands for the user and the one step that fits. A follow-up of the monitor decides it
    /// whatever the status says: a prompt that is up needs the user's answer and nothing else, and after that System
    /// Settings is the way on, also when the status did not become denied.
    private func standing(of permission: Permission) -> (OnboardingRowStatus, OnboardingAction?) {
        let reading = monitor.statuses[permission] ?? .notDetermined
        if reading == .granted { return (.granted, nil) }
        switch monitor.followUps[permission] {
        case .requesting: return (.waiting, nil)
        case .sentToSettings: return (.waiting, OnboardingCopy.openSettingsAction)
        case .stale:
            return (.stale(guidance: OnboardingCopy.staleGuidance(permission)), OnboardingCopy.openSettingsAction)
        case nil: break
        }
        guard reading == .denied else { return (.notAsked, OnboardingCopy.requestAction(permission)) }
        // For a permission whose denied status may mean never asked (`Permission.deniedMayMeanNotAsked`) the request,
        // which shows the system prompt that leads to System Settings, comes before the pane.
        return (
            .denied,
            permission.deniedMayMeanNotAsked
                ? OnboardingCopy.requestAction(permission) : OnboardingCopy.openSettingsAction
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
