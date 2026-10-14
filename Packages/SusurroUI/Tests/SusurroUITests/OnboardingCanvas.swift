import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// The canvas each onboarding view is drawn on for its snapshot. A picture matches when 99.9 % of its pixels do, so a
/// canvas is just big enough for what it shows (`OnboardingCanvasTests`), and its size is written here, not measured: a
/// canvas that followed the fonts of the machine would give a picture of another size on another macOS.
enum OnboardingCanvas: CaseIterable, Sendable, CustomTestStringConvertible {
    case rowGranted, rowNotAsked, rowDenied, rowWaitingForPrompt, rowWaitingInSettings, rowStale, rowOptional
    case bannerShort, bannerLong
    case checklistRequired, checklistWithOptional

    var testDescription: String { "\(self)" }

    /// The width a row has inside the onboarding screen, plus the margin of the canvas.
    private static let rowWidth: CGFloat = 424

    var size: CGSize {
        switch self {
        case .rowGranted: CGSize(width: Self.rowWidth, height: 108)
        case .rowNotAsked: CGSize(width: Self.rowWidth, height: 148)
        case .rowDenied: CGSize(width: Self.rowWidth, height: 148)
        case .rowWaitingForPrompt: CGSize(width: Self.rowWidth, height: 108)
        case .rowWaitingInSettings: CGSize(width: Self.rowWidth, height: 148)
        case .rowStale: CGSize(width: Self.rowWidth, height: 198)
        case .rowOptional: CGSize(width: Self.rowWidth, height: 200)
        case .bannerShort: CGSize(width: Self.rowWidth, height: 70)
        case .bannerLong: CGSize(width: Self.rowWidth, height: 90)
        case .checklistRequired: CGSize(width: Self.rowWidth, height: 300)
        case .checklistWithOptional: CGSize(width: Self.rowWidth, height: 500)
        }
    }

    @MainActor var view: AnyView {
        switch self {
        case .rowGranted: row(.granted)
        case .rowNotAsked: row(.notAsked)
        case .rowDenied: row(.denied)
        case .rowWaitingForPrompt: row(.waitingForPrompt)
        case .rowWaitingInSettings: row(.waitingInSettings)
        case .rowStale: row(.stale)
        case .rowOptional: row(.optional)
        case .bannerShort: AnyView(Banner(OnboardingFixtures.shortBanner))
        case .bannerLong: AnyView(Banner(OnboardingFixtures.longBanner))
        case .checklistRequired: AnyView(PermissionChecklist(OnboardingFixtures.rows(.fresh)) { _, _ in })
        case .checklistWithOptional: AnyView(PermissionChecklist(OnboardingFixtures.rows(.withOptional)) { _, _ in })
        }
    }

    @MainActor private func row(_ fixture: OnboardingFixtures.Row) -> AnyView {
        AnyView(PermissionRow(OnboardingFixtures.row(fixture)) { _ in })
    }
}
