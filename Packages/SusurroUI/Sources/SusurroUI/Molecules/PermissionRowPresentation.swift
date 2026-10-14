import DesignSystem

/// How a row shows where its permission stands: a tint and a symbol, beside the word that the state carries. The three
/// together tell the statuses apart without color alone.
struct StatusBadge: Equatable {
    let tint: Tint
    let symbol: String
}

extension OnboardingRowStatus {
    var badge: StatusBadge {
        switch self {
        case .granted: StatusBadge(tint: .success, symbol: "checkmark.circle.fill")
        case .notAsked: StatusBadge(tint: .neutral, symbol: "circle")
        case .denied: StatusBadge(tint: .error, symbol: "xmark.circle.fill")
        case .waiting: StatusBadge(tint: .pending, symbol: "hourglass")
        case .stale: StatusBadge(tint: .warning, symbol: "exclamationmark.triangle.fill")
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
