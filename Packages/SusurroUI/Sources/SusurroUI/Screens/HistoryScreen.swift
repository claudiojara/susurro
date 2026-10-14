import DesignSystem
import SwiftUI

/// The history: its title and the button that deletes everything, the question that stands before a deletion, the error of
/// something that failed, and the dictations newest first, or a sentence when there are none. It is a pure function of the
/// state and the theme: what the buttons do is passed in, and the screen asks the system for nothing.
struct HistoryScreen: View {
    @Environment(\.theme) private var theme
    private let state: HistoryViewState
    private let onAction: (UUID, HistoryActionKind) -> Void
    private let onLoadMore: () -> Void
    private let onDeleteAll: () -> Void
    private let onConfirm: () -> Void
    private let onCancel: () -> Void
    private let onDismissError: () -> Void

    init(
        state: HistoryViewState,
        onAction: @escaping (UUID, HistoryActionKind) -> Void,
        onLoadMore: @escaping () -> Void,
        onDeleteAll: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDismissError: @escaping () -> Void
    ) {
        self.state = state
        self.onAction = onAction
        self.onLoadMore = onLoadMore
        self.onDeleteAll = onDeleteAll
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onDismissError = onDismissError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
            HStack(spacing: theme.spacing(.sm)) {
                TextLabel(state.title, style: .title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: theme.spacing(.sm))
                if let title = state.deleteAllTitle {
                    ActionButton(title, action: onDeleteAll)
                }
            }
            if let confirmation = state.confirmation {
                HistoryNotice(
                    confirmation.message, symbol: "trash.fill", tint: .warning,
                    buttons: [
                        .init(title: confirmation.cancelTitle, kind: .secondary, action: onCancel),
                        .init(title: confirmation.confirmTitle, kind: .destructive, action: onConfirm),
                    ])
            }
            if let message = state.errorMessage {
                HistoryNotice(
                    message, symbol: "exclamationmark.triangle.fill", tint: .error,
                    buttons: [.init(title: state.dismissErrorTitle, kind: .secondary, action: onDismissError)])
            }
            if state.rows.isEmpty {
                TextLabel(state.emptyMessage, tint: .neutral)
            } else {
                ScrollView {
                    VStack(spacing: theme.spacing(.sm)) {
                        HistoryList(state.rows, onAction: onAction)
                        if let title = state.loadMoreTitle {
                            ActionButton(title, action: onLoadMore)
                        }
                    }
                }
            }
        }
        .padding(theme.spacing(.xl))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.swiftUIColor(.surfaceWindow))
    }
}

#Preview("HistoryScreen") { PreviewMatrix { HistoryScreen.Gallery() } }
