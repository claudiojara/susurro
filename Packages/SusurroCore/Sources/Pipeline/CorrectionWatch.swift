import Domain
import Foundation
import TextShaping

/// What the correction watch needs of one pasted dictation: the text and the few characters around it, to find it again,
/// and where it went. It lives in memory only; the anchors are field text and are never stored or logged.
public struct InsertionReceipt: Sendable, Equatable {
    /// How many characters of the text before and after the cursor find the dictation again.
    public static let anchorLength = 80

    public let id: UUID
    public let finalText: String
    let anchorBefore: String
    let anchorAfter: String
    public let target: AppIdentity
    public let category: AppCategory
    public let isSecureField: Bool
    /// The title of the window the dictation went to, which tells its field from one in another window.
    public let windowTitle: String?
    /// The address of the page the dictation went to, for a browser.
    public let url: String?

    public init(
        id: UUID, finalText: String, anchorBefore: String, anchorAfter: String, target: AppIdentity,
        category: AppCategory, isSecureField: Bool, windowTitle: String? = nil, url: String? = nil
    ) {
        self.id = id
        self.finalText = finalText
        self.anchorBefore = anchorBefore
        self.anchorAfter = anchorAfter
        self.target = target
        self.category = category
        self.isSecureField = isSecureField
        self.windowTitle = windowTitle
        self.url = url
    }

    /// The receipt of a dictation pasted with the context it was captured with.
    init(id: UUID, finalText: String, context: ResolvedContext, target: AppIdentity) {
        self.init(
            id: id, finalText: finalText,
            anchorBefore: String(context.context.beforeCursor.suffix(Self.anchorLength)),
            anchorAfter: String(context.context.afterCursor.prefix(Self.anchorLength)), target: target,
            category: context.style.category, isSecureField: context.context.isSecureField,
            windowTitle: context.context.windowTitle, url: context.context.url)
    }
}

/// Watches a pasted dictation for the user's corrections. The pipeline hands it each pasted dictation, and the context of
/// the next one.
public protocol CorrectionWatching: Sendable {
    /// Starts watching a pasted dictation, in place of the one watched before.
    func watch(_ receipt: InsertionReceipt) async
    /// The context of the next dictation, which is a last look at the field of the watched one.
    func handoff(_ context: DictationContext) async
    /// Stops watching: something other than the user, such as a command's rewrite, changed the watched text.
    func cancel() async
}

/// Notices the words the user corrects right after a dictation, and suggests them for the dictionary. It never adds a
/// term by itself.
///
/// Only the latest pasted dictation is watched. The field is read again `rereadDelay` after the paste, while the same app
/// is in front; a correction found there ends the watch, unless the cursor is still in one of its words, which may be
/// half typed. Otherwise the next dictation's context, captured as its key goes down in the same app, is a last chance.
/// A field in another window or on another page (by title and address, when both were read) is never diffed, and a
/// command that replaces text ends the watch. The text that is read lives in memory for the diff only: the suggestion keeps
/// the corrected word and what the dictation had written, and the diagnostics keep only why the watch ended.
///
/// Nothing is watched when "learn from corrections" or "use app context" is off, in a secure field, or in a terminal.
public actor CorrectionWatch: CorrectionWatching {
    public static let rereadDelay: Duration = .seconds(5)

    private let reader: any FocusedContextReader
    private let frontmost: any FrontmostAppProvider
    private let store: any DictionarySuggestionStore
    private let dictionaryTerms: @Sendable () -> [String]
    private let filter: SuggestionFilter
    private let settings: any SettingsStore
    private let dates: any DateSource
    private let diagnostics: any DiagnosticsLog
    private let sleep: @Sendable (Duration) async throws -> Void

    private var pending: InsertionReceipt?
    private var reread: Task<Void, Never>?

    /// - Parameters:
    ///   - reader: Reads the focused field again, within its own time budget.
    ///   - dictionaryTerms: The user's terms, which are never suggested.
    ///   - settings: Where "learn from corrections" and "use app context" are read, at each dictation.
    public init(
        reader: any FocusedContextReader, frontmost: any FrontmostAppProvider, store: any DictionarySuggestionStore,
        dictionaryTerms: @escaping @Sendable () -> [String], filter: SuggestionFilter, settings: any SettingsStore,
        dates: any DateSource = SystemDateSource(), diagnostics: any DiagnosticsLog = NoDiagnostics(),
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.reader = reader
        self.frontmost = frontmost
        self.store = store
        self.dictionaryTerms = dictionaryTerms
        self.filter = filter
        self.settings = settings
        self.dates = dates
        self.diagnostics = diagnostics
        self.sleep = sleep
    }

    /// Whether a dictation is being watched.
    var isWatching: Bool { pending != nil }

    /// Returns once the scheduled reread, if any, has run.
    func settled() async {
        await reread?.value
    }

    public func watch(_ receipt: InsertionReceipt) {
        if pending != nil { finish(.replaced) }
        guard isEnabled, !receipt.isSecureField, receipt.category != .terminal else { return }
        pending = receipt
        reread = Task { await rereadAfterDelay(receipt.id) }
    }

    public func handoff(_ context: DictationContext) {
        guard let receipt = pending else { return }
        guard isEnabled else {
            stop()
            return
        }
        guard context.app?.processID == receipt.target.processID else { return finish(.appSwitched) }
        guard !context.isSecureField else { return finish(.unreadable) }
        guard Self.isSameWindow(as: receipt, title: context.windowTitle, url: context.url) else {
            return finish(.anchorLost)
        }
        let text = context.beforeCursor + context.afterCursor
        finish(learn(from: receipt, in: text, near: context.beforeCursor.utf16.count))
    }

    public func cancel() {
        guard pending != nil else { return }
        finish(.replaced)
    }

    private var isEnabled: Bool {
        settings.value(for: DictionarySettings.learnFromCorrections)
            && settings.value(for: ContextSettings.useAppContext)
    }

    /// Reads the field once, after the delay. Whatever it finds short of a suggestion leaves the watch to the handoff.
    private func rereadAfterDelay(_ id: UUID) async {
        do {
            try await sleep(Self.rereadDelay)
        } catch {
            return
        }
        guard let receipt = pending, receipt.id == id, isEnabled else { return }
        let front = await MainActor.run { [frontmost] in frontmost.current() }
        guard pending?.id == id, front?.processID == receipt.target.processID else { return }
        let snapshot = await reader.snapshot()
        guard pending?.id == id, let snapshot, !snapshot.isSecure, let text = snapshot.fieldText,
            Self.isSameWindow(as: receipt, title: snapshot.windowTitle, url: snapshot.url)
        else { return }
        let cursor = snapshot.selection?.lowerBound
        let typing = cursor.flatMap { Self.word(at: $0, in: text) }
        if learn(from: receipt, in: text, near: cursor, typing: typing) == .suggested { finish(.suggested) }
    }

    /// Whether a field read now is in the window, and on the page, the dictation went to. A title or an address that
    /// could not be read, then or now, does not tell them apart.
    private static func isSameWindow(as receipt: InsertionReceipt, title: String?, url: String?) -> Bool {
        func differs(_ then: String?, _ now: String?) -> Bool {
            guard let then, let now else { return false }
            return then != now
        }
        return !differs(receipt.windowTitle, title) && !differs(receipt.url, url)
    }

    /// The word the cursor at `offset` (UTF-16) is in or right after, or nil when it touches none.
    private static func word(at offset: Int, in text: String) -> String? {
        guard let cursor = text.utf16.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex) else {
            return nil
        }
        func isPart(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || "'’".contains(character)
        }
        let start = text[..<cursor].lastIndex(where: { !isPart($0) }).map(text.index(after:)) ?? text.startIndex
        let end = text[cursor...].firstIndex(where: { !isPart($0) }) ?? text.endIndex
        guard start < cursor || cursor < end else { return nil }
        return String(text[start..<end])
    }

    /// Diffs the dictation against the text and records what is worth suggesting. A correction that holds `typing`,
    /// the word the cursor is in, may be only half typed: then nothing is recorded, and the watch goes on.
    private func learn(
        from receipt: InsertionReceipt, in text: String, near hint: Int?, typing: String? = nil
    ) -> CorrectionWatchEnd {
        guard
            let corrections = CorrectionDiff.corrections(
                inserted: receipt.finalText, anchorBefore: receipt.anchorBefore, anchorAfter: receipt.anchorAfter,
                in: text, near: hint)
        else { return .anchorLost }
        if let typing, corrections.contains(where: { $0.corrected.split(separator: " ").contains { $0 == typing } }) {
            return .noCorrection
        }
        let accepted = filter.suggestions(from: corrections, in: text, known: dictionaryTerms() + store.dismissed())
        guard !accepted.isEmpty else { return .noCorrection }
        let now = dates.now()
        for correction in accepted {
            store.record(term: correction.corrected, heard: correction.heard, at: now)
        }
        return .suggested
    }

    private func finish(_ reason: CorrectionWatchEnd) {
        stop()
        diagnostics.record(.correctionWatchEnded(reason: reason))
    }

    private func stop() {
        pending = nil
        reread?.cancel()
        reread = nil
    }
}
