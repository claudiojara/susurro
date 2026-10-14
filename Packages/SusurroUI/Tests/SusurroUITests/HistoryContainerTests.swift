import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// A model that records what the screen asks of it.
@MainActor
private final class SpyModel: HistoryViewModeling {
    enum Call: Equatable {
        case copyRaw(UUID), copyCleaned(UUID), retry(UUID), requestDelete(UUID)
        case requestDeleteAll, confirm, cancel, loadMore, dismissError
    }

    var state: HistoryViewState
    private(set) var calls: [Call] = []

    init(_ state: HistoryViewState) {
        self.state = state
    }

    func copyRaw(_ id: UUID) async { calls.append(.copyRaw(id)) }
    func copyCleaned(_ id: UUID) async { calls.append(.copyCleaned(id)) }
    func retry(_ id: UUID) async { calls.append(.retry(id)) }
    func requestDelete(_ id: UUID) { calls.append(.requestDelete(id)) }
    func requestDeleteAll() { calls.append(.requestDeleteAll) }
    func confirmDeletion() async { calls.append(.confirm) }
    func cancelDeletion() { calls.append(.cancel) }
    func loadMore() async { calls.append(.loadMore) }
    func dismissError() { calls.append(.dismissError) }
}

@MainActor
@Suite("History container")
struct HistoryContainerTests {
    private let size = CGSize(width: 568, height: 640)
    private let id = UUID()

    private func png(of view: some View, scheme: ColorScheme = .light) -> Data {
        SnapshotSupport.pngData(of: view, size: size, scheme: scheme)
    }

    private func screen(_ state: HistoryViewState) -> HistoryScreen {
        HistoryScreen(
            state: state, onAction: { _, _ in }, onLoadMore: {}, onDeleteAll: {}, onConfirm: {}, onCancel: {},
            onDismissError: {})
    }

    @Test(
        "the container draws the state its model has: the screen of that state and no other",
        arguments: [HistoryFixtures.Screen.empty, .populated, .confirming, .error])
    func drawsTheModelsState(fixture: HistoryFixtures.Screen) {
        let state = HistoryFixtures.state(fixture)

        #expect(png(of: HistoryContainer(model: SpyModel(state))) == png(of: screen(state)))
    }

    @Test("a model that has another state is drawn differently")
    func followsTheModel() {
        let model = SpyModel(HistoryFixtures.state(.populated))
        let before = png(of: HistoryContainer(model: model))

        model.state = HistoryFixtures.state(.empty)

        #expect(png(of: HistoryContainer(model: model)) != before)
    }

    @Test("each button of a row asks the model for that action on that dictation")
    func rowActionsReachTheModel() async {
        let model = SpyModel(HistoryFixtures.state(.populated))

        for kind in HistoryActionKind.allCases { await HistoryContainer.perform(kind, on: id, model: model) }

        #expect(model.calls == [.copyRaw(id), .copyCleaned(id), .retry(id), .requestDelete(id)])
    }

    @Test("delete only asks: nothing is confirmed until the question is answered")
    func deleteOnlyAsks() async {
        let model = SpyModel(HistoryFixtures.state(.populated))

        await HistoryContainer.perform(.delete, on: id, model: model)

        #expect(model.calls == [.requestDelete(id)])
    }
}
