import Domain

/// Runs one hold-to-talk dictation at a time: key down records, key up transcribes the recording and inserts the
/// text. The recording is written to disk as it is captured (`RecordingSession`) and is transcribed only once the file
/// has been read back. A hold that runs into the recording cap, or a device that goes away mid-recording, is
/// transcribed at once, and its text waits for the release before it goes in. A press while a dictation is recording or processing is ignored, and one that finds it processing says so
/// with a busy notice. Every wait is bounded, and so is the whole of the processing, so the coordinator always returns
/// to idle.
public actor DictationCoordinator {
    private enum Phase {
        case idle
        case starting  // preconditions are being checked and the capture is starting
        case capturing
        case finishing  // capture is being stopped and drained
        case processing  // the clip is being transcribed and inserted
        case stopped  // after shutdown()
    }

    private enum FinishReason: Equatable {
        case released(heldFor: Duration)
        case capReached
        case deviceRemoved
    }

    private let hotkeys: any HotkeySource
    private let capture: any AudioCaptureSource
    private let recordings: any AudioRecordingStore
    private let recognizer: any SpeechRecognizer
    private let inserter: any TextInserter
    private let permissions: any PermissionsChecker
    private let diagnostics: any DiagnosticsLog
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The current state first, then every change. It has a single consumer, which sees every state since creation.
    public nonisolated let states: AsyncStream<PipelineState>

    private var phase = Phase.idle
    private var published = PipelineState.idle
    private let continuation: AsyncStream<PipelineState>.Continuation
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
    private var processTask: Task<Void, Never>?
    /// The stage of the dictation being processed, which a cap that runs out names in its error.
    private var processingStage = PipelineError.Stage.readiness
    /// Whether the total cap ran out on the dictation being processed, as opposed to the limit of one of its stages.
    private var processingCapRanOut = false
    /// The one shutdown, so that every caller waits for the same work.
    private var shutdownTask: Task<Void, Never>?

    /// - Parameters:
    ///   - diagnostics: Where failures that would otherwise be swallowed are reported. They carry no text.
    ///   - sleep: Paces readiness checks and times out the waits. Tests pass a fake.
    public init(
        hotkeys: any HotkeySource,
        capture: any AudioCaptureSource,
        recordings: any AudioRecordingStore,
        recognizer: any SpeechRecognizer,
        inserter: any TextInserter,
        permissions: any PermissionsChecker,
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.hotkeys = hotkeys
        self.capture = capture
        self.recordings = recordings
        self.recognizer = recognizer
        self.inserter = inserter
        self.permissions = permissions
        self.diagnostics = diagnostics
        self.sleep = sleep
        (states, continuation) = AsyncStream.makeStream()
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
            sessionEvents?.cancel()
            processing?.cancel()
            shutdownTask = Task { await self.finishShutdown(wasRecording: wasRecording, processing: processing) }
        }
        await shutdownTask?.value
    }

    private func finishShutdown(wasRecording: Bool, processing: Task<Void, Never>?) async {
        if wasRecording { await abandonRecording() }
        await processing?.value
        sessionEvents = nil
        processTask = nil
        await drainInserter()
        publish(.idle)
        continuation.finish()
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
        switch event {
        case .down(let time): await pressed(at: time)
        case .up(let time): await released(at: time)
        }
    }

    private func pressed(at time: Duration) async {
        guard phase == .idle else { return reportBusyIfProcessing() }
        phase = .starting
        pressedAt = time
        pendingRelease = nil
        keyIsDown = true
        (keyUps, keyUp) = AsyncStream.makeStream()
        do {
            try await checkStartPreconditions()
            guard phase == .starting else { return }  // shut down meanwhile
            publish(.starting)
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
            capture: capture, store: recordings, maximumDuration: DictationLimits.recordingCap,
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

    /// A press that finds the last dictation still being processed gets no recording, so it says so. The state that was
    /// showing comes right back: the dictation carries on unchanged.
    private func reportBusyIfProcessing() {
        guard phase == .processing else { return }
        let showing = published
        publish(.notice(.busy))
        publish(showing)
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
        guard await permissions.status(.microphone) == .granted else { throw PipelineError.microphoneNotGranted }
        var readiness = await recognizer.readiness()
        if readiness == .ready { return }
        if readiness != .notInstalled {
            // A press is the chance to start a load that never started, or to retry one that failed. Preparing is
            // idempotent, so it is asked every time and the recognizer decides. What it says afterward counts, not
            // what it said before.
            try await withDeadline(DictationLimits.prepareTimeout, stage: .readiness, sleep: sleep) { [recognizer] in
                await recognizer.prepare()
            }
            readiness = await recognizer.readiness()
        }
        switch readiness {
        case .notInstalled: throw PipelineError.recognizerNotInstalled
        case .unavailable(let reason, let retryable):
            throw PipelineError.recognizerUnavailable(reason, retryable: retryable)
        case .loading, .ready: break
        }
    }

    /// Reacts to what the recording reports: the first buffer is the moment recording shows, and the cap or a device
    /// that went away finish it.
    private func consume(_ events: AsyncStream<RecordingSession.Event>) async {
        for await event in events {
            switch event {
            case .ready:
                if phase == .capturing { publish(.recording(.hold)) }
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
    /// discards a hold that was too short, or starts processing the recording.
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
            if reason == .capReached { publish(.notice(.capReached)) }
            if let notice { publish(.notice(notice)) }
            phase = .processing
            publish(.transcribing(progress: nil))
            processTask = Task { await self.process(verified) }
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

    /// Runs the processing of one recording inside the total cap. The work returns the state to end on and does not
    /// settle the cycle itself, so work that the cap abandons cannot settle it after the cap has.
    private func process(_ recording: VerifiedRecording) async {
        processingStage = .readiness
        processingCapRanOut = false
        do {
            let outcome = try await withDeadline(
                DictationLimits.processingCap, stageAtExpiry: { await self.capRanOut() }, sleep: sleep
            ) {
                try await self.transcribeAndInsert(recording)
            }
            settle(outcome)
        } catch {
            // The error alone cannot say which limit ended the dictation: the cap and a stage name the same stage.
            if processingCapRanOut { diagnostics.record(.processingCapReached) }
            settle(.error(Self.pipelineError(from: error, otherwise: PipelineError.recognitionFailed)))
        }
    }

    /// Called when the total cap runs out, and only then. Returns the stage the cap interrupted.
    private func capRanOut() -> PipelineError.Stage {
        processingCapRanOut = true
        return processingStage
    }

    private func transcribeAndInsert(_ recording: VerifiedRecording) async throws -> PipelineState {
        let clip: AudioClip
        do {
            clip = try await recordings.load(recording)
        } catch {
            throw PipelineError.persistenceFailed("the recording could not be read back")
        }
        try await waitUntilRecognizerIsReady()
        processingStage = .transcription
        let transcript = try await withDeadline(
            DictationLimits.transcriptionTimeout, stage: .transcription, sleep: sleep
        ) { [recognizer] in
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
        guard !transcript.text.allSatisfy(\.isWhitespace) else { return .notice(.noSpeech) }
        processingStage = .insertion
        try await waitForKeyRelease()
        let outcome = try await withDeadline(DictationLimits.insertionTimeout, stage: .insertion, sleep: sleep) {
            [inserter] in
            await inserter.insert(transcript.text)
        }
        switch outcome {
        case .inserted: return .inserted
        case .copiedToClipboard(let reason): return .notice(.copiedToClipboard(reason))
        case .notInserted(let reason): return .error(.notInserted(reason))
        }
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

    /// Ends a cycle: shows the outcome, if any, and returns to idle.
    private func settle(_ outcome: PipelineState? = nil) {
        guard phase != .stopped else { return }
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
