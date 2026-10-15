import Domain
import Foundation
import Synchronization

/// What a recording is for.
public enum DictationIntent: Sendable, Equatable {
    /// Text to insert at the cursor.
    case dictate
    /// An instruction that rewrites `selection`, the text that was selected as the command key went down. The selection
    /// lives in memory for its command only.
    case command(selection: String)

    /// The kind of record the attempt makes.
    var kind: DictationKind {
        switch self {
        case .dictate: .dictation
        case .command: .command
        }
    }
}

/// One finished recording on its way to the user's text.
public struct DictationJob: Sendable {
    public let recording: VerifiedRecording
    /// Suspends until the key of the hold that made the recording is up. Nil when the key is already up. A hold that ended
    /// at the recording cap or because the device went away has its key down while the text is ready, and pasting then
    /// fails on the modifiers of the hotkey.
    public let waitForKeyRelease: (@Sendable () async throws -> Void)?
    /// The app that was in front as the key went down: the text is pasted into it and no other. Nil pastes wherever the
    /// focus is.
    public let target: AppIdentity?
    /// The capture of the context that began as the key went down. Nil when no context is captured.
    let context: ContextJob?
    /// The vocabulary work that began with the context. Nil gives the recognizer and the cleaner no vocabulary.
    let vocabulary: VocabularyJob?
    /// A dictation, or a command over a selection.
    public let intent: DictationIntent

    public init(
        recording: VerifiedRecording, waitForKeyRelease: (@Sendable () async throws -> Void)? = nil,
        target: AppIdentity? = nil, intent: DictationIntent = .dictate
    ) {
        self.init(
            recording: recording, waitForKeyRelease: waitForKeyRelease, target: target, context: nil, vocabulary: nil,
            intent: intent)
    }

    init(
        recording: VerifiedRecording, waitForKeyRelease: (@Sendable () async throws -> Void)?, target: AppIdentity?,
        context: ContextJob?, vocabulary: VocabularyJob?, intent: DictationIntent = .dictate
    ) {
        self.recording = recording
        self.waitForKeyRelease = waitForKeyRelease
        self.target = target
        self.context = context
        self.vocabulary = vocabulary
        self.intent = intent
    }
}

/// Everything that happens to a recording after it is on disk, in order:
///
/// 1. a history record is created, as `processing`, with the audio reference, before anything reads the audio;
/// 2. voice activity detection runs on the stored file: no speech, and a muted microphone, end the attempt there;
/// 3. the recognizer transcribes the speech span, waiting for a model that is still loading; a blank transcript ends the
///    attempt as no speech. Meanwhile the context captured at key-down is waited for, briefly, and the style is chosen;
///    the record keeps the app, the page host and the style, never the text of the context;
/// 4. the cleanup stage polishes the transcript for that style, or falls back to the raw text with a reason;
/// 5. the text goes to the inserter, once the key of a capped hold is up;
/// 6. the record is updated with the outcome: the raw, cleaned and final text, the providers and any fallback.
///
/// A command (`DictationIntent.command`) leaves this path after step 3: the transcript is its instruction, which the
/// `CommandStage` applies to the selection, and the record, of kind `command`, keeps the instruction and never the
/// selection or the result.
///
/// The recording stays on disk whatever happens, and the record says how the attempt ended, so a failure can be retried
/// from the history. The pipeline never leaves a stage open: each is bounded, the whole is bounded, and the cancel
/// token is checked at every boundary.
public struct DictationPipeline: Sendable {
    /// How an attempt ended.
    public enum Result: Sendable, Equatable {
        /// The state to show: `inserted`, a notice, or an error.
        case finished(PipelineState)
        /// The user cancelled it, or the app is shutting down. There is nothing to show.
        case cancelled
    }

    private let recordings: any AudioRecordingStore
    private let history: any HistoryRepository
    private let detector: any VoiceActivityDetector
    private let runner: RecognitionRunner
    private let inserter: any TextInserter
    private let cleanup: CleanupStage?
    private let dates: any DateSource
    private let diagnostics: any DiagnosticsLog
    private let corrections: (any CorrectionWatching)?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let cancelRequests = CancelRequests()
    /// Command mode. Without it a command is never started.
    let command: CommandStage?

    /// - Parameters:
    ///   - cleanup: The stage that cleans the transcript. Without one the raw transcript is inserted.
    ///   - corrections: Watches each pasted dictation for the user's corrections, and gets each dictation's context.
    ///   - command: Command mode over the selection. Without it the command hotkey does nothing.
    public init(
        recordings: any AudioRecordingStore,
        history: any HistoryRepository,
        detector: any VoiceActivityDetector,
        runner: RecognitionRunner,
        inserter: any TextInserter,
        cleanup: CleanupStage? = nil,
        dates: any DateSource = SystemDateSource(),
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        corrections: (any CorrectionWatching)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        command: CommandStage? = nil
    ) {
        self.command = command
        self.recordings = recordings
        self.history = history
        self.detector = detector
        self.runner = runner
        self.inserter = inserter
        self.cleanup = cleanup
        self.dates = dates
        self.diagnostics = diagnostics
        self.corrections = corrections
        self.sleep = sleep
    }

    /// Asks for the attempt `id` to end as cancelled at its next stage boundary, with its audio kept and nothing
    /// inserted. Call it before cancelling the task that runs the attempt.
    public func cancel(_ id: UUID) {
        cancelRequests.add(id)
    }

    /// Keeps a recording that the user cancelled while it was still recording: a cancelled record with its audio, and
    /// nothing is transcribed or inserted.
    public func keepCancelled(_ recording: VerifiedRecording, kind: DictationKind = .dictation) async {
        _ = await Attempt.begin(
            for: recording, status: .cancelled, kind: kind, history: history, dates: dates, diagnostics: diagnostics)
    }

    /// Returns once the inserter has finished what it has in hand, such as putting the clipboard back.
    public func drainInserter() async {
        await inserter.drain()
    }

    /// Runs the attempt. It does not throw: every way it can end is a `Result`, and the record says which.
    ///
    /// - Parameter report: Told the state to show while the attempt waits for the speech model.
    public func process(
        _ job: DictationJob, report: @escaping @Sendable (PipelineState) async -> Void
    ) async -> Result {
        let id = job.recording.id.rawValue
        defer {
            job.context?.cancel()
            job.vocabulary?.cancel()
        }
        let tracker = StageTracker()
        let attempt = await Attempt.begin(
            for: job.recording, status: .processing, kind: job.intent.kind, history: history, dates: dates,
            diagnostics: diagnostics)
        do {
            let state = try await withDeadline(
                DictationLimits.processingCap, stageAtExpiry: { tracker.stageAtCapExpiry() }, sleep: sleep
            ) {
                try await run(job, attempt: attempt, tracker: tracker, report: report)
            }
            return .finished(state)
        } catch {
            if cancelRequests.contains(id) {
                await attempt.amend { $0.status = .cancelled }
                return .cancelled
            }
            // The app is shutting down: the record stays `processing`, and the next launch marks it interrupted.
            if Task.isCancelled { return .cancelled }
            if tracker.capRanOut { diagnostics.record(.processingCapReached) }
            let failure = Self.pipelineError(from: error)
            await attempt.amend {
                $0.status = .failed
                $0.failure = failure.kind
            }
            return .finished(.error(failure))
        }
    }

    // MARK: Stages

    private func run(
        _ job: DictationJob, attempt: Attempt, tracker: StageTracker,
        report: @escaping @Sendable (PipelineState) async -> Void
    ) async throws -> PipelineState {
        let id = job.recording.id.rawValue
        try checkpoint(id)
        let clip: AudioClip
        do {
            clip = try await recordings.load(job.recording)
        } catch {
            throw PipelineError.persistenceFailed("the recording could not be read back")
        }

        // Voice detection. A detector that fails (its model could not load) must not lose the dictation: the clip goes to
        // the recognizer whole, and only the silence check on the signal itself is left.
        try checkpoint(id)
        let found = await detectSpeech(in: clip)
        let wholeClip = VADResult(segments: [SpeechSegment(start: .zero, end: clip.duration)])
        if let notice = SilenceClassifier.classify(clip, result: found ?? wholeClip).notice {
            await attempt.amend { $0.status = .noSpeech }
            return .notice(notice)
        }

        try checkpoint(id)
        // The wait for the context runs while the clip is transcribed, so a slow context costs the dictation nothing.
        let resolution = job.context.map { context in
            Task { [sleep] in await context.resolve(deadline: DictationLimits.contextDeadline, sleep: sleep) }
        }
        defer { resolution?.cancel() }
        // The vocabulary needs the context, so a dictation that has one waits for it here, at most `contextDeadline`: it
        // is there already unless the source is slow. A dictation with no vocabulary does not wait.
        let early: ResolvedContext? = if job.vocabulary != nil { await resolution?.value } else { nil }
        let vocabulary = job.vocabulary?.terms(for: early?.context) ?? []
        let input = found.flatMap { SpeechSpan.input(from: clip, result: $0) } ?? clip
        let recognition = try await runner.run(
            input, vocabulary: vocabulary, boostTerms: job.vocabulary?.dictionaryTerms ?? []
        ) { progress in
            if progress == nil { tracker.enter(.transcription) }
            await report(.transcribing(progress: progress))
        }
        try checkpoint(id)
        await attempt.amend {
            $0.rawText = recognition.text
            $0.asrProvider = recognition.provider
            $0.fallbackReason = recognition.fallbackReason
        }
        let resolved = if let early { early } else { await resolution?.value }
        if let resolved {
            diagnostics.record(ContextJob.event(for: resolved))
            await attempt.amend { $0 = resolved.stamped($0) }
            // The field as this dictation begins is a last look at the one before it.
            await corrections?.handoff(resolved.context)
        }
        if recognition.isBlank {
            await attempt.amend { $0.status = .noSpeech }
            return .notice(.noSpeech)
        }
        if case .command(let selection) = job.intent {
            return try await runCommand(
                instruction: recognition.text, selection: selection, job: job, attempt: attempt, tracker: tracker,
                report: report)
        }

        try checkpoint(id)
        let text = try await polished(
            recognition.text, context: resolved, vocabulary: vocabulary, attempt: attempt, tracker: tracker,
            report: report)

        tracker.enter(.insertion)
        try await job.waitForKeyRelease?()
        try checkpoint(id)
        let inserter = inserter
        let target = job.target
        let outcome = try await withDeadline(DictationLimits.insertionTimeout, stage: .insertion, sleep: sleep) {
            await inserter.insert(text, into: target)
        }
        await attempt.amend {
            $0.status = .succeeded
            $0.finalText = text
            $0.delivery = DictationDelivery(outcome)
        }
        switch outcome {
        case .inserted:
            await watchForCorrections(of: text, id: id, context: resolved, target: target)
            return .inserted
        case .copiedToClipboard(let reason): return .notice(.copiedToClipboard(reason))
        case .notInserted(let reason): return .error(.notInserted(reason))
        }
    }

    /// The text to insert: the transcript after cleanup, shaped for the cursor, or the transcript itself when there is no
    /// cleanup stage. The record keeps what the cleanup did: the cleaned text, the cleaner, and why it fell back. The
    /// stage never fails except to say the dictation was cancelled, so nothing is inserted.
    private func polished(
        _ raw: String, context: ResolvedContext?, vocabulary: [String], attempt: Attempt, tracker: StageTracker,
        report: @escaping @Sendable (PipelineState) async -> Void
    ) async throws -> String {
        guard let cleanup else { return raw }
        tracker.enter(.cleanup)
        let input = CleanupInput(
            transcript: raw, style: context?.style ?? Self.unknownStyle, vocabulary: vocabulary,
            cursor: context.flatMap { Self.cursor(in: $0.context) })
        let result = try await cleanup.run(input, willClean: { await report(.polishing) })
        await attempt.amend {
            $0.cleanedText = result.cleaned
            $0.cleanerProvider = result.provider?.rawValue
            // A cleanup fallback is the newest reason; an ASR fallback stays when the cleanup had none.
            if let reason = result.fallbackReason { $0.fallbackReason = reason.rawValue }
        }
        return result.finalText
    }

    /// Applies the instruction to the selection. The record keeps what happened, and nothing of the selection or the
    /// result.
    private func runCommand(
        instruction: String, selection: String, job: DictationJob, attempt: Attempt, tracker: StageTracker,
        report: @escaping @Sendable (PipelineState) async -> Void
    ) async throws -> PipelineState {
        let id = job.recording.id.rawValue
        try checkpoint(id)
        guard let command else {
            await attempt.amend {
                $0.status = .failed
                $0.failure = CommandStage.noResultFailure
            }
            return .notice(.command(.noResult))
        }
        tracker.enter(.cleanup)
        try await job.waitForKeyRelease?()
        let outcome = try await command.run(
            instruction: instruction, selection: selection, target: job.target, inserter: inserter, sleep: sleep,
            checkpoint: { try checkpoint(id) }, report: report)
        await attempt.amend {
            $0.status = outcome.status
            $0.delivery = outcome.delivery
            if let reason = outcome.reason {
                $0.fallbackReason = reason
                $0.failure = CommandStage.noResultFailure
            }
        }
        return outcome.state
    }

    /// Hands a pasted dictation to the correction watch. A dictation without a context is not watched: nothing says its
    /// field is not a secure one.
    private func watchForCorrections(
        of text: String, id: UUID, context: ResolvedContext?, target: AppIdentity?
    ) async {
        guard let corrections, let context, let app = target ?? context.context.app else { return }
        await corrections.watch(InsertionReceipt(id: id, finalText: text, context: context, target: app))
    }

    /// The style of a dictation whose context did not arrive: an unknown app, which the neutral tone suits.
    private static let unknownStyle = StyleProfile(category: .other, tone: .neutral, source: .default)

    /// The text around the cursor, or nil when none of it could be read. A secure field gives none. A field with nothing
    /// before or after the cursor reads the same as one that could not be read, and the text is left as it is for both.
    private static func cursor(in context: DictationContext) -> CursorContext? {
        guard !context.isSecureField, !(context.beforeCursor.isEmpty && context.afterCursor.isEmpty) else { return nil }
        return CursorContext(before: context.beforeCursor, after: context.afterCursor)
    }

    /// The speech in the clip, or nil when the detector could not tell.
    private func detectSpeech(in clip: AudioClip) async -> VADResult? {
        do {
            return try await detector.analyze(clip)
        } catch {
            diagnostics.record(.voiceDetectionFailed)
            return nil
        }
    }

    /// Ends the attempt here if it was cancelled, or if the app is shutting down.
    private func checkpoint(_ id: UUID) throws {
        if cancelRequests.contains(id) { throw CancellationError() }
        try Task.checkCancellation()
    }

    private static func pipelineError(from error: any Error) -> PipelineError {
        error as? PipelineError ?? .recognitionFailed(String(describing: error))
    }
}

// MARK: Support

/// The attempts the user cancelled.
private final class CancelRequests: Sendable {
    private let ids = Mutex<Set<UUID>>([])

    func add(_ id: UUID) { ids.withLock { _ = $0.insert(id) } }
    func contains(_ id: UUID) -> Bool { ids.withLock { $0.contains(id) } }
}

/// The stage an attempt is in, for the error of a total limit that runs out.
private final class StageTracker: Sendable {
    private struct State {
        var stage = PipelineError.Stage.readiness
        var capRanOut = false
    }

    private let state = Mutex(State())

    var capRanOut: Bool { state.withLock { $0.capRanOut } }

    func enter(_ stage: PipelineError.Stage) { state.withLock { $0.stage = stage } }

    /// Called when the total limit runs out, and only then.
    func stageAtCapExpiry() -> PipelineError.Stage {
        state.withLock { state in
            state.capRanOut = true
            return state.stage
        }
    }
}

/// The history record of one attempt. Writing it is best effort: a history that cannot be written must not lose the
/// dictation, so a failure is logged and the attempt goes on without records.
private actor Attempt {
    private var record: DictationRecord
    private var isStored: Bool
    private let history: any HistoryRepository
    private let diagnostics: any DiagnosticsLog

    private init(
        record: DictationRecord, isStored: Bool, history: any HistoryRepository, diagnostics: any DiagnosticsLog
    ) {
        self.record = record
        self.isStored = isStored
        self.history = history
        self.diagnostics = diagnostics
    }

    /// Creates the record, before anything reads the audio.
    static func begin(
        for recording: VerifiedRecording, status: DictationStatus, kind: DictationKind, history: any HistoryRepository,
        dates: any DateSource, diagnostics: any DiagnosticsLog
    ) async -> Attempt {
        let record = DictationRecord(
            id: recording.id.rawValue, createdAt: dates.now(), duration: recording.duration, status: status,
            audioURL: recording.url, kind: kind)
        var stored = true
        do {
            try await history.insert(record)
        } catch {
            stored = false
            diagnostics.record(.historyWriteFailed(step: "insert"))
        }
        return Attempt(record: record, isStored: stored, history: history, diagnostics: diagnostics)
    }

    func amend(_ change: (inout DictationRecord) -> Void) async {
        change(&record)
        guard isStored else { return }
        do {
            try await history.update(record)
        } catch {
            diagnostics.record(.historyWriteFailed(step: "update"))
        }
    }
}
