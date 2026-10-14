import Domain
import SusurroUI

/// The words of the onboarding, in one place: the screen, its rows, its window, and the menu item that opens it take all
/// of their words from here (the screen and the rows through the `OnboardingViewState` that the view model builds, which
/// carries every word, and the window and the menu through `title`). The sentences are in the string catalog of the module
/// (`Localizable.xcstrings`), under the keys written here.
enum OnboardingCopy {
    /// The name of the onboarding: the title of the screen and of its window, and the menu item that opens it (with an
    /// ellipsis, since the item opens a window).
    static var title: String { L10n.string("onboarding.title", "Set up Susurro") }
    static var subtitle: String {
        L10n.string("onboarding.subtitle", "Susurro needs these permissions to hear you and to type what you say.")
    }
    static var recheckTitle: String { L10n.string("onboarding.recheck", "Check again") }
    static var doneTitle: String { L10n.string("onboarding.done", "Done") }

    /// The word a row shows in its pill for where its permission stands.
    static func statusText(_ standing: PermissionStep.Standing) -> String {
        switch standing {
        case .granted: L10n.string("onboarding.status.granted", "Allowed")
        case .notAsked: L10n.string("onboarding.status.notAsked", "Not asked yet")
        case .denied: L10n.string("onboarding.status.denied", "Not allowed")
        case .waiting: L10n.string("onboarding.status.waiting", "Waiting…")
        case .stale: L10n.string("onboarding.status.stale", "Needs attention")
        }
    }

    /// The troubleshooting steps that fit the permission. Every pane has a switch to turn off and on. Input Monitoring and
    /// Screen Recording apply a change only after the app is relaunched. Microphone has no add button, so there is
    /// nothing to remove and add again.
    static func staleGuidance(_ permission: Permission) -> String {
        let switchIt = L10n.string("onboarding.guidance.switch", "In System Settings, switch Susurro off and on again.")
        let relaunch = L10n.string(
            "onboarding.guidance.relaunch",
            "Then quit and reopen Susurro, because this permission applies only after a relaunch.")
        let addAgain = L10n.string(
            "onboarding.guidance.addAgain",
            "If it still does not work, remove Susurro from the list, add it again, and switch it on.")
        let steps =
            switch permission {
            case .microphone: [switchIt]
            case .accessibility: [switchIt, addAgain]
            case .inputMonitoring, .screenRecording: [switchIt, relaunch, addAgain]
            }
        return ([L10n.string("onboarding.guidance.prefix", "Still not allowed?")] + steps).joined(separator: " ")
    }

    static var openSettingsAction: OnboardingAction {
        OnboardingAction(
            kind: .openSettings, title: L10n.string("onboarding.action.openSettings", "Open System Settings"))
    }

    static func requestAction(_ permission: Permission) -> OnboardingAction {
        OnboardingAction(
            kind: .request, title: L10n.string("onboarding.action.allow", "Allow \(permission.displayName)"))
    }

    /// The button for a step of `PermissionStep`.
    static func action(_ action: PermissionStep.Action, for permission: Permission) -> OnboardingAction {
        switch action {
        case .request: requestAction(permission)
        case .openSettings: openSettingsAction
        }
    }

    /// The status a row shows for where the permission stands. A stale one carries the troubleshooting that fits it.
    static func status(_ standing: PermissionStep.Standing, for permission: Permission) -> OnboardingRowStatus {
        switch standing {
        case .granted: .granted
        case .notAsked: .notAsked
        case .denied: .denied
        case .waiting: .waiting
        case .stale: .stale(guidance: staleGuidance(permission))
        }
    }

    static func why(_ permission: Permission) -> String {
        switch permission {
        case .microphone:
            L10n.string("onboarding.why.microphone", "Needed to hear you while you hold the dictation hotkey.")
        case .accessibility:
            L10n.string("onboarding.why.accessibility", "Needed to paste the dictated text into the app you are using.")
        case .inputMonitoring:
            L10n.string(
                "onboarding.why.inputMonitoring", "Needed to notice a hotkey made only of modifier keys, such as fn.")
        case .screenRecording:
            L10n.string(
                "onboarding.why.screenRecording", "Needed to read the text on your screen as context for the cleanup.")
        }
    }

    /// The feature each conditional permission is for. `PermissionPolicy` decides which permissions are conditional, and a
    /// test keeps this table to exactly those, so the copy cannot drift from the policy.
    static var features: [Permission: String] {
        [
            .inputMonitoring: L10n.string("onboarding.feature.inputMonitoring", "a hotkey made of modifier keys"),
            .screenRecording: L10n.string("onboarding.feature.screenRecording", "reading on-screen text"),
        ]
    }

    /// Whether the permission holds dictation back, from the policy. An optional one says which feature it is for and
    /// that dictation works without it.
    static func requirement(
        _ permission: Permission, features: [Permission: String] = OnboardingCopy.features
    ) -> OnboardingRequirement {
        guard !PermissionPolicy.required.contains(permission) else { return .required }
        let feature = features[permission].map { L10n.string("onboarding.optional.onlyFor", "only for \($0). ") } ?? ""
        return .optional(
            featureNote: L10n.string("onboarding.optional.note", "Optional: \(feature)Dictation works without it."))
    }
}
