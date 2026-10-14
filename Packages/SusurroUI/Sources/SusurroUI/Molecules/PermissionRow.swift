import DesignSystem
import SwiftUI

/// One permission in the onboarding checklist: its name and where it stands, why the app needs it, what the optional
/// ones are for, the steps to take when a grant went stale, and the one action the user can take. It is a pure function
/// of the row and the theme: it holds no state, and what the action does is passed in.
struct PermissionRow: View {
    @Environment(\.theme) private var theme
    private let row: OnboardingRowState
    private let onAction: (OnboardingAction) -> Void

    init(_ row: OnboardingRowState, onAction: @escaping (OnboardingAction) -> Void) {
        self.row = row
        self.onAction = onAction
    }

    var body: some View {
        let badge = row.status.badge
        let card = RoundedRectangle(cornerRadius: theme.radius(.md), style: .continuous)
        VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
            HStack(spacing: theme.spacing(.sm)) {
                Icon(badge.symbol, style: .headline, tint: badge.tint)
                TextLabel(row.title, style: .headline)
                Spacer(minLength: theme.spacing(.sm))
                Pill(badge.text, tint: badge.tint)
            }
            .accessibilityElement(children: .combine)
            TextLabel(row.why, tint: .neutral)
            if case .optional(let featureNote) = row.requirement {
                TextLabel(featureNote, style: .caption, tint: .neutral)
            }
            if case .stale(let guidance) = row.status {
                TextLabel(guidance, style: .caption, tint: .warning)
            }
            if let action = row.action {
                ActionButton(action.title, kind: action.kind.buttonKind) { onAction(action) }
            }
        }
        .padding(theme.spacing(.md))
        .background(theme.swiftUIColor(.surfaceRaised), in: card)
        .overlay(card.strokeBorder(theme.swiftUIColor(.borderSubtle)))
    }
}

#Preview("PermissionRow") { PreviewMatrix { PermissionRow.Gallery() } }
