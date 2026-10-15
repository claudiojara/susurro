import AVFoundation
import Domain

/// Captures the chosen microphone, or the system default one, as 16 kHz mono chunks. The first chunk is the readiness signal: it arrives with the
/// first real buffer from the device, not when the capture is requested. The capture ends on `stop`, which delivers
/// everything captured first, or when the stream ends some other way: a conversion error, a consumer that cancels
/// or drops it, or an input that cannot be got back.
///
/// The engine's configuration can change under a capture. A Bluetooth headset does it as the capture starts: opening
/// its microphone switches it to its call mode, at another sample rate, and the engine stops delivering. A device that
/// is plugged in or out does it too. The capture then restarts the engine in the device's new format and goes on in
/// the same stream, after delivering what it had captured. Only when the input cannot be got back (no device left, a
/// restart that fails twice, or changes that keep coming) does the stream end with `CaptureError.deviceRemoved`.
///
/// An engine that refuses to start, as one can right after a Bluetooth route change, is tried once more after a pause.
public actor AVAudioEngineCaptureSource: AudioCaptureSource {
    /// The pause before a second try at starting the engine. Long enough for a Bluetooth route to settle, short enough
    /// not to be felt.
    static let retryDelay: Duration = .milliseconds(250)
    /// How many configuration changes one capture rides through before it gives up.
    static let maximumRestarts = 4

    private struct Capture {
        let id: Int
        let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
        /// The bridge of the tap that is installed. Nil while the engine is being restarted.
        var bridge: TapBridge?
        /// Watches for a change of the engine's configuration while the engine runs.
        var observer: Task<Void, Never>?
        var restarts = 0
        /// The first buffer of a bridge retired by a restart, which is the capture's first buffer.
        var firstBuffer: (frames: Int, sampleRate: Double)?
    }

    private let engine: any EngineProviding
    private let diagnostics: any DiagnosticsLog
    /// The CoreAudio id of the microphone to record from, read as each capture starts, or nil for the system default.
    private let inputDevice: @Sendable () -> UInt32?
    private let sleep: @Sendable (Duration) async throws -> Void
    private var running: Capture?
    private var captureCount = 0
    /// Counts the calls to `start` and `stop`, so a start that paused before its retry knows it was overtaken.
    private var requests = 0

    /// - Parameters:
    ///   - diagnostics: Where the size of the first tap buffer of each capture is reported, a microphone that could not
    ///     be selected, and what the engine did when it failed or was restarted.
    ///   - inputDevice: The microphone to record from, read as each capture starts (`PreferredInputDevice`). Nil is the
    ///     system default.
    public init(
        diagnostics: any DiagnosticsLog = NoDiagnostics(), inputDevice: @escaping @Sendable () -> UInt32? = { nil }
    ) {
        self.init(engine: LiveAudioEngine(), diagnostics: diagnostics, inputDevice: inputDevice)
    }

    init(
        engine: any EngineProviding, diagnostics: any DiagnosticsLog = NoDiagnostics(),
        inputDevice: @escaping @Sendable () -> UInt32? = { nil },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.engine = engine
        self.diagnostics = diagnostics
        self.inputDevice = inputDevice
        self.sleep = sleep
    }

    public func start() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        // A second tap on the same bus would crash the engine, so a capture still running is ended first.
        endCapture(deliveringTail: true)
        requests += 1
        let request = requests
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, Error>.makeStream()
        captureCount += 1
        let id = captureCount
        // Anything that ends the stream ends the capture, so the engine never runs for nobody. Our own teardown ends it
        // too, and that second pass finds nothing to do.
        continuation.onTermination = { [weak self] _ in
            Task { await self?.streamEnded(id) }
        }
        var retried = false
        while true {
            do {
                let (bridge, changes) = try runEngine(into: continuation)
                running = Capture(
                    id: id, continuation: continuation, bridge: bridge, observer: watch(changes, capture: id))
                return stream
            } catch CaptureError.noInputDevice {
                continuation.finish()
                throw CaptureError.noInputDevice
            } catch {
                record(error, stage: "start")
                guard !retried else {
                    continuation.finish()
                    throw error
                }
                retried = true
                try? await sleep(Self.retryDelay)
                // A stop or another start while this one paused wins over it.
                guard requests == request else {
                    continuation.finish()
                    throw CancellationError()
                }
            }
        }
    }

    public func stop() async {
        requests += 1
        endCapture(deliveringTail: true)
    }

    /// Points the engine at the microphone, reads its format, installs the tap, and starts the engine. An engine that
    /// fails to start is left stopped with no tap. Returns the tap's bridge and the engine's configuration changes.
    private func runEngine(
        into continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
    ) throws -> (TapBridge, AsyncStream<Void>) {
        selectInputDevice()
        // Read now, after the device is chosen and right before the tap: a Bluetooth headset changes its format as its
        // microphone opens, and the tap must be in the format the device has at this moment.
        guard let format = engine.inputFormat() else { throw CaptureError.noInputDevice }
        let bridge = TapBridge(converter: try FormatConverter(from: format), continuation: continuation)
        engine.installTap(format: format) { bridge.receive($0) }
        let changes = engine.configurationChanges()
        do {
            try engine.start()
        } catch {
            engine.removeTap()
            engine.stop()
            throw error
        }
        return (bridge, changes)
    }

    private func watch(_ changes: AsyncStream<Void>, capture id: Int) -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in changes {
                await self?.configurationChanged(id)
                return
            }
        }
    }

    /// Points the engine at the chosen microphone. One that cannot be selected is logged, and the capture goes on with
    /// the system default rather than fail the dictation.
    private func selectInputDevice() {
        guard let id = inputDevice() else { return }
        do {
            try engine.useInputDevice(id)
        } catch let error as InputDeviceError {
            diagnostics.record(.microphoneSelectionFailed(status: error.status))
        } catch {
            diagnostics.record(.microphoneSelectionFailed(status: 0))
        }
    }

    private func streamEnded(_ id: Int) {
        guard running?.id == id else { return }
        endCapture(deliveringTail: false)
    }

    /// The engine's configuration changed under the capture, and the engine stopped delivering. What was captured is
    /// delivered, and the engine is restarted in the device's new format, feeding the same stream.
    private func configurationChanged(_ id: Int) async {
        guard var capture = running, capture.id == id else { return }
        engine.removeTap()
        engine.stop()
        // The tap is gone, so the old bridge can be flushed from here. Its observer is the task running this method,
        // and it ends by itself; cancelling it would cut the pause before a retry short.
        capture.bridge?.flush()
        capture.firstBuffer = capture.firstBuffer ?? capture.bridge?.firstBuffer
        capture.bridge = nil
        capture.observer = nil
        guard capture.restarts < Self.maximumRestarts else {
            running = capture
            return lose(id, reason: "restartLimit")
        }
        capture.restarts += 1
        running = capture

        var retried = false
        while true {
            do {
                let (bridge, changes) = try runEngine(into: capture.continuation)
                running?.bridge = bridge
                running?.observer = watch(changes, capture: id)
                diagnostics.record(
                    .captureReconfigured(
                        sampleRate: bridge.inputFormat.sampleRate, channels: Int(bridge.inputFormat.channelCount)))
                return
            } catch CaptureError.noInputDevice {
                return lose(id, reason: "noInputDevice")
            } catch {
                record(error, stage: "restart")
                guard !retried else { return lose(id, reason: "restartFailed") }
                retried = true
                try? await sleep(Self.retryDelay)
                // A stop, or a new capture, while this one paused has ended it already.
                guard running?.id == id else { return }
            }
        }
    }

    /// Ends a capture whose input could not be got back, after what it captured, as a removed device.
    private func lose(_ id: Int, reason: String) {
        guard running?.id == id else { return }
        diagnostics.record(.captureLost(reason: reason))
        endCapture(deliveringTail: true, failure: CaptureError.deviceRemoved)
    }

    /// Logs an engine error by its domain and code only: its message could carry anything.
    private func record(_ error: any Error, stage: String) {
        let error = error as NSError
        diagnostics.record(.captureEngineFailed(stage: stage, domain: error.domain, code: error.code))
    }

    /// Removes the tap before finishing, so every buffer already received has been yielded when the stream ends. Nothing
    /// calls the tap after that, which makes it safe to flush the bridge from here.
    private func endCapture(deliveringTail: Bool, failure: (any Error)? = nil) {
        guard let capture = running else { return }
        running = nil
        capture.observer?.cancel()
        // Without a bridge the engine is between runs, and a restart already stopped it.
        if capture.bridge != nil {
            engine.removeTap()
            engine.stop()
        }
        if deliveringTail { capture.bridge?.flush() }
        // The tap is gone, so the bridge is read from here without a race. The size is logged now and not on the audio
        // thread, where logging is best avoided.
        if let first = capture.firstBuffer ?? capture.bridge?.firstBuffer {
            diagnostics.record(.captureFirstBuffer(frames: first.frames, sampleRate: first.sampleRate))
        }
        capture.continuation.finish(throwing: failure)
    }
}

/// Runs on the audio thread: converts each device buffer and yields it to the stream.
///
/// This is the one `@unchecked Sendable` in the capture path. The converter is not thread-safe, so the bridge is safe
/// to share only as used: the engine calls the tap serially from one audio thread, and the actor touches the bridge
/// again only after removing the tap. Each run of the engine gets a new bridge.
private final class TapBridge: @unchecked Sendable {
    let inputFormat: AVAudioFormat
    private let converter: FormatConverter
    private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
    private var hasFailed = false
    /// The size and rate of the first buffer with samples in it. Written on the audio thread, and read only after the
    /// tap has been removed.
    private(set) var firstBuffer: (frames: Int, sampleRate: Double)?

    init(converter: FormatConverter, continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation) {
        self.converter = converter
        self.continuation = continuation
        inputFormat = converter.inputFormat
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        guard !hasFailed else { return }
        if firstBuffer == nil, buffer.frameLength > 0 {
            firstBuffer = (Int(buffer.frameLength), buffer.format.sampleRate)
        }
        do {
            let samples = try converter.convert(buffer)
            // An empty buffer, or one the resampler is still priming on, converts to nothing and signals nothing.
            guard !samples.isEmpty else { return }
            continuation.yield(AudioChunk(samples: samples))
        } catch {
            fail(error)
        }
    }

    /// Yields what the resampler still holds. Call it once, after the tap has been removed.
    func flush() {
        guard !hasFailed else { return }
        do {
            let tail = try converter.finish()
            if !tail.isEmpty { continuation.yield(AudioChunk(samples: tail)) }
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: any Error) {
        hasFailed = true
        continuation.finish(throwing: error)
    }
}
