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

    public func onboardingDidAppear() {
        monitor.setOnboardingVisible(true)
    }

    public func onboardingDidDisappear() {
        monitor.setOnboardingVisible(false)
    }

    // MARK: Rows

    private func row(for permission: Permission) -> OnboardingRowState {
        let status = status(of: permission)
        return OnboardingRowState(
            id: OnboardingPermission(permission),
            title: permission.displayName,
            why: OnboardingCopy.why(permission),
            isOptional: !PermissionPolicy.required.contains(permission),
            featureNote: OnboardingCopy.featureNote(permission),
            status: status,
            action: action(for: permission, shown: status),
            staleGuidance: status == .stale ? OnboardingCopy.staleGuidance : nil
        )
    }

    private func status(of permission: Permission) -> OnboardingRowStatus {
        let reading = monitor.statuses[permission] ?? .notDetermined
        if reading == .granted { return .granted }
        if monitor.staleGuidance.contains(permission) { return .stale }
        if monitor.waiting.contains(permission) { return .waiting }
        return reading == .denied ? .denied : .notAsked
    }

    /// The step that fits where the permission stands. Accessibility and Screen Recording are reported only as allowed
    /// or not, so for them denied can mean never asked, and the request, which shows the system prompt that leads to
    /// System Settings, comes before the pane.
    private func action(for permission: Permission, shown status: OnboardingRowStatus) -> OnboardingAction? {
        switch status {
        case .granted:
            return nil
        case .notAsked:
            return OnboardingCopy.requestAction(permission)
        case .denied:
            return OnboardingCopy.deniedMeansNotAskedYet.contains(permission)
                ? OnboardingCopy.requestAction(permission) : OnboardingCopy.openSettingsAction
        case .waiting:
            // A prompt that is up needs the user's answer. Otherwise the user was sent to System Settings.
            return monitor.statuses[permission] == .denied ? OnboardingCopy.openSettingsAction : nil
        case .stale:
            return OnboardingCopy.openSettingsAction
        }
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
