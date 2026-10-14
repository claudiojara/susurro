import Domain
import Foundation

/// Runs hold-to-talk dictations: key down records, key up finishes the recording, and a `ProcessingQueue` takes it from
/// there, one recording at a time and in the order they were spoken. A new recording may start while an earlier one is
/// still being processed, so speech is never lost; at most one recording is active at once.
///
/// The recording is written to disk as it is captured (`RecordingSession`) and goes on only once the file has been read
/// back. A hold that runs into the recording cap, or a device that goes away mid-recording, is queued at once, and its
/// text waits for the release of the key before it goes in. What happens to a recording after that, from the history
/// record to the inserted text, is the `DictationPipeline`.
///
/// Every wait is bounded, so the coordinator always returns to idle.
public actor DictationCoordinator {
    private enum Phase {
        case idle
        case starting  // preconditions are being checked and the capture is starting
        case capturing
        case finishing  // capture is being stopped and drained
        case stopped  // after shutdown()
    }

    private enum FinishReason: Equatable {
        case released(heldFor: Duration)
        case capReached
        case deviceRemoved
        case cancelled
    }

    private let hotkeys: any HotkeySource
    private let capture: any AudioCaptureSource
    private let recordings: any AudioRecordingStore
    private let recognizers: RecognizerRegistry
    private let pipeline: DictationPipeline
    private let permissions: any PermissionsChecker
    private let recordingCap: Duration
    private let diagnostics: any DiagnosticsLog
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The current state first, then every change. It has a single consumer, which sees every state since creation.
    public nonisolated let states: AsyncStream<PipelineState>

    /// Whether a dictation is under way: a recording is being made, or one is queued or being processed. It starts
    /// `false` and yields at each change, so Esc can be armed exactly while it is `true`. It has a single consumer.
    public nonisolated let activity: AsyncStream<Bool>

    private var phase = Phase.idle
    private var published = PipelineState.idle
    private let continuation: AsyncStream<PipelineState>.Continuation
    private let activityContinuation: AsyncStream<Bool>.Continuation
    private var isActive = false
    private var pressedAt = Duration.zero
    /// Whether the key of the dictation that began last is still down.
    private var keyIsDown = false
    /// Ends when that key comes up, for the text that waits for it.
    private var keyUps: AsyncStream<Void>
    private var keyUp: AsyncStream<Void>.Continuation
    private var pendingRelease: Duration?
    /// The recording in progress, from the moment its capture starts until it is finished or abandoned.
    private var session: RecordingSession?
    private var sessionEvents: Task<Void, Never>?
    /// What the recording in progress shows: `starting` or `recording`. It wins over the state of a job.
    private var recordingState: PipelineState?
    private let queue = ProcessingQueue()
    /// The jobs that are queued or running, oldest first.
    private var jobs: [UUID] = []
    /// The recordings of the jobs that have not started, so that a cancelled one still gets its record.
    private var unstarted: [UUID: VerifiedRecording] = [:]
    /// The load progress of the model while the running job waits for it.
    private var jobProgress: Double?
    /// The one shutdown, so that every caller waits for the same work.
    private var shutdownTask: Task<Void, Never>?

    /// - Parameters:
    ///   - recognizers: Where the recognizer of each dictation comes from. A press checks the selected one.
    ///   - pipeline: What happens to each recording once it is on disk.
    ///   - recordingCap: How long a recording may run before it is finished for the user.
    ///   - diagnostics: Where failures that would otherwise be swallowed are reported. They carry no text.
    ///   - sleep: Paces readiness checks and times out the waits. Tests pass a fake.
    public init(
        hotkeys: any HotkeySource,
        capture: any AudioCaptureSource,
        recordings: any AudioRecordingStore,
        recognizers: RecognizerRegistry,
        pipeline: DictationPipeline,
        permissions: any PermissionsChecker,
        recordingCap: Duration = DictationLimits.recordingCap,
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.hotkeys = hotkeys
        self.capture = capture
        self.recordings = recordings
        self.recognizers = recognizers
        self.pipeline = pipeline
        self.permissions = permissions
        self.recordingCap = recordingCap
        self.diagnostics = diagnostics
        self.sleep = sleep
        (states, continuation) = AsyncStream.makeStream()
        (activity, activityContinuation) = AsyncStream.makeStream()
        (keyUps, keyUp) = AsyncStream.makeStream()
        continuation.yield(.idle)
        activityContinuation.yield(false)
    }

    /// Feeds hotkey events to `handle` until the source finishes or the task is cancelled, then shuts down.
    public func run() async {
        for await event in hotkeys.events() {
            await handle(event)
        }
        await shutdown()
    }

    /// Stops any recording, abandons every dictation in progress without inserting it, waits (for a limited time) for the
    /// inserter to finish what it has in hand, and ends `states`. Ignores later events. Every caller waits for the same
    /// shutdown, which runs in a task of its own, so it stops the capture even when the calling task is cancelled.
    public func shutdown() async {
        if shutdownTask == nil {
            let wasRecording = phase == .capturing || phase == .finishing
            phase = .stopped
            sessionEvents?.cancel()
            shutdownTask = Task { await self.finishShutdown(wasRecording: wasRecording) }
        }
        await shutdownTask?.value
    }

    private func finishShutdown(wasRecording: Bool) async {
        if wasRecording { await abandonRecording() }
        await queue.cancelAll()
        await queue.drain()
        sessionEvents = nil
        await drainInserter()
        publish(.idle)
        continuation.finish()
        activityContinuation.finish()
    }

    /// Gives the inserter the time to put the clipboard back. What a slow one leaves is put back as the app terminates.
    private func drainInserter() async {
        do {
            try await withDeadline(DictationLimits.drainTimeout, stage: .insertion, sleep: sleep) { [pipeline] in
                await pipeline.drainInserter()
            }
        } catch {
            diagnostics.record(.shutdownDrainAbandoned)
        }
    }

    /// Applies one hotkey event. Events must arrive one at a time, as `run()` delivers them. The call returns once
    /// the event is applied, before any transcription it starts has finished.
    public func handle(_ event: HotkeyEvent) async {
        switch event {
        case .down(let time): await pressed(at: time)
        case .up(let time): await released(at: time)
        }
    }

    /// Cancels the newest dictation, as Esc does. A recording is stopped and kept as a cancelled record with its audio,
    /// and nothing is transcribed or inserted. A dictation that is being processed ends cancelled at its next stage, with
    /// its audio kept, and whatever it returns later is dropped. With neither, it does nothing.
    public func cancel() async {
        switch phase {
        case .capturing:
            await beginFinishing(reason: .cancelled)?.value
        case .idle, .finishing:
            guard let newest = jobs.last else { return }
            pipeline.cancel(newest)
            if let waiting = unstarted.removeValue(forKey: newest) {
                // It never started, so the pipeline has not made its record: the audio is kept as a cancelled one.
                jobs.removeAll { $0 == newest }
                await queue.cancel(newest)
                await pipeline.keepCancelled(waiting)
                publish(restingState())
            } else {
                await queue.cancel(newest)
            }
        case .starting, .stopped:
            return
        }
    }

    private func pressed(at time: Duration) async {
        // A press while a recording is under way is the same hold; one while a dictation is processed starts the next.
        guard phase == .idle else { return }
        phase = .starting
        pressedAt = time
        pendingRelease = nil
        keyIsDown = true
        // The key of an earlier hold that never came up is taken as released, so its text does not wait for it.
        keyUp.finish()
        (keyUps, keyUp) = AsyncStream.makeStream()
        do {
            try await checkStartPreconditions()
            guard phase == .starting else { return }  // shut down meanwhile
            show(recording: .starting)
            let started = try await startRecording()
            guard phase == .starting else { return await abandon(started) }  // shut down meanwhile
            session = started
            phase = .capturing
            sessionEvents = Task { await self.consume(started.events) }
            if let release = pendingRelease { await released(at: release) }
        } catch {
            settle(.error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)))
        }
    }

    /// Starts the recording within its limit. One that has not started in time is told to stop, in case it starts late
    /// and would otherwise keep the microphone open for nobody.
    private func startRecording() async throws -> RecordingSession {
        let started = RecordingSession(
            capture: capture, store: recordings, maximumDuration: recordingCap,
            diagnostics: diagnostics)
        do {
            try await withDeadline(DictationLimits.captureStartTimeout, stage: .capture, sleep: sleep) {
                try await started.start()
            }
        } catch PipelineError.timedOut(.capture) {
            await abandon(started)
            throw PipelineError.timedOut(.capture)
        } catch RecordingFailure.persistence {
            throw PipelineError.persistenceFailed("the recording could not be opened")
        }
        return started
    }

    private func released(at time: Duration) async {
        keyIsDown = false
        keyUp.finish()
        switch phase {
        case .starting:
            pendingRelease = time  // honored as soon as the capture has started
        case .capturing:
            await beginFinishing(reason: .released(heldFor: time - pressedAt))?.value
        default:
            return
        }
    }

    private func checkStartPreconditions() async throws {
        let permissions = permissions
        let microphone: PermissionStatus
        do {
            microphone = try await withDeadline(DictationLimits.statusTimeout, stage: .capture, sleep: sleep) {
                await permissions.status(.microphone)
            }
        } catch PipelineError.timedOut {
            throw PipelineError.captureFailed("the microphone permission did not answer")
        }
        guard microphone == .granted else { throw PipelineError.microphoneNotGranted }

        let recognizer = recognizers.selected()
        if let blocker = recognizers.blocker(of: recognizer) { throw PipelineError.providerNotUsable(blocker) }
        var readiness = try await readiness(of: recognizer)
        if readiness == .ready { return }
        if readiness != .notInstalled {
            // A press is the chance to start a load that never started, or to retry one that failed. Preparing is
            // idempotent, so it is asked every time and the recognizer decides. What it says afterward counts, not
            // what it said before.
            try await withDeadline(DictationLimits.prepareTimeout, stage: .readiness, sleep: sleep) {
                await recognizer.prepare()
            }
            readiness = try await self.readiness(of: recognizer)
        }
        switch readiness {
        case .notInstalled: throw PipelineError.recognizerNotInstalled
        case .unavailable(let reason, let retryable):
            throw PipelineError.recognizerUnavailable(reason, retryable: retryable)
        case .loading, .ready: break
        }
    }

    private func readiness(of recognizer: any SpeechRecognizer) async throws -> RecognizerReadiness {
        try await withDeadline(DictationLimits.statusTimeout, stage: .readiness, sleep: sleep) {
            await recognizer.readiness()
        }
    }

    /// Reacts to what the recording reports: the first buffer is the moment recording shows, and the cap or a device
    /// that went away finish it.
    private func consume(_ events: AsyncStream<RecordingSession.Event>) async {
        for await event in events {
            switch event {
            case .ready:
                if phase == .capturing { show(recording: .recording(.hold)) }
            case .level:
                break
            case .limitReached:
                if beginFinishing(reason: .capReached) != nil { diagnostics.record(.recordingCapReached) }
            case .deviceRemoved:
                beginFinishing(reason: .deviceRemoved)
            }
        }
    }

    /// Claims the recording for finishing, so the release and the cap cannot both finish it.
    @discardableResult
    private func beginFinishing(reason: FinishReason) -> Task<Void, Never>? {
        guard phase == .capturing else { return nil }
        phase = .finishing
        return Task { await self.finishRecording(reason) }
    }

    /// Stops the capture, waits for the buffered chunks, and has the recording written out and verified. Then it
    /// discards a hold that was too short, or queues the recording.
    private func finishRecording(_ reason: FinishReason) async {
        guard let recording = session else { return settle() }
        if case .released(let heldFor) = reason, heldFor < DictationLimits.minimumHold {
            await abandon(recording)
            session = nil
            guard phase == .finishing else { return }  // shut down meanwhile
            return settle()
        }
        let result: RecordingResult
        do {
            result = try await withDeadline(DictationLimits.captureStopTimeout, stage: .capture, sleep: sleep) {
                await recording.finish()
            }
        } catch {
            await abandon(recording)
            session = nil
            return settle(.error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)))
        }
        guard phase == .finishing else { return }  // shut down meanwhile
        session = nil
        sessionEvents = nil

        switch result {
        case .tooShort:
            return settle()
        case .failed(.persistence):
            return settle(.error(.persistenceFailed("the recording could not be saved")))
        case .failed(.capture(let message)):
            return settle(.error(.captureFailed(message)))
        case .recorded(let verified, let notice):
            if reason == .cancelled {
                await pipeline.keepCancelled(verified)
                return settle()
            }
            if reason == .capReached { publish(.notice(.capReached)) }
            if let notice { publish(.notice(notice)) }
            // A hold that ended by itself has its key down while its text is ready: the text waits for the release.
            let release: AsyncStream<Void>? =
                if case .released = reason { nil } else if keyIsDown { keyUps } else { nil }
            recordingState = nil
            phase = .idle
            await enqueue(verified, waitingFor: release)
        }
    }

    /// Best effort: a recording whose capture does not stop in time is abandoned. It runs in an unstructured task, so a
    /// caller that is already cancelled still stops the capture. The file it wrote is deleted.
    private func abandonRecording() async {
        let abandoned = session
        session = nil
        if let abandoned { await abandon(abandoned) }
    }

    private func abandon(_ recording: RecordingSession) async {
        await Task {
            do {
                try await withDeadline(DictationLimits.captureStopTimeout, stage: .capture, sleep: sleep) {
                    await recording.abort()
                }
            } catch {
                diagnostics.record(.captureStopAbandoned)
            }
        }.value
    }

    // MARK: Jobs

    /// Queues a finished recording behind the ones before it.
    private func enqueue(_ recording: VerifiedRecording, waitingFor release: AsyncStream<Void>?) async {
        let id = recording.id.rawValue
        jobs.append(id)
        unstarted[id] = recording
        showJob(.transcribing(progress: nil))
        var waitForRelease: (@Sendable () async throws -> Void)?
        if let release { waitForRelease = { try await self.waitForKeyRelease(release) } }
        let job = DictationJob(recording: recording, waitForKeyRelease: waitForRelease)
        await queue.enqueue(id) { await self.run(job) }
    }

    /// The work of one queued job: the pipeline, and what it leaves on the screen.
    private func run(_ job: DictationJob) async -> ProcessingQueue.Outcome {
        unstarted[job.recording.id.rawValue] = nil
        let result = await pipeline.process(job) { state in await self.showJob(state) }
        return finish(job.recording.id.rawValue, with: result)
    }

    private func finish(_ id: UUID, with result: DictationPipeline.Result) -> ProcessingQueue.Outcome {
        jobs.removeAll { $0 == id }
        jobProgress = nil
        guard phase != .stopped else { return .cancelled }
        guard case .finished(let state) = result else {
            publish(restingState())
            return .cancelled
        }
        if case .error(let error) = state { diagnostics.record(.dictationFailed(kind: error.kind)) }
        publish(state)
        publish(restingState())
        switch state {
        case .inserted, .notice(.copiedToClipboard): return .succeeded
        case .notice: return .noSpeech
        default: return .failed
        }
    }

    /// Shows what a job is doing, unless a recording is under way: the recording is what the user is looking at.
    private func showJob(_ state: PipelineState) {
        guard phase != .stopped else { return }
        if case .transcribing(let progress) = state { jobProgress = progress }
        if recordingState == nil { publish(state) }
    }

    /// Holds the text back while the key of a hold that ran into the recording cap is still down. The inserter would
    /// otherwise find the hotkey's modifiers held, give up on the paste, and leave the text on the clipboard. The wait
    /// ends at the release or at `releaseWaitTimeout`, and the text goes in either way. Cancellation ends the wait with
    /// an error, so nothing is inserted.
    private func waitForKeyRelease(_ release: AsyncStream<Void>) async throws {
        do {
            try await withDeadline(DictationLimits.releaseWaitTimeout, stage: .insertion, sleep: sleep) {
                for await _ in release {}
            }
        } catch PipelineError.timedOut {
            diagnostics.record(.releaseWaitExpired)
        }
    }

    // MARK: State

    private static func pipelineError(
        from error: any Error, otherwise make: (String) -> PipelineError
    ) -> PipelineError {
        error as? PipelineError ?? make(String(describing: error))
    }

    /// Tells whether a dictation is under way now, when that has changed. Every change of the phase or of the jobs is
    /// followed by a published state, which is where this is called from.
    private func updateActivity() {
        let active: Bool
        switch phase {
        case .starting, .capturing, .finishing: active = true
        case .idle: active = !jobs.isEmpty
        case .stopped: active = false
        }
        guard active != isActive else { return }
        isActive = active
        activityContinuation.yield(active)
    }

    /// Shows the state of the recording in progress.
    private func show(recording state: PipelineState) {
        recordingState = state
        publish(state)
    }

    /// What shows when nothing is happening to report: the recording in progress, the dictations that are still
    /// processed, or idle.
    private func restingState() -> PipelineState {
        if let recordingState { return recordingState }
        return jobs.isEmpty ? .idle : .transcribing(progress: jobProgress)
    }

    /// Ends a recording cycle that did not become a job: shows the outcome, if any, and returns to what rests.
    private func settle(_ outcome: PipelineState? = nil) {
        guard phase != .stopped else { return }
        recordingState = nil
        phase = .idle
        if let outcome {
            if case .error(let error) = outcome { diagnostics.record(.dictationFailed(kind: error.kind)) }
            publish(outcome)
        }
        publish(restingState())
    }

    private func publish(_ state: PipelineState) {
        updateActivity()
        guard state != published else { return }
        published = state
        continuation.yield(state)
    }
}
