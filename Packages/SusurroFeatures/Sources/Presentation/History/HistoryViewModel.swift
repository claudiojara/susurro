import Domain
import Foundation
import Observation
import Pipeline
import SusurroUI

/// Adapts the history to the history screen's contract. It pages the repository, follows its change stream so a dictation
/// that finishes (or a retry that ends) shows without anyone asking, and turns the user's requests into the actions of
/// the core. Deleting asks first: a request only sets the question, and the deletion waits for the answer.
@MainActor
@Observable
public final class HistoryViewModel: HistoryViewModeling {
    /// How many dictations the list grows by each time the user asks for older ones.
    public static let pageSize = 50

    private enum Deletion: Equatable {
        case one(UUID)
        case all
    }

    @ObservationIgnored private let repository: any HistoryRepository
    @ObservationIgnored private let actions: HistoryActions
    @ObservationIgnored private let retries: RetryService
    @ObservationIgnored private let dates: any DateSource
    @ObservationIgnored private let mapper: HistoryRowMapper
    private var records: [DictationRecord] = []
    private var hasMore = false
    private var limit = HistoryViewModel.pageSize
    private var deletion: Deletion?
    private var errorMessage: String?

    public init(
        repository: any HistoryRepository, actions: HistoryActions, retries: RetryService, dates: any DateSource,
        calendar: Calendar = .current, locale: Locale = .current
    ) {
        self.repository = repository
        self.actions = actions
        self.retries = retries
        self.dates = dates
        mapper = HistoryRowMapper(calendar: calendar, locale: locale)
    }

    public var state: HistoryViewState {
        let now = dates.now()
        return HistoryViewState(
            title: HistoryCopy.title,
            rows: records.map { mapper.row(for: $0, now: now) },
            emptyMessage: HistoryCopy.emptyMessage,
            loadMoreTitle: hasMore ? HistoryCopy.loadMore : nil,
            deleteAllTitle: records.isEmpty ? nil : HistoryCopy.deleteAll,
            confirmation: confirmation,
            errorMessage: errorMessage,
            dismissErrorTitle: HistoryCopy.dismiss
        )
    }

    private var confirmation: HistoryConfirmation? {
        guard let deletion else { return nil }
        let question =
            switch deletion {
            case .one: HistoryCopy.deleteOneQuestion
            case .all: HistoryCopy.deleteAllQuestion
            }
        return HistoryConfirmation(
            message: question, confirmTitle: HistoryCopy.confirmDelete, cancelTitle: HistoryCopy.keep)
    }

    // MARK: Following the history

    /// Reads the first page, and again each time the history changes, until the task is cancelled. It subscribes before it
    /// reads, so a change that lands in between is not missed.
    public func run() async {
        let changes = repository.changes()
        await reload()
        for await _ in changes { await reload() }
    }

    /// Reads the dictations from the newest as far as the list has grown.
    public func reload() async {
        do {
            let page = try await repository.page(offset: 0, limit: limit + 1)
            hasMore = page.count > limit
            records = Array(page.prefix(limit))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = HistoryCopy.historyUnreadable
        }
    }

    public func loadMore() async {
        guard hasMore else { return }
        limit += Self.pageSize
        await reload()
    }

    // MARK: Copy and retry

    public func copyRaw(_ id: UUID) async {
        await perform { try await actions.copyRaw(id) }
    }

    public func copyCleaned(_ id: UUID) async {
        await perform { try await actions.copyCleaned(id) }
    }

    public func retry(_ id: UUID) async {
        do {
            if case .refused(let refusal) = try await retries.retry(id) {
                errorMessage = HistoryCopy.refusal(refusal)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = HistoryCopy.historyNotSaved
        }
        await reload()
    }

    // MARK: Deleting

    public func requestDelete(_ id: UUID) {
        guard records.contains(where: { $0.id == id }) else { return }
        deletion = .one(id)
    }

    public func requestDeleteAll() {
        guard !records.isEmpty else { return }
        deletion = .all
    }

    public func cancelDeletion() {
        deletion = nil
    }

    public func confirmDeletion() async {
        guard let deletion else { return }
        self.deletion = nil
        await perform {
            switch deletion {
            case .one(let id): try await actions.delete(id)
            case .all: try await actions.deleteAll()
            }
        }
        await reload()
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: Errors

    /// Runs an action of the core and turns what it throws into the sentence the screen shows.
    private func perform(_ body: () async throws -> Void) async {
        do {
            try await body()
        } catch let error as HistoryActionError {
            errorMessage = Self.message(for: error)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = HistoryCopy.historyNotSaved
        }
    }

    private static func message(for error: HistoryActionError) -> String {
        switch error {
        case .recordNotFound: HistoryCopy.recordGone
        case .nothingToCopy: HistoryCopy.nothingToCopy
        case .audioNotDeleted(let count): HistoryCopy.audioNotDeleted(count: count)
        }
    }
}
