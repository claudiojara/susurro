import AVFoundation
import Domain
import Synchronization
import Testing

@testable import AudioIO

@Suite("AVAudioEngine capture source", .timeLimit(.minutes(1)))
struct AVAudioEngineCaptureSourceTests {
    private struct EngineFailure: Error, Equatable {}

    /// An input device scripted by the test. It records what the source asks of it, in order, and delivers buffers
    /// through the installed tap the way the real engine does: only while a tap is installed.
    private final class FakeEngine: EngineProviding {
        private struct State {
            var tap: (@Sendable (AVAudioPCMBuffer) -> Void)?
            var calls: [String] = []
        }

        private let format: AVAudioFormat?
        private let startFailure: (any Error)?
        private let state = Mutex(State())

        init(
            format: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
            startFailure: (any Error)? = nil
        ) {
            self.format = format
            self.startFailure = startFailure
        }

        var calls: [String] { state.withLock { $0.calls } }

        func deliver(_ buffer: AVAudioPCMBuffer) {
            let tap = state.withLock { $0.tap }
            tap?(buffer)
        }

        func inputFormat() -> AVAudioFormat? { format }

        func installTap(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
            state.withLock {
                $0.calls.append("installTap")
                $0.tap = handler
            }
        }

        func removeTap() {
            state.withLock {
                $0.calls.append("removeTap")
                $0.tap = nil
            }
        }

        func start() throws {
            state.withLock { $0.calls.append("start") }
            if let startFailure { throw startFailure }
        }

        func stop() { state.withLock { $0.calls.append("stop") } }
    }

    /// 100 ms of a 48 kHz stereo device: 1600 samples once converted.
    private static func deviceBuffer(startingAt start: Int = 0) -> AVAudioPCMBuffer {
        makeBuffer(sampleRate: 48_000, channels: 2, frames: 4_800, startingAt: start, sample: tone(sampleRate: 48_000))
    }

    /// A 100 ms device buffer (4800 frames, two channels) is at most 1600 samples once converted. The first chunk of a
    /// capture is shorter while the resampler primes, and the rest of its output arrives when the capture ends.
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

    @Test("the first real buffer yields the first chunk, converted to 16 kHz mono")
    func firstBufferIsTheFirstChunk() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        var chunks = try await sut.start().makeAsyncIterator()

        engine.deliver(Self.deviceBuffer())

        #expect(Self.isConvertedBuffer(try await chunks.next()?.samples.count))
    }

    @Test("starting alone signals nothing: a capture stopped before any buffer ends with no chunk")
    func startIsNotReadiness() async throws {
        let sut = AVAudioEngineCaptureSource(engine: FakeEngine())
        let stream = try await sut.start()

        await sut.stop()

        #expect(try await Self.drain(stream).isEmpty)
    }

    @Test("an empty buffer is not a real buffer, so it signals nothing")
    func emptyBufferIsIgnored() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        var chunks = try await sut.start().makeAsyncIterator()
        let empty = Self.deviceBuffer()
        empty.frameLength = 0

        engine.deliver(empty)
        engine.deliver(Self.deviceBuffer())

        #expect(Self.isConvertedBuffer(try await chunks.next()?.samples.count))
    }

    @Test("stop delivers every captured chunk, finishes the stream, and removes the tap")
    func stopFinishesAndRemovesTap() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        let stream = try await sut.start()
        engine.deliver(Self.deviceBuffer())
        engine.deliver(Self.deviceBuffer(startingAt: 4_800))

        await sut.stop()

        let chunks = try await Self.drain(stream)
        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { Self.isConvertedBuffer($0.samples.count) })
        #expect(engine.calls == ["installTap", "start", "removeTap", "stop"])
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
        #expect(Self.isConvertedBuffer(try await second.next()?.samples.count))
        #expect(engine.calls == ["installTap", "start", "removeTap", "stop", "installTap", "start"])
    }

    @Test("an engine that fails to start throws its error and leaves nothing installed")
    func engineStartFailure() async {
        let engine = FakeEngine(startFailure: EngineFailure())
        let sut = AVAudioEngineCaptureSource(engine: engine)

        await #expect(throws: EngineFailure()) { try await sut.start() }

        #expect(engine.calls == ["installTap", "start", "removeTap", "stop"])
    }

    @Test("a buffer in another format than the device's ends the stream with the conversion error")
    func formatChangeFailsTheStream() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)
        var chunks = try await sut.start().makeAsyncIterator()

        engine.deliver(Self.deviceBuffer())
        engine.deliver(makeBuffer(sampleRate: 44_100, channels: 1, frames: 441) { _, _ in 0.5 })
        engine.deliver(Self.deviceBuffer(startingAt: 4_800))

        #expect(Self.isConvertedBuffer(try await chunks.next()?.samples.count))
        await #expect(throws: FormatConversionError.formatChanged) { try await chunks.next() }
        #expect(try await chunks.next() == nil)
    }
}
