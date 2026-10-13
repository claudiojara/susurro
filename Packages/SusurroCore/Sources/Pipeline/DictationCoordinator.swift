import Domain

/// Limits of the walking skeleton. Later changes replace each one; see the task list.
public enum SkeletonLimits {
    /// The shortest hold that counts as a dictation. A shorter release is discarded.
    public static let minimumHold = Duration.milliseconds(300)
    /// The longest clip held in memory. Reaching it finishes the recording.
    public static let maxClipDuration = Duration.seconds(60)
    /// The pause between readiness checks while the speech model loads.
    public static let readinessPollInterval = Duration.milliseconds(200)
}

/// Runs one hold-to-talk dictation at a time: key down records, key up transcribes the whole clip and inserts the
/// text. A press while a dictation is recording or processing is ignored.
public actor DictationCoordinator {
    /// The coordinator's internal state. The published `PipelineState` is derived from it.
    private enum Phase {
        case idle
        case capturing
        /// Capture is being stopped and drained.
        case finishing
        /// The clip is being transcribed and inserted.
        case processing
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

    private var phase = Phase.idle
    private var published = PipelineState.idle
    private var subscribers: [Int: AsyncStream<PipelineState>.Continuation] = [:]
    private var nextSubscriberID = 0
    private var pressedAt = Duration.zero
    private var samples: [Float] = []
    private var receivedAudio = false
    private var captureTask: Task<Void, Never>?

    /// - Parameter sleep: Pauses between readiness checks. Tests pass a no-op.
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
    }

    /// The current state first, then every change.
    public func states() -> AsyncStream<PipelineState> {
        let (stream, continuation) = AsyncStream.makeStream(of: PipelineState.self)
        let id = nextSubscriberID
        nextSubscriberID += 1
        subscribers[id] = continuation
        continuation.yield(published)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// Feeds hotkey events to `handle` until the source finishes or the task is cancelled.
    public func run() async {
        for await event in hotkeys.events() {
            await handle(event)
        }
    }

    /// Applies one hotkey event. Events must arrive one at a time, as `run()` delivers them. The call returns once
    /// the event is applied, which is before any transcription it starts has finished.
    public func handle(_ event: HotkeyEvent) async {
        switch event {
        case .down(let time): await pressed(at: time)
        case .up(let time): await released(at: time)
        }
    }

    // MARK: Hold-to-talk transitions

    private func pressed(at time: Duration) async {
        guard phase == .idle else { return }
        do {
            try await checkStartPreconditions()
            publish(.starting)
            let stream = try await capture.start()
            pressedAt = time
            samples = []
            receivedAudio = false
            phase = .capturing
            captureTask = Task { await self.consume(stream) }
        } catch {
            settle(.error(error as? PipelineError ?? .captureFailed))
        }
    }

    private func released(at time: Duration) async {
        guard phase == .capturing else { return }
        phase = .finishing
        await finishRecording(.released(heldFor: time - pressedAt))
    }

    private func checkStartPreconditions() async throws {
        guard await permissions.status(.microphone) == .granted else { throw PipelineError.microphoneNotGranted }
        guard await recognizer.readiness() != .notInstalled else { throw PipelineError.recognizerNotInstalled }
    }

    // MARK: Capture

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
        await capture.stop()
        await captureTask?.value
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
        Task { await self.process(clip) }
    }

    // MARK: Processing

    private func process(_ clip: AudioClip) async {
        do {
            try await waitUntilRecognizerIsReady()
            let transcript = try await recognizer.transcribe(clip, options: RecognitionOptions())
            guard !transcript.text.allSatisfy(\.isWhitespace) else { return settle(.notice(.noSpeech)) }
            await inserter.insert(transcript.text)
            settle(.inserted)
        } catch {
            settle(.error(error as? PipelineError ?? .recognitionFailed))
        }
    }

    private func waitUntilRecognizerIsReady() async throws {
        while true {
            switch await recognizer.readiness() {
            case .ready:
                publish(.transcribing(progress: nil))
                return
            case .notInstalled:
                throw PipelineError.recognizerNotInstalled
            case .loading(let progress):
                publish(.transcribing(progress: progress))
                try await sleep(SkeletonLimits.readinessPollInterval)
            }
        }
    }

    // MARK: Publishing

    /// Ends a cycle: shows the outcome, if any, and returns to idle.
    private func settle(_ outcome: PipelineState? = nil) {
        if let outcome { publish(outcome) }
        phase = .idle
        publish(.idle)
    }

    private func publish(_ state: PipelineState) {
        guard state != published else { return }
        published = state
        for continuation in subscribers.values { continuation.yield(state) }
    }

    private func removeSubscriber(_ id: Int) {
        subscribers[id] = nil
    }
}
