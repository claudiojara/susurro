import DesignSystem

/// How a row shows where its permission stands: a word, a tint, and a symbol. The three together tell the statuses apart
/// without color alone.
struct StatusBadge: Equatable {
    let text: String
    let tint: Tint
    let symbol: String
}

extension OnboardingRowStatus {
    var badge: StatusBadge {
        switch self {
        case .granted: StatusBadge(text: "Allowed", tint: .success, symbol: "checkmark.circle.fill")
        case .notAsked: StatusBadge(text: "Not asked yet", tint: .neutral, symbol: "circle")
        case .denied: StatusBadge(text: "Not allowed", tint: .error, symbol: "xmark.circle.fill")
        case .waiting: StatusBadge(text: "Waiting…", tint: .accent, symbol: "hourglass")
        case .stale: StatusBadge(text: "Needs attention", tint: .warning, symbol: "exclamationmark.triangle.fill")
        }
    }
}

extension OnboardingAction.Kind {
    /// Asking the system is the step that moves the user on, so it is the main button; opening System Settings is the
    /// way out of a row that is stuck, and is quieter.
    var buttonKind: ActionButton.Kind {
        switch self {
        case .request: .primary
        case .openSettings: .secondary
        }
    }
}
