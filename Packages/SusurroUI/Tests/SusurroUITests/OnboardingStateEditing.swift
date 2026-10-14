@testable import SusurroUI

/// A state with some of its parts replaced, for tests that change one thing about a fixture and look at what the view
/// does with it.
extension OnboardingRowState {
    func with(
        title: String? = nil, why: String? = nil, requirement: OnboardingRequirement? = nil,
        status: OnboardingRowStatus? = nil, statusText: String? = nil, action: OnboardingAction?? = nil
    ) -> OnboardingRowState {
        OnboardingRowState(
            id: id, title: title ?? self.title, why: why ?? self.why, requirement: requirement ?? self.requirement,
            status: status ?? self.status, statusText: statusText ?? self.statusText,
            action: action ?? self.action)
    }
}

extension OnboardingViewState {
    func with(
        title: String? = nil, subtitle: String? = nil, rows: [OnboardingRowState]? = nil,
        restrictionMessage: String?? = nil, recheckTitle: String? = nil, doneTitle: String? = nil,
        isDoneEnabled: Bool? = nil
    ) -> OnboardingViewState {
        OnboardingViewState(
            title: title ?? self.title, subtitle: subtitle ?? self.subtitle, rows: rows ?? self.rows,
            restrictionMessage: restrictionMessage ?? self.restrictionMessage,
            recheckTitle: recheckTitle ?? self.recheckTitle, doneTitle: doneTitle ?? self.doneTitle,
            isDoneEnabled: isDoneEnabled ?? self.isDoneEnabled)
    }
}
