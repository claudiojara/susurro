import SwiftUI

/// Puts the history screen in front of the code that drives it. It reads the state of its model and sends what the user
/// does to it: the screen below knows neither. The model computes `state` from observable properties, so a change to the
/// history redraws the screen without anything here asking for it.
public struct HistoryContainer: View {
    private let model: any HistoryViewModeling

    public init(model: any HistoryViewModeling) {
        self.model = model
    }

    public var body: some View {
        let model = model
        HistoryScreen(
            state: model.state,
            onAction: { id, action in Task { await Self.perform(action, on: id, model: model) } },
            onLoadMore: { Task { await model.loadMore() } },
            onDeleteAll: { model.requestDeleteAll() },
            onConfirm: { Task { await model.confirmDeletion() } },
            onCancel: { model.cancelDeletion() },
            onDismissError: { model.dismissError() })
    }

    /// Does what a button of a row asks. Delete only asks: the model deletes after the confirmation.
    static func perform(_ action: HistoryActionKind, on id: UUID, model: any HistoryViewModeling) async {
        switch action {
        case .copyRaw: await model.copyRaw(id)
        case .copyCleaned: await model.copyCleaned(id)
        case .retry: await model.retry(id)
        case .delete: model.requestDelete(id)
        }
    }
}
