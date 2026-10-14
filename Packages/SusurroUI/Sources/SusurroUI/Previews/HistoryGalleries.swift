import DesignSystem
import SwiftUI

// What the history views look like, in one place: each gallery shows every state of one view. The previews draw these, and
// the snapshot tests draw the same fixtures one by one.
#if DEBUG

    extension HistoryRow {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(spacing: theme.spacing(.sm)) {
                    ForEach(HistoryFixtures.Row.allCases, id: \.self) {
                        HistoryRow(HistoryFixtures.row($0)) { _ in }
                    }
                }
            }
        }
    }

    extension HistoryNotice {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(spacing: theme.spacing(.sm)) {
                    HistoryNotice(
                        "Delete this dictation and its audio? This cannot be undone.", symbol: "trash.fill",
                        tint: .warning,
                        buttons: [
                            .init(title: "Keep", kind: .secondary, action: {}),
                            .init(title: "Delete", kind: .destructive, action: {}),
                        ])
                    HistoryNotice(
                        "The audio of 1 dictation could not be deleted, so the dictation was kept. Try again.",
                        symbol: "exclamationmark.triangle.fill", tint: .error,
                        buttons: [.init(title: "Dismiss", kind: .secondary, action: {})])
                }
            }
        }
    }

    extension HistoryList {
        struct Gallery: View {
            var body: some View {
                HistoryList(HistoryFixtures.rows(.populated)) { _, _ in }
            }
        }
    }

    extension HistoryScreen {
        struct Gallery: View {
            var body: some View {
                HistoryScreen(
                    state: HistoryFixtures.state(.populated), onAction: { _, _ in }, onLoadMore: {}, onDeleteAll: {},
                    onConfirm: {}, onCancel: {}, onDismissError: {})
            }
        }
    }

    /// A model with a fixed state, for the preview of the container.
    @MainActor
    private final class PreviewModel: HistoryViewModeling {
        let state: HistoryViewState

        init(_ state: HistoryViewState) {
            self.state = state
        }

        func copyRaw(_ id: UUID) async {}
        func copyCleaned(_ id: UUID) async {}
        func retry(_ id: UUID) async {}
        func requestDelete(_ id: UUID) {}
        func requestDeleteAll() {}
        func confirmDeletion() async {}
        func cancelDeletion() {}
        func loadMore() async {}
        func dismissError() {}
    }

    #Preview("HistoryContainer") {
        PreviewMatrix { HistoryContainer(model: PreviewModel(HistoryFixtures.state(.populated))) }
    }

#endif
