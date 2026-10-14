import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// One picture per view and appearance, each on a canvas just big enough for it (`OnboardingCanvas`). The references are
/// recorded on the CI image (`record-snapshots`), never here, and `make test` skips these suites by their name.
@MainActor
@Suite("Onboarding snapshots")
struct OnboardingSnapshotTests {
    nonisolated private static let rows: [OnboardingCanvas] = [
        .rowGranted, .rowNotAsked, .rowDenied, .rowWaitingForPrompt, .rowWaitingInSettings, .rowStale, .rowOptional,
    ]

    nonisolated private static let banners: [OnboardingCanvas] = [.bannerShort, .bannerLong]
    nonisolated private static let checklists: [OnboardingCanvas] = [.checklistRequired, .checklistWithOptional]

    @Test("a permission row in each state", arguments: rows, Probe.schemes)
    func rows(canvas: OnboardingCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the warning banner with a short and a long message", arguments: banners, Probe.schemes)
    func banners(canvas: OnboardingCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the checklist with the required rows and with the optional ones", arguments: checklists, Probe.schemes)
    func checklists(canvas: OnboardingCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }
}
