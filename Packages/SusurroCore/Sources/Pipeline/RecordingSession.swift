import Domain

/// Why a recording did not come out as a verified file.
public enum RecordingFailure: Error, Sendable, Equatable {
    /// The recording could not be written to disk and read back, so it must not be transcribed.
    case persistence
    /// The capture failed and no audio had arrived. The text is the underlying error.
    case capture(String)
}

/// How a recording ended.
public enum RecordingResult: Sendable, Equatable {
    /// The audio is on disk and verified. `notice` says something the user should know about how it ended.
    case recorded(VerifiedRecording, notice: NoticeKind?)
    /// Shorter than `RecordingLimits.minimumDuration`: the file is deleted and nothing was recorded.
    case tooShort
    case failed(RecordingFailure)
}

/// One recording, from the start of the capture to a verified file. It writes the audio out while it is captured, so
/// memory holds a second of it at a time however long the recording runs, and it hands out a recording only after the
/// store has read the file back. Recognition starts from that recording and from nothing else.
public actor RecordingSession {
    public enum Event: Sendable, Equatable {
        /// The first real buffer arrived.
        case ready
        /// The level of a buffer, as its RMS amplitude.
        case level(Float)
        /// The recording reached its maximum duration. Audio past it is dropped; finish the recording.
        case limitReached
        /// The input device went away. What was captured is kept; finish the recording.
        case deviceRemoved
    }

    public nonisolated let id: SessionID
    /// What happens while recording, ending when the recording is finished or aborted. It has a single consumer.
    public nonisolated let events: AsyncStream<Event>

    private let capture: any AudioCaptureSource
    private let store: any AudioRecordingStore
    private let maximumSamples: Int?
    private let diagnostics: any DiagnosticsLog
    private let eventContinuation: AsyncStream<Event>.Continuation

    private var sink: (any AudioRecordingSink)?
    private var consumer: Task<Void, Never>?
    private var pending: [Float] = []
    private var received = 0
    private var peakPending = 0
    private var ready = false
    private var limitReported = false
    private var writeFailed = false
    private var deviceLost = false
    private var streamFailure: String?
    private var ended = false

    /// - Parameters:
    ///   - maximumDuration: Audio past it is dropped and `limitReached` is sent. Nil for no limit.
    public init(
        id: SessionID = SessionID(),
        capture: any AudioCaptureSource,
        store: any AudioRecordingStore,
        maximumDuration: Duration? = nil,
        diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        self.id = id
        self.capture = capture
        self.store = store
        self.diagnostics = diagnostics
        maximumSamples = maximumDuration.map { AudioClip.sampleIndex(at: $0) }
        (events, eventContinuation) = AsyncStream.makeStream()
    }

    /// Whether the first buffer has arrived.
    public var isReady: Bool { ready }

    /// The most audio that was held in memory, waiting to be written, at any moment so far.
    public var peakBufferedDuration: Duration { AudioClip.duration(ofSamples: peakPending) }

    /// How much audio has been captured.
    public var recordedDuration: Duration { AudioClip.duration(ofSamples: received) }

    /// Starts the capture and opens the file. Throws `CaptureError.noInputDevice` or whatever the capture throws, and
    /// `RecordingFailure.persistence` when the store cannot open the file, in which case nothing records.
    public func start() async throws {
        let stream: AsyncThrowingStream<AudioChunk, Error>
        do {
            stream = try await capture.start()
        } catch {
            end()
            throw error
        }
        do {
            sink = try await store.begin(id)
        } catch {
            diagnostics.record(.recordingStoreFailed(step: "begin"))
            await capture.stop()
            end()
            throw RecordingFailure.persistence
        }
        consumer = Task { await self.consume(stream) }
    }

    /// Stops the capture, waits for the audio it still holds, and verifies the file. Call it once.
    public func finish() async -> RecordingResult {
        await capture.stop()
        await consumer?.value
        consumer = nil
        defer { end() }
        guard !ended, let sink else { return .failed(.capture("the recording was abandoned")) }
        self.sink = nil
        if writeFailed {
            await sink.abort()
            return .failed(.persistence)
        }
        if received == 0 {
            await sink.abort()
            return .failed(.capture(streamFailure ?? "no audio was captured"))
        }
        if recordedDuration < RecordingLimits.minimumDuration {
            await sink.abort()
            return .tooShort
        }
        do {
            try await write(pending, to: sink)
        } catch {
            return await fail(sink, at: "write")
        }
        let recording: VerifiedRecording
        do {
            recording = try await sink.finish()
        } catch {
            return await fail(sink, at: "verify")
        }
        let difference = max(recording.duration, recordedDuration) - min(recording.duration, recordedDuration)
        guard recording.sampleCount > 0, difference <= RecordingLimits.durationTolerance else {
            return await fail(sink, at: "verify")
        }
        return .recorded(recording, notice: deviceLost ? .deviceDisconnected : nil)
    }

    /// Deletes what is on disk and reports that the recording could not be kept.
    private func fail(_ sink: any AudioRecordingSink, at step: String) async -> RecordingResult {
        diagnostics.record(.recordingStoreFailed(step: step))
        await sink.abort()
        return .failed(.persistence)
    }

    /// Stops the capture and deletes the file, as for a recording that is not kept. It also ends a `finish` that is
    /// stuck, which then reports the recording as abandoned.
    public func abort() async {
        let consuming = consumer
        consumer = nil
        consuming?.cancel()
        let sink = self.sink
        self.sink = nil
        end()
        await capture.stop()
        await sink?.abort()
    }

    // MARK: Consuming

    private func consume(_ stream: AsyncThrowingStream<AudioChunk, Error>) async {
        do {
            for try await chunk in stream { await receive(chunk) }
        } catch CaptureError.deviceRemoved {
            deviceLost = true
            eventContinuation.yield(.deviceRemoved)
        } catch {
            // The audio captured so far stays. If none arrived, finishing reports this failure.
            streamFailure = String(describing: error)
            diagnostics.record(.captureStreamFailed(errorType: String(describing: type(of: error))))
        }
    }

    private func receive(_ chunk: AudioChunk) async {
        guard !ended, !limitReported, !chunk.samples.isEmpty else { return }
        var samples = chunk.samples
        if let maximumSamples, received + samples.count >= maximumSamples {
            samples = Array(samples.prefix(max(0, maximumSamples - received)))
            limitReported = true
        }
        if !ready {
            ready = true
            eventContinuation.yield(.ready)
        }
        if !samples.isEmpty {
            eventContinuation.yield(.level(Self.rms(of: samples)))
            received += samples.count
            guard !writeFailed else { return await announceLimit() }
            pending.append(contentsOf: samples)
            peakPending = max(peakPending, pending.count)
            if pending.count >= AudioClip.sampleIndex(at: RecordingLimits.writeBatch) { await flush() }
        }
        await announceLimit()
    }

    private func announceLimit() async {
        if limitReported { eventContinuation.yield(.limitReached) }
    }

    private func flush() async {
        guard let sink else { return }
        let batch = pending
        pending = []
        do {
            try await write(batch, to: sink)
        } catch {
            writeFailed = true
            diagnostics.record(.recordingStoreFailed(step: "write"))
        }
    }

    private func write(_ samples: [Float], to sink: any AudioRecordingSink) async throws {
        guard !samples.isEmpty else { return }
        try await sink.append(AudioChunk(samples: samples))
    }

    private func end() {
        ended = true
        eventContinuation.finish()
    }

    private static func rms(of samples: [Float]) -> Float {
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }
}
