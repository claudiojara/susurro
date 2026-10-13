import Domain

/// Limits of the walking skeleton. Later changes replace each one.
public enum SkeletonLimits {
    /// A shorter hold is discarded.
    public static let minimumHold = Duration.milliseconds(300)
    /// Reaching this much audio finishes the recording.
    public static let maxClipDuration = Duration.seconds(60)
    /// The pause between readiness checks while the speech model loads.
    public static let readinessPollInterval = Duration.milliseconds(200)
    /// How long a loading model may keep a finished recording waiting.
    public static let readinessTimeout = Duration.seconds(60)
    /// How long stopping the capture and delivering its last chunks may take.
    public static let captureStopTimeout = Duration.seconds(5)
    public static let transcriptionTimeout = Duration.seconds(30)
    public static let insertionTimeout = Duration.seconds(10)
}

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

    private static let capSampleCount = Int(SkeletonLimits.maxClipDuration / .seconds(1)) * AudioClip.sampleRate

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
        // An unstructured task, so the cleanup runs to completion even when this task was cancelled.
        await Task { await self.shutdown() }.value
    }

    /// Stops any recording, abandons any dictation in progress without inserting it, and ends `states`. Ignores
    /// later events. Call it from a task that is not cancelled.
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
            publish(.starting)
            let stream = try await capture.start()
            guard phase == .starting else { return await abandonCapture() }  // shut down meanwhile
            samples = []
            receivedAudio = false
            phase = .capturing
            captureTask = Task { await self.consume(stream) }
            if let release = pendingRelease { await released(at: release) }
        } catch {
            settle(.error(error as? PipelineError ?? .captureFailed))
        }
    }

    private func released(at time: Duration) async {
        switch phase {
        case .starting:
            pendingRelease = time  // honored as soon as the capture has started
        case .capturing:
            phase = .finishing
            await finishRecording(.released(heldFor: time - pressedAt))
        default:
            return
        }
    }

    private func checkStartPreconditions() async throws {
        guard await permissions.status(.microphone) == .granted else { throw PipelineError.microphoneNotGranted }
        guard await recognizer.readiness() != .notInstalled else { throw PipelineError.recognizerNotInstalled }
    }

    private func consume(_ stream: AsyncThrowingStream<AudioChunk, Error>) async {
        do {
            for try await chunk in stream { record(chunk) }
        } catch {
            // The samples captured so far stay in the clip. Device loss gets its own handling later.
        }
    }

    private func record(_ chunk: AudioChunk) {
        if !receivedAudio, phase == .capturing {
            receivedAudio = true
            publish(.recording(.hold))
        }
        samples.append(contentsOf: chunk.samples)
        if phase == .capturing, samples.count >= Self.capSampleCount {
            phase = .finishing
            Task { await self.finishRecording(.capReached) }
        }
    }

    /// Stops capture, waits for the buffered chunks, then discards the clip or starts processing it.
    private func finishRecording(_ reason: FinishReason) async {
        do {
            try await withDeadline(SkeletonLimits.captureStopTimeout, stage: .capture, sleep: sleep) {
                [capture, captureTask] in
                await capture.stop()
                await captureTask?.value
            }
        } catch is CancellationError {
            return  // shutdown() cleans up
        } catch {
            captureTask?.cancel()
            return settle(.error(error as? PipelineError ?? .captureFailed))
        }
        guard phase == .finishing else { return }  // shut down meanwhile
        captureTask = nil
        let clip = AudioClip(samples: samples)
        samples = []

        switch reason {
        case .released(let heldFor):
            guard heldFor >= SkeletonLimits.minimumHold else { return settle() }
            guard !clip.samples.isEmpty else { return settle(.error(.captureFailed)) }
        case .capReached:
            publish(.notice(.capReached))
        }
        phase = .processing
        publish(.transcribing(progress: nil))
        processTask = Task { await self.process(clip) }
    }

    /// Best effort: a capture that does not stop in time is abandoned.
    private func abandonCapture() async {
        try? await withDeadline(SkeletonLimits.captureStopTimeout, stage: .capture, sleep: sleep) { [capture] in
            await capture.stop()
        }
    }

    private func process(_ clip: AudioClip) async {
        do {
            try await waitUntilRecognizerIsReady()
            let transcript = try await withDeadline(
                SkeletonLimits.transcriptionTimeout, stage: .transcription, sleep: sleep
            ) { [recognizer] in
                try await recognizer.transcribe(clip, options: RecognitionOptions())
            }
            guard !transcript.text.allSatisfy(\.isWhitespace) else { return settle(.notice(.noSpeech)) }
            let outcome = try await withDeadline(SkeletonLimits.insertionTimeout, stage: .insertion, sleep: sleep) {
                [inserter] in
                await inserter.insert(transcript.text)
            }
            switch outcome {
            case .inserted: settle(.inserted)
            case .copiedToClipboard(let reason): settle(.notice(.copiedToClipboard(reason)))
            }
        } catch is CancellationError {
            return  // shutdown() cleans up
        } catch {
            settle(.error(error as? PipelineError ?? .recognitionFailed))
        }
    }

    private func waitUntilRecognizerIsReady() async throws {
        var pausesLeft = Int(SkeletonLimits.readinessTimeout / SkeletonLimits.readinessPollInterval)
        while true {
            switch await recognizer.readiness() {
            case .ready:
                publish(.transcribing(progress: nil))
                return
            case .notInstalled:
                throw PipelineError.recognizerNotInstalled
            case .loading(let progress):
                guard pausesLeft > 0 else { throw PipelineError.timedOut(.readiness) }
                pausesLeft -= 1
                publish(.transcribing(progress: progress))
                try await sleep(SkeletonLimits.readinessPollInterval)
            }
        }
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
