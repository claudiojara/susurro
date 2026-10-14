import Domain

/// Where a permission stands for the user and the one step that fits it. The onboarding and the menu both decide by
/// this rule, so they cannot offer different steps for the same permission.
public struct PermissionStep: Equatable, Sendable {
    public enum Standing: Equatable, Sendable {
        case granted
        /// Nobody has asked for it yet.
        case notAsked
        case denied
        /// A prompt or System Settings is open and the status has not changed yet.
        case waiting
        /// The status did not change for long after the user came back: the troubleshooting steps apply.
        case stale
    }

    public enum Action: Equatable, Sendable {
        /// Ask the system, which may show its prompt.
        case request
        /// Open the permission's pane of System Settings.
        case openSettings
    }

    public let standing: Standing
    /// The one step the user can take now, or nil when there is none: it is granted, or the prompt is up.
    public let action: Action?

    /// The step for a permission, from its status and the follow-up of the monitor, if it has one.
    ///
    /// A follow-up decides it whatever the status says: a prompt that is up needs the user's answer and nothing else,
    /// and after that System Settings is the way on, also when the status did not become denied. With none, a
    /// permission nobody has asked for is asked for. A refusal opens System Settings, except for a permission whose
    /// denied status may mean never asked (`Permission.deniedMayMeanNotAsked`): there the request, which shows the
    /// system prompt that leads to System Settings, comes before the pane.
    public static func make(
        permission: Permission, status: PermissionStatus, followUp: PermissionsMonitor.FollowUp?
    ) -> PermissionStep {
        if status == .granted { return PermissionStep(standing: .granted, action: nil) }
        switch followUp {
        case .requesting: return PermissionStep(standing: .waiting, action: nil)
        case .sentToSettings: return PermissionStep(standing: .waiting, action: .openSettings)
        case .stale: return PermissionStep(standing: .stale, action: .openSettings)
        case nil: break
        }
        guard status == .denied else { return PermissionStep(standing: .notAsked, action: .request) }
        return PermissionStep(standing: .denied, action: permission.deniedMayMeanNotAsked ? .request : .openSettings)
    }
}
