// The contract between the history screen and the code that drives it. The screen draws these values and calls the
// intents; it knows nothing of the core, so the status of a dictation has a name of its own here and the view model in
// `SusurroFeatures` maps it. Every text is ready to show: the screen writes no word of its own.

import Foundation

/// How a dictation stands, for the dot and the word at the top of its row.
public nonisolated enum HistoryRowStatus: Equatable, Sendable, CaseIterable {
    case processing
    case succeeded
    case noSpeech
    case failed
    case cancelled
}

/// The things a row can do.
public nonisolated enum HistoryActionKind: Equatable, Sendable, CaseIterable {
    case copyRaw
    case copyCleaned
    /// Run the dictation again from its stored audio. Nothing is pasted.
    case retry
    case delete
}

/// One button of a row.
public nonisolated struct HistoryRowAction: Equatable, Sendable, Identifiable {
    public let kind: HistoryActionKind
    public let title: String
    /// Why the action cannot be taken now, or nil when it can. The row shows the reason next to the disabled button.
    public let unavailableReason: String?

    public var id: HistoryActionKind { kind }
    public var isAvailable: Bool { unavailableReason == nil }

    public init(kind: HistoryActionKind, title: String, unavailableReason: String? = nil) {
        self.kind = kind
        self.title = title
        self.unavailableReason = unavailableReason
    }
}

/// One dictation in the list.
public nonisolated struct HistoryRowState: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let status: HistoryRowStatus
    /// The word for the status, such as "Done" or "Failed".
    public let statusLabel: String
    /// When it was dictated, such as "Today, 14:32".
    public let timestamp: String
    /// The app, the length, and anything else worth a glance, on one line.
    public let detail: String
    /// The text of the dictation, or the sentence that stands in for it when there is none.
    public let text: String
    /// What the user should know about this dictation: why it failed, that the text only lives here, that audio expired.
    public let note: String?
    public let actions: [HistoryRowAction]

    public init(
        id: UUID, status: HistoryRowStatus, statusLabel: String, timestamp: String, detail: String, text: String,
        note: String?, actions: [HistoryRowAction]
    ) {
        self.id = id
        self.status = status
        self.statusLabel = statusLabel
        self.timestamp = timestamp
        self.detail = detail
        self.text = text
        self.note = note
        self.actions = actions
    }
}

/// A question the screen asks before something is deleted for good.
public nonisolated struct HistoryConfirmation: Equatable, Sendable {
    public let message: String
    public let confirmTitle: String
    public let cancelTitle: String

    public init(message: String, confirmTitle: String, cancelTitle: String) {
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
    }
}

/// Everything the history screen shows.
public nonisolated struct HistoryViewState: Equatable, Sendable {
    public let title: String
    public let rows: [HistoryRowState]
    /// Shown instead of the list while there is no dictation.
    public let emptyMessage: String
    /// The title of the button that shows older dictations, or nil when there are no more.
    public let loadMoreTitle: String?
    /// The title of the button that deletes every dictation, or nil when there is nothing to delete.
    public let deleteAllTitle: String?
    public let confirmation: HistoryConfirmation?
    /// What went wrong with the last thing the user asked for, such as audio that could not be deleted.
    public let errorMessage: String?
    public let dismissErrorTitle: String

    public init(
        title: String, rows: [HistoryRowState], emptyMessage: String, loadMoreTitle: String?, deleteAllTitle: String?,
        confirmation: HistoryConfirmation?, errorMessage: String?, dismissErrorTitle: String
    ) {
        self.title = title
        self.rows = rows
        self.emptyMessage = emptyMessage
        self.loadMoreTitle = loadMoreTitle
        self.deleteAllTitle = deleteAllTitle
        self.confirmation = confirmation
        self.errorMessage = errorMessage
        self.dismissErrorTitle = dismissErrorTitle
    }
}

/// What the history screen needs from the code behind it.
@MainActor
public protocol HistoryViewModeling: AnyObject {
    var state: HistoryViewState { get }

    func copyRaw(_ id: UUID) async
    func copyCleaned(_ id: UUID) async
    func retry(_ id: UUID) async
    /// Asks to delete one dictation. Nothing is deleted until `confirmDeletion`.
    func requestDelete(_ id: UUID)
    /// Asks to delete every dictation. Nothing is deleted until `confirmDeletion`.
    func requestDeleteAll()
    func confirmDeletion() async
    func cancelDeletion()
    func loadMore() async
    func dismissError()
}
