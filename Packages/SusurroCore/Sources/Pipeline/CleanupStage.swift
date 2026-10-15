import Domain
import TextShaping

/// Turns a transcript into the text that goes into the app. The raw transcript is always a valid result: every way the
/// cleanup can fail ends in it, with a reason, and the stage never throws except to say the dictation was cancelled.
///
/// The order is the design's: the deterministic passes (a snippet that is the whole dictation, then inline snippets,
/// fillers, and replacements), the skip rules, the input budget, the cleaner raced against its timeout, the output guard,
/// and the insertion shaper. The passes run whether or not cleanup is on, and a fallback keeps what they did.
public struct CleanupStage: Sendable {
    private let isEnabled: @Sendable () -> Bool
    private let cleaner: @Sendable () -> (any TranscriptCleaner)?
    private let rules: @Sendable () -> TranscriptRules
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - isEnabled: Whether cleanup is on, read for each dictation.
    ///   - cleaner: The cleaner to use now, or nil when none can be used.
    ///   - rules: The user's snippets, replacements, and filler switch, read for each dictation.
    ///   - sleep: Times the cleaner's limit. Tests pass the sleep of a `ManualClock`.
    public init(
        isEnabled: @escaping @Sendable () -> Bool,
        cleaner: @escaping @Sendable () -> (any TranscriptCleaner)?,
        rules: @escaping @Sendable () -> TranscriptRules = { .none },
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.isEnabled = isEnabled
        self.cleaner = cleaner
        self.rules = rules
        self.sleep = sleep
    }

    /// A stage over the settings and the registry: cleanup is on while `cleanup.enabled` is, the cleaner is the one the
    /// registry resolves from the selection, and the rules are the user's snippets, replacements, and filler switch.
    public init(
        settings: any SettingsStore, registry: CleanerRegistry,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.init(
            isEnabled: { settings.value(for: CleanupSettings.enabled) },
            cleaner: { registry.resolve().cleaner },
            rules: {
                TranscriptRules(
                    snippets: settings.value(for: TextRuleSettings.snippets),
                    replacements: settings.value(for: TextRuleSettings.replacements),
                    removesFillers: settings.value(for: TextRuleSettings.removeFillers))
            },
            sleep: sleep)
    }

    /// Cleans one dictation. Throws `CancellationError` when the dictation is cancelled meanwhile, so nothing is inserted.
    ///
    /// - Parameter willClean: Called just before the cleaner is, and only if it will be, so a caller can show that the
    ///   text is being polished. A cleanup that is skipped never calls it.
    public func run(
        _ input: CleanupInput, willClean: @Sendable () async -> Void = {}
    ) async throws -> CleanupResult {
        try Task.checkCancellation()
        let rules = rules()
        if let snippet = rules.snippet(matching: input.transcript) {
            return CleanupResult(
                raw: input.transcript, cleaned: nil, fallbackReason: nil, provider: nil,
                finalText: InsertionShaper.shape(
                    snippet, around: input.cursor, vocabulary: input.vocabulary, adjustsCase: false))
        }
        // A verbatim dictation keeps what was said, hesitations included; the user's own rules still apply.
        let passed = rules.removingFillers(rules.removesFillers && input.style.tone != .verbatim)
            .apply(to: input.transcript)
        let shaped = CleanupInput(
            transcript: passed.text, style: input.style, vocabulary: input.vocabulary, cursor: input.cursor)
        let result = try await clean(shaped, skip: passed.expandedSnippet, willClean: willClean)
        return CleanupResult(
            raw: input.transcript, cleaned: result.cleaned, fallbackReason: result.fallbackReason,
            provider: result.provider, finalText: result.finalText)
    }

    /// Cleans the text the passes left. `raw` in its result is that text. A dictation with a snippet expanded inside it
    /// is not cleaned: the cleaner would rewrite the user's own text.
    private func clean(
        _ input: CleanupInput, skip: Bool, willClean: @Sendable () async -> Void
    ) async throws -> CleanupResult {
        let raw = input.transcript
        guard isEnabled(), input.style.tone != .verbatim, !skip, !raw.allSatisfy(\.isWhitespace) else {
            return result(for: input, cleaned: nil, reason: nil, provider: nil)
        }
        guard let cleaner = cleaner() else {
            return result(for: input, cleaned: nil, reason: .providerUnavailable, provider: nil)
        }
        guard await cleaner.availability() == .available else {
            return result(for: input, cleaned: nil, reason: .providerUnavailable, provider: nil)
        }
        let budget = cleaner.budget
        guard raw.count <= budget.maxTranscriptCharacters else {
            return result(for: input, cleaned: nil, reason: .inputTooLarge, provider: nil)
        }
        let payload = CleanupRequestFactory.payload(for: cleaner, input: input)
        await willClean()
        let output: String
        do {
            output = try await withDeadline(
                budget.timeout(forTranscriptCharacters: raw.count), stage: .cleanup, sleep: sleep
            ) {
                try await cleaner.clean(payload)
            }
        } catch PipelineError.timedOut {
            return result(for: input, cleaned: nil, reason: .timeout, provider: cleaner.id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return result(for: input, cleaned: nil, reason: FallbackReason(thrownBy: error), provider: cleaner.id)
        }
        try Task.checkCancellation()
        let reference = input.vocabulary + [payload.contextText]
        switch OutputGuard.evaluate(raw: raw, output: output, reference: reference) {
        case .accepted(let text):
            return result(for: input, cleaned: text, reason: nil, provider: cleaner.id)
        case .fallback(let reason):
            return result(for: input, cleaned: nil, reason: reason, provider: cleaner.id)
        }
    }

    /// The result for the cleaned text, or for the raw transcript when there is none, shaped for the cursor.
    private func result(
        for input: CleanupInput, cleaned: String?, reason: FallbackReason?, provider: CleanerProviderID?
    ) -> CleanupResult {
        CleanupResult(
            raw: input.transcript, cleaned: cleaned, fallbackReason: reason, provider: provider,
            finalText: InsertionShaper.shape(
                cleaned ?? input.transcript, around: input.cursor, vocabulary: input.vocabulary)
        )
    }
}

extension CleanupPayload {
    /// The text before the cursor that a local request carries, or none.
    fileprivate var contextText: String {
        if case .local(let request) = self { request.beforeCursor } else { "" }
    }
}
