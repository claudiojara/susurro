import Activation
import Domain

/// Runs the dictations the hotkey asks for, one at a time. The hotkey events go through the `ActivationMachine` reducer,
/// and the coordinator executes the effects it returns: hold to talk (key down records, key up transcribes the whole
/// clip and inserts the text), a tap that is discarded, a double tap that records hands-free until the next press, and
/// Esc, which cancels whatever is in flight without inserting anything. A recording that runs into the cap, whether it is
/// the time cap of the machine or the size limit of the clip, is transcribed at once, and its text waits for the key to
/// come up before it goes in. A press while a dictation is processing is ignored and says so with a busy notice, until
/// the processing queue (which lets a new recording start meanwhile) arrives. Every wait is bounded, and so is the whole
/// of the processing, so the coordinator always returns to idle.
public actor DictationCoordinator {
    private enum Phase {
        case idle
        case starting  // the capture is starting
        case capturing
        case finishing  // capture is being stopped and drained
        case processing  // the clip is being transcribed and inserted
        case stopped  // after shutdown()
    }

    /// How a recording ends, which the reducer decides.
    private enum RecordingEnd {
        /// The clip is submitted and becomes a job.
        case submit(ActivationMachine.Effect.FinishMode)
        /// A tap: the clip is thrown away.
        case discard
        /// Esc: the clip is not processed.
        case cancel

        var isJob: Bool {
            if case .submit = self { return true }
            return false
        }
    }

    private static let capSampleCount = Int(DictationLimits.recordingCap / .seconds(1)) * AudioClip.sampleRate

    private let hotkeys: any HotkeySource
    private let capture: any AudioCaptureSource
    private let recognizer: any SpeechRecognizer
    private let inserter: any TextInserter
    private let permissions: any PermissionsChecker
    private let frontmost: (any FrontmostAppProvider)?
    private let context: ContextPipeline?
    private let diagnostics: any DiagnosticsLog
    private let sleep: @Sendable (Duration) async throws -> Void
    private let clock: any Clock<Duration>

    /// The current state first, then every change. It has a single consumer, which sees every state since creation.
    public nonisolated let states: AsyncStream<PipelineState>
    /// The input level of the microphone (0...1, see `AudioLevel`) of each chunk that arrives while recording. It keeps
    /// only the newest value that nobody has read, so a slow reader sees the latest level and never a backlog.
    public nonisolated let levels: AsyncStream<Double>

    private var phase = Phase.idle
    private var published = PipelineState.idle
    private let continuation: AsyncStream<PipelineState>.Continuation
    private let levelContinuation: AsyncStream<Double>.Continuation
    /// The state of the reducer and the timers it asked for.
    private let machine = ActivationMachine()
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
    private var samples: [Float] = []
    private var receivedAudio = false
    private var captureFailure: String?
    private var captureTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    /// The app that was in front when the key of the recording went down, which its text is pasted into and no other.
    private var dictationTarget: AppIdentity?
    /// The capture of the context of the recording under way, started as the key went down.
    private var contextJob: ContextJob?
    /// The number of the newest job, and the number of the one Esc cancelled last. A job checks its own number, so a job
    /// that was cancelled stays cancelled however late its work returns.
    private var jobSerial = 0
    private var cancelledSerial = 0
    /// The stage of the dictation being processed, which a cap that runs out names in its error.
    private var processingStage = PipelineError.Stage.readiness
    /// Whether the total cap ran out on the dictation being processed, as opposed to the limit of one of its stages.
    private var processingCapRanOut = false
    /// The one shutdown, so that every caller waits for the same work.
    private var shutdownTask: Task<Void, Never>?

    /// - Parameters:
    ///   - frontmost: Tells which app is in front as the key goes down. Without it the text is pasted wherever the focus
    ///     is when the transcript is ready.
    ///   - context: Captures the context of each dictation as the key goes down and chooses its style. Without it no
    ///     context is captured.
    ///   - diagnostics: Where failures that would otherwise be swallowed are reported. They carry no text.
    ///   - sleep: Paces readiness checks and times out the waits. Tests pass a fake.
    ///   - clock: Runs the timers of the activation machine: the recording cap and the double-tap window. Tests pass a
    ///     `ManualClock`.
    public init(
        hotkeys: any HotkeySource,
        capture: any AudioCaptureSource,
        recognizer: any SpeechRecognizer,
        inserter: any TextInserter,
        permissions: any PermissionsChecker,
        frontmost: (any FrontmostAppProvider)? = nil,
        context: ContextPipeline? = nil,
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.hotkeys = hotkeys
        self.capture = capture
        self.recognizer = recognizer
        self.inserter = inserter
        self.permissions = permissions
        self.frontmost = frontmost
        self.context = context
        self.diagnostics = diagnostics
        self.sleep = sleep
        self.clock = clock
        (states, continuation) = AsyncStream.makeStream()
        (levels, levelContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (keyUps, keyUp) = AsyncStream.makeStream()
        continuation.yield(.idle)
    }

    /// Feeds hotkey events to `handle` until the source finishes or the task is cancelled, then shuts down.
    public func run() async {
        for await event in hotkeys.events() {
            await handle(event)
        }
        await shutdown()
    }

    /// Stops any recording, abandons any dictation in progress without inserting it, waits (for a limited time) for the
    /// inserter to finish what it has in hand, and ends `states`. Ignores later events. Every caller waits for the same
    /// shutdown, which runs in a task of its own, so it stops the capture even when the calling task is cancelled.
    public func shutdown() async {
        if shutdownTask == nil {
            let wasRecording = phase == .capturing || phase == .finishing
            let processing = processTask
            phase = .stopped
            timers.cancelAll()
            captureTask?.cancel()
            processing?.cancel()
            dropContextJob()
            samples = []
            shutdownTask = Task { await self.finishShutdown(wasRecording: wasRecording, processing: processing) }
        }
        await shutdownTask?.value
    }

    private func finishShutdown(wasRecording: Bool, processing: Task<Void, Never>?) async {
        if wasRecording { await abandonCapture() }
        await processing?.value
        captureTask = nil
        processTask = nil
        await drainInserter()
        setEscapeArmed(false)
        publish(.idle)
        continuation.finish()
        levelContinuation.finish()
    }

    /// Gives the inserter the time to put the clipboard back. What a slow one leaves is put back as the app terminates.
    private func drainInserter() async {
        do {
            try await withDeadline(DictationLimits.drainTimeout, stage: .insertion, sleep: sleep) { [inserter] in
                await inserter.drain()
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

    // MARK: Events

    private func pressed(at time: Duration) async {
        guard activation.startsCaptureOnPress else {
            if activation.acceptsPress { beginKeyPress() }
            return await run(.down(at: time))
        }
        guard phase == .idle else { return reportBusyIfProcessing() }
        phase = .starting
        pendingEnd = nil
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

    /// The key of a dictation went down. The text that waits for the key waits for this press.
    private func beginKeyPress() {
        keyIsDown = true
        (keyUps, keyUp) = AsyncStream.makeStream()
    }

    /// A press that finds the last dictation still being processed gets no recording, so it says so. The state that was
    /// showing comes right back: the dictation carries on unchanged.
    private func reportBusyIfProcessing() {
        guard phase == .processing else { return }
        let showing = published
        publish(.notice(.busy))
        publish(showing)
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
            case .finish(let mode): finishing = await endRecording(.submit(mode))
            case .discardCapture: finishing = await endRecording(.discard)
            case .cancelCapture: finishing = await endRecording(.cancel)
            case .cancelNewestJob: cancelNewestJob()
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

    /// Reads what the start depends on and asks the rule whether the recording may start. The recognizer is asked to
    /// prepare when it is not ready, which starts a load that never started and retries one that failed; what it says
    /// afterward counts, not what it said before.
    private func startFailure() async -> PipelineError? {
        do {
            let microphone = await permissions.status(.microphone)
            var readiness = RecognizerReadiness.ready
            if microphone == .granted {
                readiness = await recognizer.readiness()
                if readiness != .ready, readiness != .notInstalled {
                    try await withDeadline(DictationLimits.prepareTimeout, stage: .readiness, sleep: sleep) {
                        [recognizer] in
                        await recognizer.prepare()
                    }
                    readiness = await recognizer.readiness()
                }
            }
            return StartPreconditions.evaluate(microphone: microphone, recognizer: readiness)
        } catch {
            return Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)
        }
    }

    /// Starts the capture, shows that it is starting, and carries on to the recording once it has. A press that ended
    /// while the capture was starting is honored as soon as it has.
    private func startRecording(_ mode: RecordingMode) async {
        recordingMode = mode
        publish(.starting)
        do {
            let stream = try await startCapture()
            guard phase == .starting else { return await abandonCapture() }  // shut down meanwhile
            samples = []
            receivedAudio = false
            captureFailure = nil
            phase = .capturing
            captureTask = Task { await self.consume(stream) }
            if let pending = pendingEnd {
                pendingEnd = nil
                await endRecording(pending)?.value
            }
        } catch {
            await captureCouldNotStart(error)
        }
    }

    /// The recording did not start. The reducer goes back to idle, and an end that was waiting for the start is dropped.
    private func captureCouldNotStart(_ error: any Error) async {
        let dropped = pendingEnd
        pendingEnd = nil
        await dispatch(.captureFailed)
        if dropped?.isJob == true { await dispatch(.jobFinished) }
        await settle(.error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)))
    }

    /// Starts the capture within its limit. One that has not started in time is told to stop, in case it starts late
    /// and would otherwise keep the microphone open for nobody.
    private func startCapture() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        do {
            return try await withDeadline(DictationLimits.captureStartTimeout, stage: .capture, sleep: sleep) {
                [capture] in
                try await capture.start()
            }
        } catch PipelineError.timedOut(.capture) {
            await abandonCapture()
            throw PipelineError.timedOut(.capture)
        }
    }

    // MARK: Recording

    private func consume(_ stream: AsyncThrowingStream<AudioChunk, Error>) async {
        do {
            for try await chunk in stream { await receive(chunk) }
        } catch {
            // The samples captured so far stay in the clip. If none arrived, the release reports this failure.
            captureFailure = String(describing: error)
            diagnostics.record(.captureStreamFailed(errorType: String(describing: type(of: error))))
        }
    }

    private func receive(_ chunk: AudioChunk) async {
        if !receivedAudio, phase == .capturing {
            receivedAudio = true
            publish(.recording(recordingMode))
        }
        samples.append(contentsOf: chunk.samples)
        if phase == .capturing { levelContinuation.yield(AudioLevel.level(of: chunk.samples)) }
        if samples.count >= Self.capSampleCount, phase == .capturing {
            await dispatch(.capReached)
        }
    }

    /// Ends the recording the way the reducer decided. While the capture is still starting the end waits for it. The
    /// task that stops the capture is returned, so that a caller that can wait for it does.
    private func endRecording(_ end: RecordingEnd) async -> Task<Void, Never>? {
        let serial = end.isJob ? newJob() : jobSerial
        switch phase {
        case .starting:
            pendingEnd = end
            return nil
        case .capturing:
            if case .submit(.cap) = end { diagnostics.record(.recordingCapReached) }
            phase = .finishing
            return Task { await self.finishRecording(end, serial: serial) }
        case .idle, .finishing, .processing, .stopped:
            // Nothing is being captured, so a job that this was to start does not exist.
            if end.isJob { await dispatch(.jobFinished) }
            return nil
        }
    }

    /// A recording was submitted: a job is in flight from now on.
    private func newJob() -> Int {
        jobSerial += 1
        activation = machine.reduce(activation, .jobEnqueued).state
        return jobSerial
    }

    /// Stops capture, waits for the buffered chunks, then throws the clip away or starts processing it.
    private func finishRecording(_ end: RecordingEnd, serial: Int) async {
        do {
            try await withDeadline(DictationLimits.captureStopTimeout, stage: .capture, sleep: sleep) {
                [capture, captureTask] in
                await capture.stop()
                await captureTask?.value
            }
        } catch {
            captureTask?.cancel()
            return await settle(
                .error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)), endsJob: end.isJob)
        }
        guard phase == .finishing else { return }  // shut down meanwhile
        captureTask = nil
        let clip = AudioClip(samples: samples)
        samples = []

        switch end {
        case .discard, .cancel:
            return await settle()
        case .submit:
            guard cancelledSerial != serial else { return await settle(endsJob: true) }
            guard !clip.samples.isEmpty else {
                return await settle(.error(.captureFailed(captureFailure ?? "no audio was captured")), endsJob: true)
            }
        }
        phase = .processing
        publish(.transcribing(progress: nil))
        // The job takes the context and the target of its recording with it.
        let job = Job(clip: clip, serial: serial, target: dictationTarget, context: contextJob)
        contextJob = nil
        processTask = Task { await self.process(job) }
    }

    /// One submitted recording on its way to the app it was dictated in.
    private struct Job: Sendable {
        let clip: AudioClip
        let serial: Int
        /// The app that was in front as the key went down.
        let target: AppIdentity?
        /// The capture of the context that began as the key went down.
        let context: ContextJob?
    }

    /// Esc cancels the newest job: it inserts nothing, whatever stage it is in. Its processing ends quietly and the job
    /// finishes as any other.
    private func cancelNewestJob() {
        cancelledSerial = jobSerial
        processTask?.cancel()
    }

    /// Best effort: a capture that does not stop in time is abandoned. It runs in an unstructured task, so a caller
    /// that is already cancelled still stops the capture.
    private func abandonCapture() async {
        await Task {
            do {
                try await withDeadline(DictationLimits.captureStopTimeout, stage: .capture, sleep: sleep) {
                    [capture] in
                    await capture.stop()
                }
            } catch {
                diagnostics.record(.captureStopAbandoned)
            }
        }.value
    }

    // MARK: Processing

    /// Runs the processing of one clip inside the total cap. The work returns the state to end on and does not settle
    /// the cycle itself, so work that the cap abandons cannot settle it after the cap has.
    private func process(_ job: Job) async {
        let serial = job.serial
        defer { job.context?.cancel() }
        processingStage = .readiness
        processingCapRanOut = false
        do {
            let outcome = try await withDeadline(
                DictationLimits.processingCap, stageAtExpiry: { await self.capRanOut() }, sleep: sleep
            ) {
                try await self.transcribeAndInsert(job)
            }
            await settle(outcome, endsJob: true)
        } catch {
            // The user cancelled it: there is nothing to show.
            if cancelledSerial == serial { return await settle(endsJob: true) }
            // The error alone cannot say which limit ended the dictation: the cap and a stage name the same stage.
            if processingCapRanOut { diagnostics.record(.processingCapReached) }
            await settle(
                .error(Self.pipelineError(from: error, otherwise: PipelineError.recognitionFailed)), endsJob: true)
        }
    }

    /// Called when the total cap runs out, and only then. Returns the stage the cap interrupted.
    private func capRanOut() -> PipelineError.Stage {
        processingCapRanOut = true
        return processingStage
    }

    private func transcribeAndInsert(_ job: Job) async throws -> PipelineState {
        let serial = job.serial
        // The wait for the context runs while the clip is transcribed, so a slow context costs the dictation nothing.
        let resolution = startContextResolution(job.context)
        defer { resolution?.cancel() }
        try await waitUntilRecognizerIsReady()
        processingStage = .transcription
        let transcript = try await withDeadline(
            DictationLimits.transcriptionTimeout, stage: .transcription, sleep: sleep
        ) { [recognizer, clip = job.clip] in
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
        // A job that Esc cancelled inserts nothing, even if the recognizer returned the text meanwhile.
        guard cancelledSerial != serial else { throw CancellationError() }
        guard !transcript.text.allSatisfy(\.isWhitespace) else { return .notice(.noSpeech) }
        if let resolved = await resolution?.value { diagnostics.record(ContextJob.event(for: resolved)) }
        processingStage = .insertion
        try await waitForKeyRelease()
        guard cancelledSerial != serial else { throw CancellationError() }
        let outcome = try await withDeadline(DictationLimits.insertionTimeout, stage: .insertion, sleep: sleep) {
            [inserter, target = job.target] in
            await inserter.insert(transcript.text, into: target)
        }
        switch outcome {
        case .inserted: return .inserted
        case .copiedToClipboard(let reason): return .notice(.copiedToClipboard(reason))
        case .notInserted(let reason): return .error(.notInserted(reason))
        }
    }

    /// Starts waiting for the context of the dictation, at most `contextDeadline`, and then chooses its style.
    private func startContextResolution(_ job: ContextJob?) -> Task<ResolvedContext?, Never>? {
        guard let job else { return nil }
        let sleep = sleep
        return Task { await job.resolve(deadline: DictationLimits.contextDeadline, sleep: sleep) }
    }

    /// Holds the text back while the key of a hold that ran into the recording cap is still down. The inserter would
    /// otherwise find the hotkey's modifiers held, give up on the paste, and leave the text on the clipboard. The wait
    /// ends at the release or at `releaseWaitTimeout`, and the text goes in either way. A hold that ended with the
    /// release finds the key up and does not wait. Cancellation ends the wait with an error, so nothing is inserted.
    private func waitForKeyRelease() async throws {
        guard keyIsDown else { return }
        do {
            try await withDeadline(DictationLimits.releaseWaitTimeout, stage: .insertion, sleep: sleep) { [keyUps] in
                for await _ in keyUps {}
            }
        } catch PipelineError.timedOut {
            diagnostics.record(.releaseWaitExpired)
        }
    }

    /// Waits for a loading model while the finished clip stays in memory. The wait ends when the model is ready, when it
    /// fails, when its progress has not changed for `readinessStallTimeout`, or at `readinessHardCap`. A clip that waits
    /// out one of the limits is lost; keeping it for another attempt arrives with 4d.7.
    private func waitUntilRecognizerIsReady() async throws {
        let stallLimit = Int(DictationLimits.readinessStallTimeout / DictationLimits.readinessPollInterval)
        let totalLimit = Int(DictationLimits.readinessHardCap / DictationLimits.readinessPollInterval)
        var stalledPolls = 0
        var totalPolls = 0
        var lastProgress: Double?
        while true {
            let readiness = await recognizer.readiness()
            // Work that the total cap abandoned must not publish a state once it is cancelled.
            try Task.checkCancellation()
            switch readiness {
            case .ready:
                publish(.transcribing(progress: nil))
                return
            case .notInstalled:
                throw PipelineError.recognizerNotInstalled
            case .unavailable(let reason, let retryable):
                throw PipelineError.recognizerUnavailable(reason, retryable: retryable)
            case .loading(let progress):
                if progress != lastProgress {
                    lastProgress = progress
                    stalledPolls = 0
                }
                guard stalledPolls < stallLimit, totalPolls < totalLimit else {
                    throw PipelineError.timedOut(.readiness)
                }
                stalledPolls += 1
                totalPolls += 1
                publish(.transcribing(progress: progress))
                try await sleep(DictationLimits.readinessPollInterval)
            }
        }
    }

    private static func pipelineError(
        from error: any Error, otherwise make: (String) -> PipelineError
    ) -> PipelineError {
        error as? PipelineError ?? make(String(describing: error))
    }

    // MARK: Outcome

    /// Ends a cycle: shows the outcome, if any, and returns to idle. A cycle that ended a job tells the reducer first, so
    /// that Esc is already released when the idle state shows.
    private func settle(_ outcome: PipelineState? = nil, endsJob: Bool = false) async {
        guard phase != .stopped else { return }
        if endsJob { await dispatch(.jobFinished) }
        guard phase != .stopped else { return }
        dropContextJob()
        if let outcome {
            if case .error(let error) = outcome { diagnostics.record(.dictationFailed(kind: error.kind)) }
            publish(outcome)
        }
        phase = .idle
        processTask = nil
        publish(.idle)
    }

    private func publish(_ state: PipelineState) {
        guard state != published else { return }
        published = state
        continuation.yield(state)
    }
}
