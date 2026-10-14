import SwiftUI

/// Puts the onboarding screen in front of the code that drives it. It reads the state of its model and sends the steps
/// the user takes to it: the screen below knows neither. The model computes `state` from observable properties, so a
/// change to a permission redraws the screen without anything here asking for it.
public struct OnboardingContainer: View {
    private let model: any OnboardingViewModeling
    private let onDone: () -> Void

    /// - Parameter onDone: What the Done button does: the window that holds the screen closes itself.
    public init(model: any OnboardingViewModeling, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
    }

    public var body: some View {
        let model = model
        OnboardingScreen(
            state: model.state,
            onAction: { permission, action in Task { await Self.perform(action, for: permission, on: model) } },
            onRecheck: { Task { await model.recheck() } },
            onDone: onDone)
    }

    /// Does the step of a row: asks the system for the permission, or opens its pane of System Settings.
    static func perform(
        _ action: OnboardingAction, for permission: OnboardingPermission, on model: any OnboardingViewModeling
    ) async {
        switch action.kind {
        case .request: await model.request(permission)
        case .openSettings: model.openSettings(permission)
        }
    }
}
