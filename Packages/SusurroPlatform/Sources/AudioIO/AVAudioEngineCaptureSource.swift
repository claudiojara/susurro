import AVFoundation
import Domain

/// Captures the default microphone as 16 kHz mono chunks. The first chunk is the readiness signal: it arrives with the
/// first real buffer from the device, not when the capture is requested. The capture ends on `stop`, which delivers
/// everything captured first, or when the stream ends some other way: a conversion error, a consumer that cancels
/// or drops it, or a change of the engine's configuration. That change is what a device that is unplugged, or a route
/// that switches mid-recording (AirPods connecting), looks like: the stream ends with `CaptureError.deviceRemoved`,
/// after everything captured until then.
public actor AVAudioEngineCaptureSource: AudioCaptureSource {
    private struct Capture {
        let id: Int
        let bridge: TapBridge
        let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
        /// Watches for a change of the engine's configuration for as long as the capture runs.
        let observer: Task<Void, Never>
    }

    private let engine: any EngineProviding
    private let diagnostics: any DiagnosticsLog
    private var running: Capture?
    private var captureCount = 0

    /// - Parameter diagnostics: Where the size of the first tap buffer of each capture is reported.
    public init(diagnostics: any DiagnosticsLog = NoDiagnostics()) {
        self.init(engine: LiveAudioEngine(), diagnostics: diagnostics)
    }

    init(engine: any EngineProviding, diagnostics: any DiagnosticsLog = NoDiagnostics()) {
        self.engine = engine
        self.diagnostics = diagnostics
    }

    public func start() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        // A second tap on the same bus would crash the engine, so a capture still running is ended first.
        endCapture(deliveringTail: true)
        guard let format = engine.inputFormat() else { throw CaptureError.noInputDevice }
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, Error>.makeStream()
        let bridge = TapBridge(converter: try FormatConverter(from: format), continuation: continuation)
        captureCount += 1
        let id = captureCount
        // Anything that ends the stream ends the capture, so the engine never runs for nobody. Our own teardown ends it
        // too, and that second pass finds nothing to do.
        continuation.onTermination = { [weak self] _ in
            Task { await self?.streamEnded(id) }
        }
        engine.installTap(format: format) { bridge.receive($0) }
        let changes = engine.configurationChanges()
        do {
            try engine.start()
        } catch {
            engine.removeTap()
            engine.stop()
            continuation.finish()
            throw error
        }
        let observer = Task { [weak self] in
            for await _ in changes {
                await self?.configurationChanged(id)
                return
            }
        }
        running = Capture(id: id, bridge: bridge, continuation: continuation, observer: observer)
        return stream
    }

    public func stop() async {
        endCapture(deliveringTail: true)
    }

    private func streamEnded(_ id: Int) {
        guard running?.id == id else { return }
        endCapture(deliveringTail: false)
    }

    /// The engine's configuration changed under the capture, and the engine stopped delivering. What was captured is
    /// delivered first, then the stream ends with the reason.
    private func configurationChanged(_ id: Int) {
        guard running?.id == id else { return }
        endCapture(deliveringTail: true, failure: CaptureError.deviceRemoved)
    }

    /// Removes the tap before finishing, so every buffer already received has been yielded when the stream ends. Nothing
    /// calls the tap after that, which makes it safe to flush the bridge from here.
    private func endCapture(deliveringTail: Bool, failure: (any Error)? = nil) {
        guard let capture = running else { return }
        running = nil
        capture.observer.cancel()
        engine.removeTap()
        engine.stop()
        if deliveringTail { capture.bridge.flush() }
        // The tap is gone, so the bridge is read from here without a race. The size is logged now and not on the audio
        // thread, where logging is best avoided.
        if let first = capture.bridge.firstBuffer {
            diagnostics.record(.captureFirstBuffer(frames: first.frames, sampleRate: first.sampleRate))
        }
        capture.continuation.finish(throwing: failure)
    }
}

/// Runs on the audio thread: converts each device buffer and yields it to the stream.
///
/// This is the one `@unchecked Sendable` in the capture path. The converter is not thread-safe, so the bridge is safe
/// to share only as used: the engine calls the tap serially from one audio thread, and the actor touches the bridge
/// again only after removing the tap. A new capture gets a new bridge.
private final class TapBridge: @unchecked Sendable {
    private let converter: FormatConverter
    private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
    private var hasFailed = false
    /// The size and rate of the first buffer with samples in it. Written on the audio thread, and read only after the
    /// tap has been removed.
    private(set) var firstBuffer: (frames: Int, sampleRate: Double)?

    init(converter: FormatConverter, continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation) {
        self.converter = converter
        self.continuation = continuation
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
