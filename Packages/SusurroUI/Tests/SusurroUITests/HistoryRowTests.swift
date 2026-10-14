import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// What a history row and the history screen paint, read from their pixels and their size, in light and dark. The
/// snapshots say the picture did not change; these say what is in it.
@MainActor
@Suite("History row")
struct HistoryRowTests {
    private let width: CGFloat = 568
    private var canvas: CGSize { CGSize(width: width, height: 300) }

    private func row(_ fixture: HistoryFixtures.Row, onAction: @escaping (HistoryActionKind) -> Void = { _ in })
        -> HistoryRow
    {
        HistoryRow(HistoryFixtures.row(fixture), onAction: onAction)
    }

    private func screen(_ fixture: HistoryFixtures.Screen) -> HistoryScreen {
        HistoryScreen(
            state: HistoryFixtures.state(fixture), onAction: { _, _ in }, onLoadMore: {}, onDeleteAll: {},
            onConfirm: {}, onCancel: {}, onDismissError: {})
    }

    @Test(
        "the symbol is painted in the tint of the status, at the left end of the first line",
        arguments: [
            (HistoryFixtures.Row.succeeded, ColorToken.statusSuccess),
            (.failed, .statusError),
            (.processing, .statusPending),
            (.cancelled, .statusWarning),
        ])
    func statusTint(fixture: HistoryFixtures.Row, token: ColorToken) throws {
        for scheme in Probe.schemes {
            let picture = Probe.picture(of: row(fixture), size: canvas, scheme: scheme)

            let painted = try #require(
                SnapshotSupport.extent(of: picture, matching: Probe.theme(scheme).color(token), tolerance: Probe.exact),
                "\(fixture) paints nothing in \(token) in \(scheme)")

            #expect(painted.minX < 60, "\(fixture) in \(scheme): \(painted)")
        }
    }

    @Test("a failure note is painted in the error color, below the text")
    func failureNoteIsRed() throws {
        for scheme in Probe.schemes {
            let failed = Probe.picture(of: row(.failed), size: canvas, scheme: scheme)
            let done = Probe.picture(of: row(.succeeded), size: canvas, scheme: scheme)
            let error = try Probe.theme(scheme).color(.statusError)

            let failedExtent = try #require(SnapshotSupport.extent(of: failed, matching: error, tolerance: Probe.exact))
            #expect(SnapshotSupport.extent(of: done, matching: error, tolerance: Probe.exact) == nil)
            // The symbol is on the first line and the note is further down, so the red reaches below the symbol.
            #expect(failedExtent.height > 40, "\(failedExtent)")
        }
    }

    @Test("the reason an action is unavailable is written under the buttons, and the row is taller for it")
    func unavailableReasonIsShown() {
        let expired = HistoryFixtures.row(.audioExpired)
        let reason = expired.actions.compactMap(\.unavailableReason)
        let without = HistoryRowState(
            id: expired.id, status: expired.status, statusLabel: expired.statusLabel, timestamp: expired.timestamp,
            detail: expired.detail, text: expired.text, note: expired.note,
            actions: expired.actions.map { HistoryRowAction(kind: $0.kind, title: $0.title) })

        let with = Probe.height(of: HistoryRow(expired) { _ in }, width: 520)
        let plain = Probe.height(of: HistoryRow(without) { _ in }, width: 520)

        #expect(reason == ["Audio expired after 7 days."])
        #expect(with > plain + 10, "\(with) against \(plain)")
    }

    @Test("a processing row has no buttons, so it is shorter than a done one")
    func processingHasNoButtons() {
        let processing = Probe.height(of: row(.processing), width: 520)
        let done = Probe.height(of: row(.succeeded), width: 520)

        #expect(processing + 20 < done, "\(processing) against \(done)")
    }

    @Test("the screen shows the empty message and no list when there is no dictation")
    func emptyScreen() {
        let empty = Probe.height(of: screen(.empty), width: 568)
        let populated = Probe.height(of: screen(.populated), width: 568)

        #expect(empty + 100 < populated, "\(empty) against \(populated)")
    }

    @Test("the question before a deletion and the error each take room on the screen")
    func noticesTakeRoom() {
        let plain = HistoryFixtures.state(.populated)
        let asking = HistoryFixtures.state(.confirming)
        let failing = HistoryFixtures.state(.error)
        func height(_ state: HistoryViewState) -> CGFloat {
            Probe.height(
                of: HistoryScreen(
                    state: state, onAction: { _, _ in }, onLoadMore: {}, onDeleteAll: {}, onConfirm: {}, onCancel: {},
                    onDismissError: {}), width: 568)
        }
        let one = HistoryViewState(
            title: plain.title, rows: Array(plain.rows.prefix(1)), emptyMessage: plain.emptyMessage,
            loadMoreTitle: nil, deleteAllTitle: plain.deleteAllTitle, confirmation: nil, errorMessage: nil,
            dismissErrorTitle: plain.dismissErrorTitle)

        #expect(height(asking) > height(one) + 40)
        #expect(height(failing) > height(one) + 40)
    }
}
