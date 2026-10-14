import AVFoundation
import CoreTestSupport
import Domain
import Synchronization
import Testing

@testable import AudioIO

@Suite("AVAudioEngine capture source", .timeLimit(.minutes(1)))
struct AVAudioEngineCaptureSourceTests {
    private struct EngineFailure: Error, Equatable {}

    private enum Call: Equatable {
        case installTap, removeTap, start, stop
    }

    /// An input device scripted by the test. It records what the source asks of it, in order, and behaves like the real
    /// engine: one tap at a time, buffers only while it runs and a tap is installed, and the buffer's memory is reused
    /// as soon as the tap returns.
    private final class FakeEngine: EngineProviding {
        private struct State {
            var tap: (@Sendable (AVAudioPCMBuffer) -> Void)?
            var tapFormat: AVAudioFormat?
            var isRunning = false
            var calls: [Call] = []
            var changes: AsyncStream<Void>.Continuation?
        }

        /// Opened when the engine is stopped, so tests can wait for a teardown the source starts on its own.
        let stopped = Gate()
        let format: AVAudioFormat?
        private let startFailure: (any Error)?
        private let state = Mutex(State())

        init(
            format: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
            startFailure: (any Error)? = nil
        ) {
            self.format = format
            self.startFailure = startFailure
        }

        var calls: [Call] { state.withLock { $0.calls } }
        var tapFormat: AVAudioFormat? { state.withLock { $0.tapFormat } }

        func deliver(_ buffer: AVAudioPCMBuffer) {
            let (tap, isRunning) = state.withLock { ($0.tap, $0.isRunning) }
            guard isRunning else {
                Issue.record("A buffer was delivered while the engine is not running.")
                return
            }
            tap?(buffer)
            // The real engine reuses this memory once the tap returns, so a bridge that kept the buffer would read this.
            if let data = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) { data[channel][frame * buffer.stride] = .nan }
                }
            }
        }

        /// Tells the source that the engine's configuration changed, as an unplugged device or a route switch does.
        func signalConfigurationChange() {
            state.withLock { $0.changes }?.yield()
        }

        func configurationChanges() -> AsyncStream<Void> {
            let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
            state.withLock { $0.changes = continuation }
            return stream
        }

        func inputFormat() -> AVAudioFormat? { format }

        func installTap(format: AVAudioFormat, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
            state.withLock {
                precondition($0.tap == nil, "A second tap was installed on the same bus.")
                $0.calls.append(.installTap)
                $0.tap = handler
                $0.tapFormat = format
            }
        }

        func removeTap() {
            state.withLock {
                $0.calls.append(.removeTap)
                $0.tap = nil
            }
        }

        func start() throws {
            state.withLock { $0.calls.append(.start) }
            if let startFailure { throw startFailure }
            state.withLock { $0.isRunning = true }
        }

        func stop() {
            state.withLock {
                $0.calls.append(.stop)
                $0.isRunning = false
            }
            stopped.open()
        }
    }

    /// 100 ms of a 48 kHz stereo device.
    private static func deviceBuffer(startingAt start: Int = 0) -> AVAudioPCMBuffer {
        makeBuffer(sampleRate: 48_000, channels: 2, frames: 4_800, startingAt: start, sample: tone(sampleRate: 48_000))
    }

    /// A 100 ms device buffer converts to at most 1600 samples; the first chunk is shorter while the resampler primes.
    private static func isConvertedBuffer(_ count: Int?) -> Bool {
        count.map { (1_000...1_600).contains($0) } ?? false
    }

    private static func drain(_ stream: AsyncThrowingStream<AudioChunk, Error>) async throws -> [AudioChunk] {
        var chunks: [AudioChunk] = []
        for try await chunk in stream { chunks.append(chunk) }
        return chunks
    }

    @Test("without an input device, start throws before any tap or engine start")
    func noInputDevice() async {
        let engine = FakeEngine(format: nil)
        let sut = AVAudioEngineCaptureSource(engine: engine)

        await #expect(throws: CaptureError.noInputDevice) { try await sut.start() }

        #expect(engine.calls.isEmpty)
    }

    @Test("the first real buffer yields the first chunk, converted, through a tap in the device format")
    func firstBufferIsTheFirstChunk() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        var chunks = try await sut.start().makeAsyncIterator()

        engine.deliver(Self.deviceBuffer())

        let chunk = try #require(try await chunks.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
        #expect(!chunk.samples.contains { $0.isNaN })
        #expect(engine.tapFormat == engine.format)
    }

    @Test("starting alone signals nothing: a capture stopped before any buffer ends with no chunk")
    func startIsNotReadiness() async throws {
        let sut = AVAudioEngineCaptureSource(engine: FakeEngine())
        let stream = try await sut.start()

        await sut.stop()

        #expect(try await Self.drain(stream).isEmpty)
    }

    @Test(
        "a buffer that is empty, or converts to nothing, is not readiness",
        arguments: [0, 16]
    )
    func bufferWithoutSamplesIsIgnored(frames: Int) async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        var chunks = try await sut.start().makeAsyncIterator()

        engine.deliver(makeBuffer(sampleRate: 48_000, channels: 2, frames: frames) { _, _ in 0.5 })
        engine.deliver(Self.deviceBuffer())

        let chunk = try #require(try await chunks.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
    }

    @Test(
        "stop delivers everything captured, including the resampler's tail, and removes the tap",
        arguments: [44_100.0, 48_000, 96_000]
    )
    func stopDeliversEverythingCaptured(sampleRate: Double) async throws {
        let frames = 4_096
        let engine = FakeEngine(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let sut = AVAudioEngineCaptureSource(engine: engine)
        let stream = try await sut.start()
        for buffer in tapBuffers(
            sampleRate: sampleRate, count: 50, frames: frames, sample: tone(sampleRate: sampleRate))
        {
            engine.deliver(buffer)
        }

        await sut.stop()

        let total = try await Self.drain(stream).reduce(0) { $0 + $1.samples.count }
        let nominal = Double(50 * frames) * 16_000 / sampleRate
        #expect(abs(Double(total) - nominal) <= 1)
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
    }

    @Test("stop without a running capture does nothing")
    func stopWhenIdle() async {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)

        await sut.stop()

        #expect(engine.calls.isEmpty)
    }

    @Test("starting again tears the previous capture down first, so the tap is never installed twice")
    func restartReplacesCapture() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        let first = try await sut.start()

        var second = try await sut.start().makeAsyncIterator()
        engine.deliver(Self.deviceBuffer())

        #expect(try await Self.drain(first).isEmpty)
        let chunk = try #require(try await second.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop, .installTap, .start])
    }

    @Test("an engine that fails to start throws its error and leaves nothing installed")
    func engineStartFailure() async {
        let engine = FakeEngine(startFailure: EngineFailure())
        let sut = AVAudioEngineCaptureSource(engine: engine)

        await #expect(throws: EngineFailure()) { try await sut.start() }

        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
    }

    @Test("a buffer in another format than the device's ends the stream and tears the capture down")
    func formatChangeEndsTheCapture() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        var chunks = try await sut.start().makeAsyncIterator()

        engine.deliver(Self.deviceBuffer())
        engine.deliver(makeBuffer(sampleRate: 44_100, channels: 1, frames: 441) { _, _ in 0.5 })

        let chunk = try #require(try await chunks.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
        await #expect(throws: FormatConversionError.formatChanged) { try await chunks.next() }
        #expect(try await chunks.next() == nil)
        await engine.stopped.wait()
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
        await sut.stop()
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
    }

    @Test("a configuration change mid-recording delivers what was captured, then ends the stream as a removed device")
    func configurationChangeEndsTheCapture() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        var chunks = try await sut.start().makeAsyncIterator()

        engine.deliver(Self.deviceBuffer())
        engine.signalConfigurationChange()

        let chunk = try #require(try await chunks.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
        // The resampler's tail may come as one more chunk before the end.
        var ended = false
        while !ended {
            do {
                ended = try await chunks.next() == nil
            } catch {
                #expect(error as? CaptureError == .deviceRemoved)
                ended = true
            }
        }
        await engine.stopped.wait()
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
        await sut.stop()
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
    }

    @Test("a consumer that stops reading ends the capture")
    func consumerCancellationEndsTheCapture() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        let stream = try await sut.start()
        let firstChunk = Gate()
        let reader = Task {
            for try await _ in stream { firstChunk.open() }
        }
        engine.deliver(Self.deviceBuffer())
        await firstChunk.wait()

        reader.cancel()

        await engine.stopped.wait()
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
    }

    @Test("a stream that is dropped without being read ends the capture")
    func droppedStreamEndsTheCapture() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)

        _ = try await sut.start()

        await engine.stopped.wait()
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
    }

    @Test(
        "a capture logs the size of the first tap buffer it received, once",
        arguments: [(512, 44_100.0), (4_800, 48_000), (1_024, 48_000)]
    )
    func logsTheFirstTapBuffer(frames: Int, sampleRate: Double) async throws {
        let log = RecordingDiagnostics()
        let engine = FakeEngine(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log)
        let stream = try await sut.start()
        engine.deliver(makeBuffer(sampleRate: sampleRate, channels: 2, frames: 0) { _, _ in 0 })  // not counted
        engine.deliver(
            makeBuffer(sampleRate: sampleRate, channels: 2, frames: frames, sample: tone(sampleRate: sampleRate)))
        engine.deliver(
            makeBuffer(sampleRate: sampleRate, channels: 2, frames: 256, sample: tone(sampleRate: sampleRate)))

        await sut.stop()
        _ = try await Self.drain(stream)

        #expect(log.events == [.captureFirstBuffer(frames: frames, sampleRate: sampleRate)])
    }

    @Test("a capture that received no buffer logs nothing")
    func noBufferLogsNothing() async throws {
        let log = RecordingDiagnostics()
        let sut = AVAudioEngineCaptureSource(engine: FakeEngine(), diagnostics: log)
        let stream = try await sut.start()

        await sut.stop()
        _ = try await Self.drain(stream)

        #expect(log.events.isEmpty)
    }

    @Test("each capture logs its own first buffer")
    func eachCaptureLogsItsOwn() async throws {
        let log = RecordingDiagnostics()
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log)
        for frames in [512, 1_024] {
            let stream = try await sut.start()
            engine.deliver(
                makeBuffer(sampleRate: 48_000, channels: 2, frames: frames, sample: tone(sampleRate: 48_000)))
            await sut.stop()
            _ = try await Self.drain(stream)
        }

        #expect(
            log.events == [
                .captureFirstBuffer(frames: 512, sampleRate: 48_000),
                .captureFirstBuffer(frames: 1_024, sampleRate: 48_000),
            ])
    }
}
