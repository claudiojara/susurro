import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// The checklist is the rows of the state, one under the other, in the order of the state. A state has one row for each
/// permission, so the rows here are taken from the screens' fixtures and never repeat a permission.
@MainActor
@Suite("Permission checklist")
struct PermissionChecklistTests {
    private let width: CGFloat = 392
    private let canvas = CGSize(width: 424, height: 330)
    private let rows = OnboardingFixtures.rows(.withOptional)

    private func checklist(_ rows: [OnboardingRowState]) -> PermissionChecklist {
        PermissionChecklist(rows) { _, _ in }
    }

    private func height(_ rows: [OnboardingRowState], theme: Theme = .default) -> CGFloat {
        Probe.height(of: checklist(rows), width: width, theme: theme)
    }

    @Test("it has no height without rows, and as much as the row with one")
    func oneRowIsTheRow() {
        let row = Probe.height(of: PermissionRow(rows[2]) { _ in }, width: width)

        #expect(height([]) == 0)
        #expect(abs(height([rows[2]]) - row) <= 1, "\(height([rows[2]])) against \(row)")
    }

    @Test("rows are stacked with the sm space between them", arguments: [8.0, 20.0])
    func rowsAreSpaced(gap: Double) {
        // The rows use the sm space inside as well, so each one is measured in the same theme.
        let theme = Probe.spaced(.sm, gap)
        let heights = rows.map { height([$0], theme: theme) }

        #expect(abs(height(rows, theme: theme) - (heights.reduce(0, +) + 3 * gap)) <= 1, "\(heights)")
    }

    @Test("the rows are drawn in the order of the state")
    func rowsKeepTheirOrder() throws {
        // The first row of this state is allowed, which paints in the success color, and the second one is stale, which
        // paints in the warning color.
        let state = OnboardingFixtures.rows(.stale)
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            func top(_ rows: [OnboardingRowState], in token: ColorToken) throws -> CGFloat {
                let picture = Probe.picture(of: checklist(rows), size: canvas, scheme: scheme)
                let found = SnapshotSupport.extent(of: picture, matching: theme.color(token), tolerance: Probe.exact)
                return try #require(found, "nothing is painted in \(token)").minY
            }

            #expect(try top(state, in: .statusSuccess) < top(state, in: .statusWarning))
            #expect(try top(state.reversed(), in: .statusWarning) < top(state.reversed(), in: .statusSuccess))
        }
    }
}
