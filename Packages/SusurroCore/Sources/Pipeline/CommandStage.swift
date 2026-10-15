import Domain
import TextShaping

/// Command mode: the instruction said while the command hotkey is held rewrites the selected text, and the result
/// replaces the selection (ADR 0033).
///
/// The selection is read as the key goes down (`start`), before anything is recorded. Once the instruction is
/// transcribed, `run` hands both to the on-device model within a limit that grows with their length, checks the reply
/// (`CommandOutputGuard`), reads the selection again, and pastes the result over it only when it is still the one the
/// command was said over: a paste over a live selection replaces it, and one undo of the app brings it back. A selection
/// that changed meanwhile is left alone, and the result goes to the clipboard. The reply is collected whole and never
/// streamed into the app, since a half-replaced selection is worse than none.
///
/// The selection and the result are text of the field: they live in memory for their command and are never stored or
/// logged. The rewrite runs on this Mac only.
public struct CommandStage: Sendable {
    /// What the key-down of a command found.
    enum Start: Sendable, Equatable {
        /// The command may record. The selection travels with it.
        case selection(String)
        /// The command cannot run, and the error says why.
        case failure(PipelineError)
        /// There is nothing to rewrite, and the notice says why. Nothing is recorded.
        case notice(CommandNotice)
    }

    /// How a command ended, for the state to show and the record.
    struct Outcome: Sendable, Equatable {
        let state: PipelineState
        let status: DictationStatus
        let delivery: DictationDelivery?
        /// The fixed name of why nothing was replaced, or nil.
        let reason: String?
    }

    /// The `failure` of a command record that replaced nothing.
    static let noResultFailure = "commandNoResult"

    let isEnabled: @Sendable () -> Bool
    let rewriter: any SelectionRewriter
    let reader: any FocusedContextReader
    let clipboard: any ClipboardWriting
    let diagnostics: any DiagnosticsLog

    /// - Parameters:
    ///   - isEnabled: Whether command mode is turned on (`CommandSettings.enabled`).
    ///   - rewriter: The on-device model. A rewriter that is not local is never handed a selection.
    ///   - reader: Reads the focused element, for the selection.
    ///   - clipboard: Where the result goes when the selection changed while the model worked.
    public init(
        isEnabled: @escaping @Sendable () -> Bool,
        rewriter: any SelectionRewriter,
        reader: any FocusedContextReader,
        clipboard: any ClipboardWriting,
        diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        self.isEnabled = isEnabled
        self.rewriter = rewriter
        self.reader = reader
        self.clipboard = clipboard
        self.diagnostics = diagnostics
    }

    // MARK: Start

    /// Checks what a command needs as its key goes down, in order: command mode on, Accessibility, the model, and a
    /// selection to rewrite. Every read is bounded.
    func start(
        permissions: any PermissionsChecker, sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async -> Start {
        guard isEnabled() else { return .failure(.commandUnavailable(.turnedOff)) }
        let accessibility = try? await withDeadline(DictationLimits.statusTimeout, stage: .capture, sleep: sleep) {
            await permissions.status(.accessibility)
        }
        guard accessibility == .granted else { return .failure(.commandUnavailable(.accessibilityMissing)) }
        let rewriter = rewriter
        let availability = try? await withDeadline(DictationLimits.statusTimeout, stage: .capture, sleep: sleep) {
            await rewriter.availability()
        }
        guard availability == .available else { return .failure(.commandUnavailable(.modelUnavailable)) }
        switch await readSelection(sleep: sleep) {
        case .text(let text): return .selection(text)
        case .none: return .notice(.noSelection)
        case .tooLong: return .notice(.selectionTooLong)
        case .secure: return .notice(.secureField)
        case .unreadable: return .notice(.selectionUnreadable)
        }
    }

    // MARK: Run

    /// Rewrites `selection` as `instruction` says and puts the result in its place. It throws only when the command was
    /// cancelled (`checkpoint`) or the paste ran out of time.
    func run(
        instruction: String,
        selection: String,
        target: AppIdentity?,
        inserter: any TextInserter,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        checkpoint: () throws -> Void,
        report: @escaping @Sendable (PipelineState) async -> Void
    ) async throws -> Outcome {
        await report(.rewriting)
        guard rewriter.locality == .local else { return noResult("notLocal") }
        let request = LocalCommandRequest(instruction: instruction, selection: selection)
        let rewriter = rewriter
        let reply: String
        do {
            reply = try await withDeadline(
                CommandLimits.timeout(instruction: instruction.count, selection: selection.count), stage: .cleanup,
                sleep: sleep
            ) { try await rewriter.rewrite(request) }
        } catch let error as CancellationError {
            throw error
        } catch PipelineError.timedOut {
            return noResult("timedOut")
        } catch {
            try checkpoint()
            return noResult(error is CommandPromptError ? "inputTooLarge" : "failed")
        }
        try checkpoint()
        let text: String
        switch CommandOutputGuard.evaluate(selection: selection, instruction: instruction, output: reply) {
        case .accepted(let accepted): text = Self.keepingLineBreak(of: selection, in: accepted)
        case .rejected(let reason): return noResult(reason.rawValue)
        }

        // The selection must still be the one the command was said over: a paste replaces whatever is selected now.
        guard case .text(let current) = await readSelection(sleep: sleep, limit: .max),
            SelectionReader.isSame(current, selection)
        else {
            try checkpoint()
            await clipboard.copy(text)
            return Outcome(
                state: .notice(.command(.selectionChanged)), status: .succeeded, delivery: .copiedToClipboard,
                reason: nil)
        }
        try checkpoint()
        let outcome = try await withDeadline(DictationLimits.insertionTimeout, stage: .insertion, sleep: sleep) {
            await inserter.insert(text, into: target)
        }
        let state: PipelineState =
            switch outcome {
            case .inserted: .replaced
            case .copiedToClipboard(let reason): .notice(.copiedToClipboard(reason))
            case .notInserted(let reason): .error(.notInserted(reason))
            }
        return Outcome(state: state, status: .succeeded, delivery: DictationDelivery(outcome), reason: nil)
    }

    /// Reads the selection, at most `statusTimeout`: a reader that does not answer reads as nothing read.
    private func readSelection(
        sleep: @escaping @Sendable (Duration) async throws -> Void, limit: Int = CommandLimits.maxSelection
    ) async -> SelectionCapture {
        let reader = reader
        let snapshot = try? await withDeadline(DictationLimits.statusTimeout, stage: .capture, sleep: sleep) {
            await reader.snapshot()
        }
        return SelectionReader.capture(from: snapshot ?? nil, limit: limit)
    }

    private func noResult(_ reason: String) -> Outcome {
        diagnostics.record(.commandNoResult(reason: reason))
        return Outcome(state: .notice(.command(.noResult)), status: .failed, delivery: nil, reason: reason)
    }

    /// A selection that ends a line keeps its line break, which a model drops.
    private static func keepingLineBreak(of selection: String, in text: String) -> String {
        guard let last = selection.last, last.isNewline, !(text.last?.isNewline ?? false) else { return text }
        return text + String(last)
    }
}
