import Domain
import Foundation
import Synchronization

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

    public init(
        recording: VerifiedRecording, waitForKeyRelease: (@Sendable () async throws -> Void)? = nil,
        target: AppIdentity? = nil
    ) {
        self.init(recording: recording, waitForKeyRelease: waitForKeyRelease, target: target, context: nil)
    }

    init(
        recording: VerifiedRecording, waitForKeyRelease: (@Sendable () async throws -> Void)?, target: AppIdentity?,
        context: ContextJob?
    ) {
        self.recording = recording
        self.waitForKeyRelease = waitForKeyRelease
        self.target = target
        self.context = context
    }
}

/// Everything that happens to a recording after it is on disk, in order:
///
/// 1. a history record is created, as `processing`, with the audio reference, before anything reads the audio;
/// 2. voice activity detection runs on the stored file: no speech, and a muted microphone, end the attempt there;
/// 3. the recognizer transcribes the speech span, waiting for a model that is still loading; a blank transcript ends the
///    attempt as no speech. Meanwhile the context captured at key-down is waited for, briefly, and the style is chosen;
///    the record keeps the app, the page host and the style, never the text of the context;
/// 4. the text goes to the inserter, once the key of a capped hold is up;
/// 5. the record is updated with the outcome.
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
    private let dates: any DateSource
    private let diagnostics: any DiagnosticsLog
    private let sleep: @Sendable (Duration) async throws -> Void
    private let cancelRequests = CancelRequests()

    public init(
        recordings: any AudioRecordingStore,
        history: any HistoryRepository,
        detector: any VoiceActivityDetector,
        runner: RecognitionRunner,
        inserter: any TextInserter,
        dates: any DateSource = SystemDateSource(),
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.recordings = recordings
        self.history = history
        self.detector = detector
        self.runner = runner
        self.inserter = inserter
        self.dates = dates
        self.diagnostics = diagnostics
        self.sleep = sleep
    }

    /// Asks for the attempt `id` to end as cancelled at its next stage boundary, with its audio kept and nothing
    /// inserted. Call it before cancelling the task that runs the attempt.
    public func cancel(_ id: UUID) {
        cancelRequests.add(id)
    }

    /// Keeps a recording that the user cancelled while it was still recording: a cancelled record with its audio, and
    /// nothing is transcribed or inserted.
    public func keepCancelled(_ recording: VerifiedRecording) async {
        _ = await Attempt.begin(
            for: recording, status: .cancelled, history: history, dates: dates, diagnostics: diagnostics)
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
        defer { job.context?.cancel() }
        let tracker = StageTracker()
        let attempt = await Attempt.begin(
            for: job.recording, status: .processing, history: history, dates: dates, diagnostics: diagnostics)
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
        let input = found.flatMap { SpeechSpan.input(from: clip, result: $0) } ?? clip
        let recognition = try await runner.run(input) { progress in
            if progress == nil { tracker.enter(.transcription) }
            await report(.transcribing(progress: progress))
        }
        try checkpoint(id)
        await attempt.amend {
            $0.rawText = recognition.text
            $0.asrProvider = recognition.provider
            $0.fallbackReason = recognition.fallbackReason
        }
        if let resolved = await resolution?.value {
            diagnostics.record(ContextJob.event(for: resolved))
            await attempt.amend { $0 = resolved.stamped($0) }
        }
        if recognition.isBlank {
            await attempt.amend { $0.status = .noSpeech }
            return .notice(.noSpeech)
        }

        tracker.enter(.insertion)
        try await job.waitForKeyRelease?()
        try checkpoint(id)
        let text = recognition.text
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
        case .inserted: return .inserted
        case .copiedToClipboard(let reason): return .notice(.copiedToClipboard(reason))
        case .notInserted(let reason): return .error(.notInserted(reason))
        }
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
        for recording: VerifiedRecording, status: DictationStatus, history: any HistoryRepository,
        dates: any DateSource, diagnostics: any DiagnosticsLog
    ) async -> Attempt {
        let record = DictationRecord(
            id: recording.id.rawValue, createdAt: dates.now(), duration: recording.duration, status: status,
            audioURL: recording.url)
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
