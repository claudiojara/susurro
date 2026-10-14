import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// The checklist is the rows of the state, one under the other, in the order of the state.
@MainActor
@Suite("Permission checklist")
struct PermissionChecklistTests {
    private let width: CGFloat = 392
    private let canvas = CGSize(width: 424, height: 330)

    private func checklist(_ rows: [OnboardingFixtures.Row]) -> PermissionChecklist {
        PermissionChecklist(rows.map(OnboardingFixtures.row)) { _, _ in }
    }

    private func height(_ rows: [OnboardingFixtures.Row], theme: Theme = .default) -> CGFloat {
        Probe.height(of: checklist(rows), width: width, theme: theme)
    }

    @Test("it has no height without rows, and as much as the row with one")
    func oneRowIsTheRow() {
        let row = Probe.height(of: PermissionRow(OnboardingFixtures.row(.denied)) { _ in }, width: width)

        #expect(height([]) == 0)
        #expect(abs(height([.denied]) - row) <= 1, "\(height([.denied])) against \(row)")
    }

    @Test("rows are stacked with the sm space between them")
    func rowsAreSpaced() {
        let rows: [OnboardingFixtures.Row] = [.granted, .denied, .stale]
        let heights = rows.map { height([$0]) }

        #expect(abs(height(rows) - (heights.reduce(0, +) + 2 * 8)) <= 1, "\(height(rows)) against \(heights)")
        #expect(abs(height(rows, theme: Probe.spaced(.sm, 20)) - (heights.reduce(0, +) + 2 * 20)) <= 1)
    }

    @Test("the rows are drawn in the order of the state")
    func rowsKeepTheirOrder() throws {
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            func top(_ rows: [OnboardingFixtures.Row], in token: ColorToken) throws -> CGFloat {
                let picture = Probe.picture(of: checklist(rows), size: canvas, scheme: scheme)
                let found = SnapshotSupport.extent(of: picture, matching: theme.color(token), tolerance: Probe.exact)
                return try #require(found, "nothing is painted in \(token)").minY
            }

            // The granted row paints in the success color and the denied one in the error color.
            #expect(try top([.granted, .denied], in: .statusSuccess) < top([.granted, .denied], in: .statusError))
            #expect(try top([.denied, .granted], in: .statusError) < top([.denied, .granted], in: .statusSuccess))
        }
    }
}
