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

    @Test("a permission row in each state", arguments: rows, Probe.schemes)
    func rows(canvas: OnboardingCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }
}
