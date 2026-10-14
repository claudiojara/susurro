import Activation
import Domain
import Foundation

/// Runs the dictations the hotkey asks for. The hotkey events go through the `ActivationMachine` reducer, and the
/// coordinator executes the effects it returns: hold to talk (key down records, key up submits the recording), a tap
/// that is discarded, a double tap that records hands-free until the next press, and Esc, which cancels the recording or
/// the newest dictation without inserting anything.
///
/// The recording is written to disk as it is captured (`RecordingSession`) and goes on only once the file has been read
/// back. A submitted recording becomes a job on a `ProcessingQueue`, one at a time and in the order they were spoken; a
/// new recording may start while earlier ones are still processed, so speech is never lost, and at most one recording is
/// active at once. A recording that runs into the cap (the reducer's timer or the session's own limit), or whose device
/// goes away, is submitted at once, and its text waits for the key to come up before it goes in. What happens to a job
/// from there, from the history record to the inserted text, is the `DictationPipeline`.
///
/// As the key goes down the coordinator notes the app in front, which the text is pasted into, and starts capturing the
/// context of the dictation; both travel with the job.
///
/// Every wait is bounded, so the coordinator always returns to idle.
public actor DictationCoordinator {
    private enum Phase {
        case idle
        case starting  // the capture is starting
        case capturing
        case finishing  // capture is being stopped and the recording verified
        case stopped  // after shutdown()
    }

    /// How a recording ends, which the reducer decides.
    private enum RecordingEnd {
        /// The recording is submitted and becomes a job. `cap` says the cap ended it.
        case submit(capped: Bool)
        /// A tap: the recording is thrown away, with no history.
        case discard
        /// Esc: the recording is kept as a cancelled record and is not processed.
        case cancel

        var isJob: Bool {
            if case .submit = self { return true }
            return false
        }
    }

    private let hotkeys: any HotkeySource
    private let capture: any AudioCaptureSource
    private let recordings: any AudioRecordingStore
    private let recognizers: RecognizerRegistry
    private let pipeline: DictationPipeline
    private let permissions: any PermissionsChecker
    private let frontmost: (any FrontmostAppProvider)?
    private let context: ContextPipeline?
    private let recordingCap: Duration
    private let diagnostics: any DiagnosticsLog
    private let sleep: @Sendable (Duration) async throws -> Void
    private let clock: any Clock<Duration>

    /// The current state first, then every change. It has a single consumer, which sees every state since creation.
    public nonisolated let states: AsyncStream<PipelineState>
    /// The input level of the microphone (0...1, see `AudioLevel`) of each buffer that arrives while recording. It keeps
    /// only the newest value that nobody has read, so a slow reader sees the latest level and never a backlog.
    public nonisolated let levels: AsyncStream<Double>
    /// Whether a dictation is under way: a recording is being made, or one is queued or being processed. It starts
    /// `false` and yields at each change. It has a single consumer.
    public nonisolated let activity: AsyncStream<Bool>

    private var phase = Phase.idle
    private var published = PipelineState.idle
    private let continuation: AsyncStream<PipelineState>.Continuation
    private let levelContinuation: AsyncStream<Double>.Continuation
    private let activityContinuation: AsyncStream<Bool>.Continuation
    private var isActive = false
    /// The state of the reducer and the timers it asked for.
    private let machine: ActivationMachine
    private var activation = ActivationMachine.State()
    private var timers = ActivationTimers()
    private var escapeArmed = false
    /// Whether the key of the dictation that began last is still down.
    private var keyIsDown = false
    /// Ends when that key comes up, for the text that waits for it.
    private var keyUps: AsyncStream<Void>
    private var keyUp: AsyncStream<Void>.Continuation
    /// How the recording that is starting or running was started.
    private var recordingMode = RecordingMode.hold
    /// How the recording ends, when the reducer ended it before the capture had started. It is honored as soon as the
    /// capture has started.
    private var pendingEnd: RecordingEnd?
    /// Esc cancelled the recording that was submitted while it was still being finished.
    private var submittedRecordingCancelled = false
    /// The recording in progress, from the moment its capture starts until it is finished or abandoned.
    private var session: RecordingSession?
    private var sessionEvents: Task<Void, Never>?
    /// What the recording in progress shows: `starting` or `recording`. It wins over the state of a job.
    private var recordingState: PipelineState?
    /// The app that was in front when the key of the recording went down, which its text is pasted into and no other.
    private var dictationTarget: AppIdentity?
    /// The capture of the context of the recording under way, started as the key went down.
    private var contextJob: ContextJob?
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
    ///   - frontmost: Tells which app is in front as the key goes down. Without it the text is pasted wherever the focus
    ///     is when the transcript is ready.
    ///   - context: Captures the context of each dictation as the key goes down and chooses its style. Without it no
    ///     context is captured.
    ///   - recordingCap: How long a recording may run before it is finished for the user, by the reducer's timer and by
    ///     the recording's own limit, whichever comes first.
    ///   - diagnostics: Where failures that would otherwise be swallowed are reported. They carry no text.
    ///   - sleep: Paces readiness checks and times out the waits. Tests pass a fake.
    ///   - clock: Runs the timers of the activation machine: the recording cap and the double-tap window. Tests pass a
    ///     `ManualClock`.
    public init(
        hotkeys: any HotkeySource,
        capture: any AudioCaptureSource,
        recordings: any AudioRecordingStore,
        recognizers: RecognizerRegistry,
        pipeline: DictationPipeline,
        permissions: any PermissionsChecker,
        frontmost: (any FrontmostAppProvider)? = nil,
        context: ContextPipeline? = nil,
        recordingCap: Duration = DictationLimits.recordingCap,
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.hotkeys = hotkeys
        self.capture = capture
        self.recordings = recordings
        self.recognizers = recognizers
        self.pipeline = pipeline
        self.permissions = permissions
        self.frontmost = frontmost
        self.context = context
        self.recordingCap = recordingCap
        self.diagnostics = diagnostics
        self.sleep = sleep
        self.clock = clock
        var timing = ActivationMachine.Timing.standard
        timing.cap = recordingCap
        machine = ActivationMachine(timing: timing)
        (states, continuation) = AsyncStream.makeStream()
        (levels, levelContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
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
            timers.cancelAll()
            sessionEvents?.cancel()
            dropContextJob()
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
        setEscapeArmed(false)
        publish(.idle)
        continuation.finish()
        levelContinuation.finish()
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
        guard phase != .stopped else { return }
        switch event {
        case .down(let time): await pressed(at: time)
        case .up(let time): await released(at: time)
        case .escape: await run(.escape)
        }
    }

    /// Cancels the recording, or the newest dictation, as Esc does. A recording is stopped and kept as a cancelled
    /// record with its audio, and nothing is transcribed or inserted. A dictation that is being processed ends cancelled
    /// at its next stage, with its audio kept, and whatever it returns later is dropped. With neither, it does nothing.
    public func cancel() async {
        guard phase != .stopped else { return }
        await run(.escape)
    }

    // MARK: Events

    private func pressed(at time: Duration) async {
        guard activation.startsCaptureOnPress else {
            if activation.acceptsPress { beginKeyPress() }
            return await run(.down(at: time))
        }
        // A press while a recording is still being stopped and verified starts nothing. One while dictations are being
        // processed starts the next recording: they are queued behind each other.
        guard phase == .idle else { return }
        phase = .starting
        pendingEnd = nil
        submittedRecordingCancelled = false
        beginKeyPress()
        let failure = await startFailure()
        guard phase == .starting else { return }  // shut down meanwhile
        await run(.down(at: time, startFailure: failure))
    }

    private func released(at time: Duration) async {
        keyIsDown = false
        keyUp.finish()
        await run(.up(at: time))
    }

    /// The key of a dictation went down. The text that waits for the key waits for this press. The key of an earlier
    /// hold that never came up is taken as released, so its text does not wait for it.
    private func beginKeyPress() {
        keyIsDown = true
        keyUp.finish()
        (keyUps, keyUp) = AsyncStream.makeStream()
    }

    /// Sends the event to the reducer and executes what it asks for, and returns once a recording that the event ended
    /// has finished stopping.
    private func run(_ event: ActivationMachine.Event) async {
        await dispatch(event)?.value
    }

    /// Like `run`, for events that come from inside: the task that stops a recording is left to run, since the caller can
    /// be the very task that it waits for.
    @discardableResult
    private func dispatch(_ event: ActivationMachine.Event) async -> Task<Void, Never>? {
        let transition = machine.reduce(activation, event)
        activation = transition.state
        return await execute(transition.effects)
    }

    // MARK: Effects

    /// Executes the effects in the order the reducer lists them, except that the capture starts last: it can take a
    /// while, and the timers and the Esc registration must be in place by then, since a release can arrive meanwhile.
    /// Returns the task that stops the recording, if the effects end one.
    private func execute(_ effects: [ActivationMachine.Effect]) async -> Task<Void, Never>? {
        var finishing: Task<Void, Never>?
        var starting: RecordingMode?
        for effect in effects {
            switch effect {
            case .armEsc: setEscapeArmed(true)
            case .disarmEsc: setEscapeArmed(false)
            case .startCapture(let mode): starting = mode
            case .captureContext: await beginContextCapture()
            case .scheduleCap(let duration): schedule(.cap, after: duration)
            case .cancelCap: timers.cancel(.cap)
            case .scheduleDoubleTapTimeout(let duration): schedule(.doubleTap, after: duration)
            case .cancelDoubleTapTimeout: timers.cancel(.doubleTap)
            case .finish(let mode): finishing = await endRecording(.submit(capped: mode == .cap))
            case .discardCapture: finishing = await endRecording(.discard)
            case .cancelCapture(let keepAudio): finishing = await endRecording(keepAudio ? .cancel : .discard)
            case .cancelNewestJob: await cancelNewestJob()
            case .notice(let kind): publish(.notice(kind))
            case .showError(let error): await settle(.error(error))
            }
        }
        if let starting { await startRecording(starting) }
        return finishing
    }

    private func schedule(_ kind: ActivationTimers.Kind, after duration: Duration) {
        timers.schedule(kind, after: duration, on: clock) { [self] token in
            await self.timerFired(kind, token: token)
        }
    }

    private func timerFired(_ kind: ActivationTimers.Kind, token: Int) async {
        guard phase != .stopped, timers.complete(kind, token: token) else { return }
        switch kind {
        case .cap: await dispatch(.capReached)
        case .doubleTap: await dispatch(.doubleTapTimeout)
        }
    }

    private func setEscapeArmed(_ armed: Bool) {
        guard armed != escapeArmed else { return }
        escapeArmed = armed
        hotkeys.setEscapeArmed(armed)
    }

    /// The key of a recording went down: notes the app in front, which the text goes to, and starts capturing the
    /// context of the dictation. The capture never delays the recording.
    private func beginContextCapture() async {
        dropContextJob()
        dictationTarget = await frontmost?.current()
        contextJob = context.map { ContextJob(app: dictationTarget, pipeline: $0) }
    }

    private func dropContextJob() {
        contextJob?.cancel()
        contextJob = nil
    }

    // MARK: Start

    /// Checks what the start depends on, and returns why the recording may not start, if it may not.
    private func startFailure() async -> PipelineError? {
        do {
            try await checkStartPreconditions()
            return nil
        } catch {
            return Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)
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

    /// Starts the recording, shows that it is starting, and carries on once it has. An end that the reducer decided
    /// while the capture was starting is honored as soon as it has.
    private func startRecording(_ mode: RecordingMode) async {
        recordingMode = mode
        phase = .starting
        show(recording: .starting)
        do {
            let started = try await startSession()
            guard phase == .starting else { return await abandon(started) }  // shut down meanwhile
            session = started
            phase = .capturing
            sessionEvents = Task { await self.consume(started.events) }
            if let pending = pendingEnd {
                pendingEnd = nil
                await beginEnding(pending)?.value
            }
        } catch {
            await captureCouldNotStart(error)
        }
    }

    /// Starts the recording within its limit. One that has not started in time is told to stop, in case it starts late
    /// and would otherwise keep the microphone open for nobody.
    private func startSession() async throws -> RecordingSession {
        let started = RecordingSession(
            capture: capture, store: recordings, maximumDuration: recordingCap, diagnostics: diagnostics)
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

    /// The recording did not start. The reducer goes back to idle, and an end that was waiting for the start is dropped.
    private func captureCouldNotStart(_ error: any Error) async {
        let dropped = pendingEnd
        pendingEnd = nil
        await dispatch(.captureFailed)
        await settle(
            .error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)),
            endsJob: dropped?.isJob == true)
    }

    // MARK: Recording

    /// Reacts to what the recording reports: the first buffer is the moment recording shows, each buffer moves the
    /// meter, and the cap or a device that went away finish it.
    private func consume(_ events: AsyncStream<RecordingSession.Event>) async {
        for await event in events {
            switch event {
            case .ready:
                if phase == .capturing { show(recording: .recording(recordingMode)) }
            case .level(let rms):
                if phase == .capturing { levelContinuation.yield(AudioLevel.level(rms: Double(rms))) }
            case .limitReached:
                if phase == .capturing { await dispatch(.capReached) }
            case .deviceRemoved:
                await deviceRemoved()
            }
        }
    }

    /// The input device went away: what was captured is submitted, and the reducer is told that the recording is over.
    private func deviceRemoved() async {
        guard phase == .capturing, activation.phase.isRecording else { return }
        countJob()
        await dispatch(.captureFailed)
        beginEnding(.submit(capped: false))
    }

    /// Ends the recording the way the reducer decided. A submission counts as a job for the reducer from now on, so
    /// Esc stays armed for it.
    private func endRecording(_ end: RecordingEnd) async -> Task<Void, Never>? {
        if end.isJob { countJob() }
        switch phase {
        case .starting, .capturing:
            return beginEnding(end)
        case .idle, .finishing, .stopped:
            // Nothing is being captured, so a job that this was to start does not exist.
            if end.isJob { await dispatch(.jobFinished) }
            return nil
        }
    }

    /// Claims the recording for finishing, so that the release and the cap cannot both finish it. While the capture is
    /// still starting the end waits for it. The task that finishes the recording is returned.
    @discardableResult
    private func beginEnding(_ end: RecordingEnd) -> Task<Void, Never>? {
        switch phase {
        case .starting:
            pendingEnd = end
            return nil
        case .capturing:
            if case .submit(capped: true) = end { diagnostics.record(.recordingCapReached) }
            phase = .finishing
            return Task { await self.finishRecording(end) }
        case .idle, .finishing, .stopped:
            return nil
        }
    }

    /// The reducer counts the recordings that were submitted and have not finished.
    private func countJob() {
        activation = machine.reduce(activation, .jobEnqueued).state
    }

    /// Stops the capture, waits for the buffered chunks, and has the recording written out and verified. Then it throws
    /// a tap away, keeps a cancelled recording, or queues a submitted one.
    private func finishRecording(_ end: RecordingEnd) async {
        guard let recording = session else { return await settle(endsJob: end.isJob) }
        if case .discard = end {
            await abandon(recording)
            session = nil
            sessionEvents = nil
            guard phase == .finishing else { return }  // shut down meanwhile
            return await settle()
        }
        let result: RecordingResult
        do {
            result = try await withDeadline(DictationLimits.captureStopTimeout, stage: .capture, sleep: sleep) {
                await recording.finish()
            }
        } catch {
            await abandon(recording)
            session = nil
            return await settle(
                .error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)), endsJob: end.isJob)
        }
        guard phase == .finishing else { return }  // shut down meanwhile
        session = nil
        sessionEvents = nil

        switch result {
        case .tooShort:
            return await settle(endsJob: end.isJob)
        case .failed(.persistence):
            return await settle(.error(.persistenceFailed("the recording could not be saved")), endsJob: end.isJob)
        case .failed(.capture(let message)):
            return await settle(.error(.captureFailed(message)), endsJob: end.isJob)
        case .recorded(let verified, let notice):
            if !end.isJob || submittedRecordingCancelled {
                await pipeline.keepCancelled(verified)
                return await settle(endsJob: end.isJob)
            }
            if let notice { publish(.notice(notice)) }
            // A recording that the key did not end (the cap, a lost device, the press that stops hands-free) has its
            // key down while its text is ready: the text waits for the release.
            let release = keyIsDown ? keyUps : nil
            let target = dictationTarget
            let context = contextJob
            contextJob = nil
            recordingState = nil
            phase = .idle
            await enqueue(verified, waitingFor: release, target: target, context: context)
        }
    }

    /// Best effort: a recording whose capture does not stop in time is abandoned. The file it wrote is deleted.
    private func abandonRecording() async {
        let abandoned = session
        session = nil
        if let abandoned { await abandon(abandoned) }
    }

    /// It runs in an unstructured task, so a caller that is already cancelled still stops the capture.
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
    private func enqueue(
        _ recording: VerifiedRecording, waitingFor release: AsyncStream<Void>?, target: AppIdentity?,
        context: ContextJob?
    ) async {
        let id = recording.id.rawValue
        jobs.append(id)
        unstarted[id] = recording
        showJob(.transcribing(progress: nil))
        var waitForRelease: (@Sendable () async throws -> Void)?
        if let release { waitForRelease = { try await self.waitForKeyRelease(release) } }
        let job = DictationJob(
            recording: recording, waitForKeyRelease: waitForRelease, target: target, context: context)
        await queue.enqueue(id) { await self.run(job) }
    }

    /// Esc cancels the newest dictation: it inserts nothing, whatever stage it is in. A recording that was submitted and
    /// is still being verified is the newest; otherwise it is the newest job on the queue.
    private func cancelNewestJob() async {
        if phase == .finishing || pendingEnd?.isJob == true {
            submittedRecordingCancelled = true
            return
        }
        guard let newest = jobs.last else { return }
        pipeline.cancel(newest)
        if let waiting = unstarted.removeValue(forKey: newest) {
            // It never started, so the pipeline has not made its record: the audio is kept as a cancelled one.
            jobs.removeAll { $0 == newest }
            await queue.cancel(newest)
            await pipeline.keepCancelled(waiting)
            await dispatch(.jobFinished)
            publish(restingState())
        } else {
            await queue.cancel(newest)
        }
    }

    /// The work of one queued job: the pipeline, and what it leaves on the screen.
    private func run(_ job: DictationJob) async -> ProcessingQueue.Outcome {
        unstarted[job.recording.id.rawValue] = nil
        let result = await pipeline.process(job) { state in await self.showJob(state) }
        return await finish(job.recording.id.rawValue, with: result)
    }

    /// Ends a job. The reducer is told first, so that Esc is already released when the resting state shows.
    private func finish(_ id: UUID, with result: DictationPipeline.Result) async -> ProcessingQueue.Outcome {
        jobs.removeAll { $0 == id }
        jobProgress = nil
        guard phase != .stopped else { return .cancelled }
        await dispatch(.jobFinished)
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

    /// Holds the text back while the key that ended the recording without being released is still down. The inserter
    /// would otherwise find the hotkey's modifiers held, give up on the paste, and leave the text on the clipboard. The
    /// wait ends at the release or at `releaseWaitTimeout`, and the text goes in either way. Cancellation ends the wait
    /// with an error, so nothing is inserted.
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

    /// Ends a recording cycle that did not become a job: shows the outcome, if any, and returns to what rests. A cycle
    /// that the reducer counted as a job tells it first, so that Esc is already released when the resting state shows.
    private func settle(_ outcome: PipelineState? = nil, endsJob: Bool = false) async {
        guard phase != .stopped else { return }
        if endsJob { await dispatch(.jobFinished) }
        guard phase != .stopped else { return }
        dropContextJob()
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
