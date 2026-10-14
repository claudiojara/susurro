import DesignSystem
import SwiftUI

/// The onboarding: what Susurro needs and why, a banner while a required permission is missing, the permissions with the
/// step for each, and the buttons to check again and to finish. It is a pure function of the state and the theme: what
/// the steps and the buttons do is passed in, and the screen asks the system for nothing.
///
/// The screen is as tall as its content, unless it is given a height it may not exceed (a window on a small display). Then
/// the banner and the checklist scroll between the title and the buttons, which stay where they are, so the way to finish
/// is never out of reach.
struct OnboardingScreen: View {
    @Environment(\.theme) private var theme
    private let state: OnboardingViewState
    private let maxHeight: CGFloat?
    private let onAction: (OnboardingPermission, OnboardingAction) -> Void
    private let onRecheck: () -> Void
    private let onDone: () -> Void

    /// - Parameter maxHeight: The most the screen may take, or nil for as much as its content needs.
    init(
        state: OnboardingViewState,
        maxHeight: CGFloat?,
        onAction: @escaping (OnboardingPermission, OnboardingAction) -> Void,
        onRecheck: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.state = state
        self.maxHeight = maxHeight
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
            // The checklist as it is when it fits, and in a scroll view when it does not.
            ViewThatFits(in: .vertical) {
                checklist
                ScrollView { checklist }
            }
            HStack(spacing: theme.spacing(.sm)) {
                ActionButton(state.recheckTitle, action: onRecheck)
                Spacer(minLength: theme.spacing(.sm))
                ActionButton(state.doneTitle, kind: .primary, action: onDone)
                    .disabled(!state.isDoneEnabled)
            }
        }
        .padding(theme.spacing(.xl))
        .frame(width: theme.layout(.onboardingWidth))
        .frame(maxHeight: maxHeight)
        .background(theme.swiftUIColor(.surfaceWindow))
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
            if let message = state.restrictionMessage {
                Banner(message)
            }
            PermissionChecklist(state.rows, onAction: onAction)
        }
    }
}

#Preview("OnboardingScreen") { PreviewMatrix { OnboardingScreen.Gallery() } }
