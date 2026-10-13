import Domain

/// Runs one hold-to-talk dictation at a time: key down records, key up transcribes the whole clip and inserts the
/// text. A press while a dictation is recording or processing is ignored. Every wait is bounded, so the coordinator
/// always returns to idle.
public actor DictationCoordinator {
    private enum Phase {
        case idle
        case starting  // preconditions are being checked and the capture is starting
        case capturing
        case finishing  // capture is being stopped and drained
        case processing  // the clip is being transcribed and inserted
        case stopped  // after shutdown()
    }

    private enum FinishReason {
        case released(heldFor: Duration)
        case capReached
    }

    private static let capSampleCount = Int(DictationLimits.recordingCap / .seconds(1)) * AudioClip.sampleRate

    private let hotkeys: any HotkeySource
    private let capture: any AudioCaptureSource
    private let recognizer: any SpeechRecognizer
    private let inserter: any TextInserter
    private let permissions: any PermissionsChecker
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The current state first, then every change. It has a single consumer, which sees every state since creation.
    public nonisolated let states: AsyncStream<PipelineState>

    private var phase = Phase.idle
    private var published = PipelineState.idle
    private let continuation: AsyncStream<PipelineState>.Continuation
    private var pressedAt = Duration.zero
    private var pendingRelease: Duration?
    private var samples: [Float] = []
    private var receivedAudio = false
    private var captureFailure: String?
    private var captureTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?

    /// - Parameter sleep: Paces readiness checks and times out the waits. Tests pass a fake.
    public init(
        hotkeys: any HotkeySource,
        capture: any AudioCaptureSource,
        recognizer: any SpeechRecognizer,
        inserter: any TextInserter,
        permissions: any PermissionsChecker,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.hotkeys = hotkeys
        self.capture = capture
        self.recognizer = recognizer
        self.inserter = inserter
        self.permissions = permissions
        self.sleep = sleep
        (states, continuation) = AsyncStream.makeStream()
        continuation.yield(.idle)
    }

    /// Feeds hotkey events to `handle` until the source finishes or the task is cancelled, then shuts down.
    public func run() async {
        for await event in hotkeys.events() {
            await handle(event)
        }
        await shutdown()
    }

    /// Stops any recording, abandons any dictation in progress without inserting it, and ends `states`. Ignores
    /// later events. It stops the capture even when the calling task is cancelled.
    public func shutdown() async {
        guard phase != .stopped else { return }
        let wasRecording = phase == .capturing || phase == .finishing
        phase = .stopped
        captureTask?.cancel()
        processTask?.cancel()
        samples = []
        if wasRecording { await abandonCapture() }
        await processTask?.value
        captureTask = nil
        processTask = nil
        publish(.idle)
        continuation.finish()
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
        guard phase == .idle else { return }
        phase = .starting
        pressedAt = time
        pendingRelease = nil
        do {
            try await checkStartPreconditions()
            guard phase == .starting else { return }  // shut down meanwhile
            publish(.starting)
            let stream = try await capture.start()
            guard phase == .starting else { return await abandonCapture() }  // shut down meanwhile
            samples = []
            receivedAudio = false
            captureFailure = nil
            phase = .capturing
            captureTask = Task { await self.consume(stream) }
            if let release = pendingRelease { await released(at: release) }
        } catch {
            settle(.error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)))
        }
    }

    private func released(at time: Duration) async {
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
        switch await recognizer.readiness() {
        case .notInstalled:
            throw PipelineError.recognizerNotInstalled
        case .unavailable(let reason):
            // Pressing again is the user's way to try again. The recognizer decides whether it is time.
            await recognizer.prepare()
            throw PipelineError.recognizerUnavailable(reason)
        case .loading, .ready:
            break
        }
    }

    private func consume(_ stream: AsyncThrowingStream<AudioChunk, Error>) async {
        do {
            for try await chunk in stream { receive(chunk) }
        } catch {
            // The samples captured so far stay in the clip. If none arrived, the release reports this failure.
            captureFailure = String(describing: error)
        }
    }

    private func receive(_ chunk: AudioChunk) {
        if !receivedAudio, phase == .capturing {
            receivedAudio = true
            publish(.recording(.hold))
        }
        samples.append(contentsOf: chunk.samples)
        if samples.count >= Self.capSampleCount { beginFinishing(reason: .capReached) }
    }

    /// Claims the recording for finishing, so the release and the cap cannot both finish it.
    @discardableResult
    private func beginFinishing(reason: FinishReason) -> Task<Void, Never>? {
        guard phase == .capturing else { return nil }
        phase = .finishing
        return Task { await self.finishRecording(reason) }
    }

    /// Stops capture, waits for the buffered chunks, then discards the clip or starts processing it.
    private func finishRecording(_ reason: FinishReason) async {
        do {
            try await withDeadline(DictationLimits.captureStopTimeout, stage: .capture, sleep: sleep) {
                [capture, captureTask] in
                await capture.stop()
                await captureTask?.value
            }
        } catch {
            captureTask?.cancel()
            return settle(.error(Self.pipelineError(from: error, otherwise: PipelineError.captureFailed)))
        }
        guard phase == .finishing else { return }  // shut down meanwhile
        captureTask = nil
        let clip = AudioClip(samples: samples)
        samples = []

        switch reason {
        case .released(let heldFor):
            guard heldFor >= DictationLimits.minimumHold else { return settle() }
            guard !clip.samples.isEmpty else {
                return settle(.error(.captureFailed(captureFailure ?? "no audio was captured")))
            }
        case .capReached:
            publish(.notice(.capReached))
        }
        phase = .processing
        publish(.transcribing(progress: nil))
        processTask = Task { await self.process(clip) }
    }

    /// Best effort: a capture that does not stop in time is abandoned. It runs in an unstructured task, so a caller
    /// that is already cancelled still stops the capture.
    private func abandonCapture() async {
        await Task {
            try? await withDeadline(DictationLimits.captureStopTimeout, stage: .capture, sleep: sleep) { [capture] in
                await capture.stop()
            }
        }.value
    }

    private func process(_ clip: AudioClip) async {
        do {
            try await waitUntilRecognizerIsReady()
            let transcript = try await withDeadline(
                DictationLimits.transcriptionTimeout, stage: .transcription, sleep: sleep
            ) { [recognizer] in
                try await recognizer.transcribe(clip, options: RecognitionOptions())
            }
            guard !transcript.text.allSatisfy(\.isWhitespace) else { return settle(.notice(.noSpeech)) }
            let outcome = try await withDeadline(DictationLimits.insertionTimeout, stage: .insertion, sleep: sleep) {
                [inserter] in
                await inserter.insert(transcript.text)
            }
            switch outcome {
            case .inserted: settle(.inserted)
            case .copiedToClipboard(let reason): settle(.notice(.copiedToClipboard(reason)))
            case .notInserted(let reason): settle(.error(.notInserted(reason)))
            }
        } catch {
            settle(.error(Self.pipelineError(from: error, otherwise: PipelineError.recognitionFailed)))
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
            switch await recognizer.readiness() {
            case .ready:
                publish(.transcribing(progress: nil))
                return
            case .notInstalled:
                throw PipelineError.recognizerNotInstalled
            case .unavailable(let reason):
                throw PipelineError.recognizerUnavailable(reason)
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
        if let outcome { publish(outcome) }
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
