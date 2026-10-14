import DesignSystem
import SwiftUI

/// The dictations of the history, one row under the other in the order of the state, newest first. What a row's buttons do
/// is passed in, with the dictation they belong to.
struct HistoryList: View {
    @Environment(\.theme) private var theme
    private let rows: [HistoryRowState]
    private let onAction: (UUID, HistoryActionKind) -> Void

    init(_ rows: [HistoryRowState], onAction: @escaping (UUID, HistoryActionKind) -> Void) {
        self.rows = rows
        self.onAction = onAction
    }

    var body: some View {
        LazyVStack(spacing: theme.spacing(.sm)) {
            ForEach(rows) { row in
                HistoryRow(row) { onAction(row.id, $0) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("HistoryList") { PreviewMatrix { HistoryList.Gallery() } }
