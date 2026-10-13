import AVFoundation
import Domain

/// Captures the default microphone as 16 kHz mono chunks.
///
/// `start` returns once the engine is running. The first chunk is the readiness signal: it arrives with the first real
/// buffer from the device, not when the capture is requested.
public actor AVAudioEngineCaptureSource: AudioCaptureSource {
    private let engine: any EngineProviding
    private var running: AsyncThrowingStream<AudioChunk, Error>.Continuation?

    public init() {
        self.init(engine: LiveAudioEngine())
    }

    init(engine: any EngineProviding) {
        self.engine = engine
    }

    public func start() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        // A second tap on the same bus would crash the engine, so a capture still running is ended first.
        endCapture()
        guard let format = engine.inputFormat() else { throw CaptureError.noInputDevice }
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, Error>.makeStream()
        let bridge = TapBridge(converter: try FormatConverter(from: format), continuation: continuation)
        engine.installTap { bridge.receive($0) }
        do {
            try engine.start()
        } catch {
            engine.removeTap()
            engine.stop()
            continuation.finish()
            throw error
        }
        running = continuation
        return stream
    }

    public func stop() async {
        endCapture()
    }

    /// Removes the tap before finishing, so every buffer already received has been yielded when the stream ends.
    private func endCapture() {
        guard let continuation = running else { return }
        running = nil
        engine.removeTap()
        engine.stop()
        continuation.finish()
    }
}

/// Runs on the audio thread: converts each device buffer and yields it to the stream.
///
/// This is the one `@unchecked Sendable` in the capture path. The converter is not thread-safe, and the bridge is
/// safe to share only because of how it is used: the actor creates it, hands it to the engine's tap, and never touches
/// it again, while the engine calls the tap serially from a single audio thread. A new capture gets a new bridge.
private final class TapBridge: @unchecked Sendable {
    private let converter: FormatConverter
    private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation

    init(converter: FormatConverter, continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation) {
        self.converter = converter
        self.continuation = continuation
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        do {
            continuation.yield(AudioChunk(samples: try converter.convert(buffer)))
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
