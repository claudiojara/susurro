import Domain
import SusurroUI

/// The words of the onboarding.
enum OnboardingCopy {
    /// The troubleshooting steps that fit the permission. Every pane has a switch to turn off and on. Input Monitoring and
    /// Screen Recording apply a change only after the app is relaunched. Microphone has no add button, so there is
    /// nothing to remove and add again.
    static func staleGuidance(_ permission: Permission) -> String {
        let switchIt = "In System Settings, switch Susurro off and on again."
        let relaunch = "Then quit and reopen Susurro, because this permission applies only after a relaunch."
        let addAgain = "If it still does not work, remove Susurro from the list, add it again, and switch it on."
        let steps =
            switch permission {
            case .microphone: [switchIt]
            case .accessibility: [switchIt, addAgain]
            case .inputMonitoring, .screenRecording: [switchIt, relaunch, addAgain]
            }
        return (["Still not allowed?"] + steps).joined(separator: " ")
    }

    static let openSettingsAction = OnboardingAction(kind: .openSettings, title: "Open System Settings")

    static func requestAction(_ permission: Permission) -> OnboardingAction {
        OnboardingAction(kind: .request, title: "Allow \(permission.displayName)")
    }

    static func why(_ permission: Permission) -> String {
        switch permission {
        case .microphone: "Needed to hear you while you hold the dictation hotkey."
        case .accessibility: "Needed to paste the dictated text into the app you are using."
        case .inputMonitoring: "Needed to notice a hotkey made only of modifier keys, such as fn."
        case .screenRecording: "Needed to read the text on your screen as context for the cleanup."
        }
    }

    /// The feature each conditional permission is for. `PermissionPolicy` decides which permissions are conditional, and a
    /// test keeps this table to exactly those, so the copy cannot drift from the policy.
    static let features: [Permission: String] = [
        .inputMonitoring: "a hotkey made of modifier keys",
        .screenRecording: "reading on-screen text",
    ]

    /// Whether the permission holds dictation back, from the policy. An optional one says which feature it is for and
    /// that dictation works without it.
    static func requirement(
        _ permission: Permission, features: [Permission: String] = OnboardingCopy.features
    ) -> OnboardingRequirement {
        guard !PermissionPolicy.required.contains(permission) else { return .required }
        let feature = features[permission].map { "only for \($0). " } ?? ""
        return .optional(featureNote: "Optional: \(feature)Dictation works without it.")
    }
}
