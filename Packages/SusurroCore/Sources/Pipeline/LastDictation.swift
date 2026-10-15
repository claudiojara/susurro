import Domain

/// What became of a request for the last dictation.
public enum LastDictationOutcome: Sendable, Equatable {
    /// The history has no dictation with text.
    case nothing
    /// The text went to the inserter, which did this with it.
    case pasted(InsertionOutcome)
    /// The text was put on the clipboard.
    case copied

    /// What the overlay tells the user, or nil when the result speaks for itself (the text is in the app) or the
    /// inserter already said what went wrong.
    public var notice: NoticeKind? {
        switch self {
        case .nothing: .noLastDictation
        case .copied: .lastDictationCopied
        case .pasted(.copiedToClipboard(let reason)): .copiedToClipboard(reason)
        case .pasted(.inserted), .pasted(.notInserted): nil
        }
    }
}

/// Pastes or copies the final text of the most recent dictation that succeeded, as the history kept it; a command is
/// never one. The paste goes through the same inserter as a dictation, so it waits its turn behind one, and the user's
/// clipboard comes back after it. The text goes wherever the focus is: no target app is checked.
public struct LastDictation: Sendable {
    private let repository: any HistoryRepository
    private let inserter: any TextInserter
    private let clipboard: any ClipboardWriting
    private let pageSize: Int
    /// How many records are looked at, at most, before the search gives up. A history of that many failures in a row has
    /// nothing worth pasting.
    private let searchLimit: Int

    public init(
        repository: any HistoryRepository, inserter: any TextInserter, clipboard: any ClipboardWriting,
        pageSize: Int = 50, searchLimit: Int = 500
    ) {
        self.repository = repository
        self.inserter = inserter
        self.clipboard = clipboard
        self.pageSize = max(1, pageSize)
        self.searchLimit = searchLimit
    }

    /// The final text of the newest dictation that succeeded with text, or nil. A history that cannot be read has none.
    public func text() async -> String? {
        var offset = 0
        while offset < searchLimit {
            guard let page = try? await repository.page(offset: offset, limit: pageSize) else { return nil }
            // A command keeps no text of its own: its instruction is not something to paste.
            let found = page.first {
                $0.kind == .dictation && $0.status == .succeeded && !($0.finalText ?? "").isEmpty
            }
            if let text = found?.finalText { return text }
            if page.count < pageSize { return nil }
            offset += page.count
        }
        return nil
    }

    /// Pastes the last dictation at the cursor of the app in front.
    public func paste() async -> LastDictationOutcome {
        guard let text = await text() else { return .nothing }
        return .pasted(await inserter.insert(text, into: nil))
    }

    /// Puts the last dictation on the clipboard.
    public func copy() async -> LastDictationOutcome {
        guard let text = await text() else { return .nothing }
        await clipboard.copy(text)
        return .copied
    }
}
