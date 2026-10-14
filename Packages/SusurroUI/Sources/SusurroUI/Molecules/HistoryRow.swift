import DesignSystem
import SwiftUI

/// One dictation in the history: its status and when it happened, where and how long, its text, a note when there is
/// something to know, and the buttons that act on it. An action that cannot be taken is dimmed and the reason is written
/// under the buttons. It is a pure function of the row and the theme: it holds no state, and what the buttons do is
/// passed in.
struct HistoryRow: View {
    @Environment(\.theme) private var theme
    private let row: HistoryRowState
    private let onAction: (HistoryActionKind) -> Void

    init(_ row: HistoryRowState, onAction: @escaping (HistoryActionKind) -> Void) {
        self.row = row
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
            HStack(spacing: theme.spacing(.sm)) {
                Icon(row.status.symbol, style: .headline, tint: row.status.tint)
                TextLabel(row.statusLabel, style: .headline)
                Spacer(minLength: theme.spacing(.sm))
                TextLabel(row.timestamp, style: .caption, tint: .neutral)
            }
            .accessibilityElement(children: .combine)
            TextLabel(row.detail, style: .caption, tint: .neutral)
            TextLabel(row.text)
                .textSelection(.enabled)
            if let note = row.note {
                TextLabel(note, style: .caption, tint: row.status.noteTint)
            }
            if !row.actions.isEmpty {
                HStack(spacing: theme.spacing(.sm)) {
                    ForEach(row.actions) { action in
                        ActionButton(action.title) { onAction(action.kind) }
                            .disabled(!action.isAvailable)
                    }
                }
                ForEach(row.actions.compactMap(\.unavailableReason), id: \.self) { reason in
                    TextLabel(reason, style: .caption, tint: .neutral)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview("HistoryRow") { PreviewMatrix { HistoryRow.Gallery() } }
