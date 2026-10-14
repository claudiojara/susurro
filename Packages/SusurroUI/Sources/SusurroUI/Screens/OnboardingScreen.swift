import DesignSystem
import SwiftUI

/// The onboarding: what Susurro needs and why, a banner while a required permission is missing, the permissions with the step for each,
/// and the buttons to check again and to finish. It is a pure function of the state and the theme: what the steps and
/// the buttons do is passed in, and the screen asks the system for nothing.
struct OnboardingScreen: View {
    @Environment(\.theme) private var theme
    private let state: OnboardingViewState
    private let onAction: (OnboardingPermission, OnboardingAction) -> Void
    private let onRecheck: () -> Void
    private let onDone: () -> Void

    init(
        state: OnboardingViewState,
        onAction: @escaping (OnboardingPermission, OnboardingAction) -> Void,
        onRecheck: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.state = state
        self.onAction = onAction
        self.onRecheck = onRecheck
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                TextLabel(state.title, style: .title)
                    .accessibilityAddTraits(.isHeader)
                TextLabel(state.subtitle, tint: .neutral)
            }
            if let message = state.restrictionMessage {
                Banner(message)
            }
            PermissionChecklist(state.rows, onAction: onAction)
            HStack(spacing: theme.spacing(.sm)) {
                ActionButton(state.recheckTitle, action: onRecheck)
                Spacer(minLength: theme.spacing(.sm))
                ActionButton(state.doneTitle, kind: .primary, action: onDone)
                    .disabled(!state.isDoneEnabled)
            }
        }
        .padding(theme.spacing(.xl))
        .frame(width: theme.layout(.onboardingWidth))
        .background(theme.swiftUIColor(.surfaceWindow))
    }
}

#Preview("OnboardingScreen") { PreviewMatrix { OnboardingScreen.Gallery() } }
