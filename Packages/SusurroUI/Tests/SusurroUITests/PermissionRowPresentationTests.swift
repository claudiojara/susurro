import DesignSystem
import SusurroUI
import Testing

@testable import SusurroUI

@MainActor
@Suite("Permission row presentation")
struct PermissionRowPresentationTests {
    @Test(
        "each status has a word, a tint, and a symbol of its own",
        arguments: [
            (OnboardingRowStatus.granted, "Allowed", Tint.success, "checkmark.circle.fill"),
            (.notAsked, "Not asked yet", .neutral, "circle"),
            (.denied, "Not allowed", .error, "xmark.circle.fill"),
            (.waiting, "Waiting…", .pending, "hourglass"),
            (.stale(guidance: "Switch it off and on."), "Needs attention", .warning, "exclamationmark.triangle.fill"),
            (.stale(guidance: "Quit and reopen."), "Needs attention", .warning, "exclamationmark.triangle.fill"),
        ]
    )
    func badge(status: OnboardingRowStatus, text: String, tint: Tint, symbol: String) {
        let badge = status.badge

        #expect(badge.text == text)
        #expect(badge.tint == tint)
        #expect(badge.symbol == symbol)
    }

    @Test("no two statuses read alike, so the badge alone tells them apart")
    func badgesDiffer() {
        let statuses: [OnboardingRowStatus] = [.granted, .notAsked, .denied, .waiting, .stale(guidance: "x")]

        let badges = statuses.map(\.badge)

        #expect(Set(badges.map(\.text)).count == statuses.count)
        #expect(Set(badges.map(\.symbol)).count == statuses.count)
        #expect(Set(badges.map(\.tint)).count == statuses.count)
    }

    @Test(
        "asking the system is the main step of a row, and opening System Settings the quieter one",
        arguments: [(OnboardingAction.Kind.request, ActionButton.Kind.primary), (.openSettings, .secondary)]
    )
    func buttonKind(action: OnboardingAction.Kind, button: ActionButton.Kind) {
        #expect(action.buttonKind == button)
    }
}
