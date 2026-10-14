import Domain
import SusurroUI

/// The words of the onboarding.
enum OnboardingCopy {
    static let staleGuidance =
        "Still not allowed? In System Settings, remove Susurro from the list, add it again, and switch it on."

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

    /// For an optional permission: the feature it is for, and that dictation works without it. A required one has none.
    static func featureNote(_ permission: Permission) -> String? {
        switch permission {
        case .microphone, .accessibility: nil
        case .inputMonitoring: "Optional: only for a hotkey made of modifier keys. Dictation works without it."
        case .screenRecording: "Optional: only for reading on-screen text. Dictation works without it."
        }
    }
}
