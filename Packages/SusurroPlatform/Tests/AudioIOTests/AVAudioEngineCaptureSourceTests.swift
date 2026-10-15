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
        case useDevice(UInt32)
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
            var format: AVAudioFormat?
            var startFailures: [any Error]
        }

        /// Opened when the engine is stopped, so tests can wait for a teardown the source starts on its own.
        let stopped = Gate()
        private let deviceFailure: (any Error)?
        private let state: Mutex<State>

        /// - Parameter startFailures: What each call to `start` throws, in order, before it starts succeeding.
        init(
            format: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
            startFailures: [any Error] = [], deviceFailure: (any Error)? = nil
        ) {
            state = Mutex(State(format: format, startFailures: startFailures))
            self.deviceFailure = deviceFailure
        }

        /// The device's format, which a route switch changes (a Bluetooth headset going into call mode).
        var format: AVAudioFormat? {
            get { state.withLock { $0.format } }
            set { state.withLock { $0.format = newValue } }
        }

        func useInputDevice(_ id: UInt32) throws {
            state.withLock { $0.calls.append(.useDevice(id)) }
            if let deviceFailure { throw deviceFailure }
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

        var isRunning: Bool { state.withLock { $0.isRunning } }

        /// Makes the next calls to `start` throw these, in order.
        func failNextStarts(_ failures: [any Error]) {
            state.withLock { $0.startFailures = failures }
        }

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
            let failure: (any Error)? = state.withLock {
                $0.calls.append(.start)
                return $0.startFailures.isEmpty ? nil : $0.startFailures.removeFirst()
            }
            if let failure { throw failure }
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

    private static let noSleep: @Sendable (Duration) async throws -> Void = { _ in }

    private static func engineFailed(_ stage: String) -> DiagnosticEvent {
        let error = EngineFailure() as NSError
        return .captureEngineFailed(stage: stage, domain: error.domain, code: error.code)
    }

    /// 100 ms of a Bluetooth headset in its call mode: 24 kHz mono.
    private static func headsetBuffer(startingAt start: Int = 0) -> AVAudioPCMBuffer {
        makeBuffer(sampleRate: 24_000, channels: 1, frames: 2_400, startingAt: start, sample: tone(sampleRate: 24_000))
    }

    /// Waits for the source to restart the engine on its own, which it does on its actor after a configuration change.
    private static func waitUntilRunning(_ engine: FakeEngine, starts: Int) async throws {
        for _ in 0..<1_000 {
            if engine.isRunning, engine.calls.count(where: { $0 == .start }) >= starts { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("The engine was not restarted.")
    }

    /// Reads the stream to its end and returns what it delivered and the error it ended with, if any.
    private static func drainUntilFailure(
        _ stream: AsyncThrowingStream<AudioChunk, Error>
    ) async -> ([AudioChunk], (any Error)?) {
        var chunks: [AudioChunk] = []
        do {
            for try await chunk in stream { chunks.append(chunk) }
            return (chunks, nil)
        } catch {
            return (chunks, error)
        }
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

    @Test("an engine that fails to start twice throws its error, logs both failures, and leaves nothing installed")
    func engineStartFailure() async {
        let log = RecordingDiagnostics()
        let engine = FakeEngine(startFailures: [EngineFailure(), EngineFailure()])
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log, sleep: Self.noSleep)

        await #expect(throws: EngineFailure()) { try await sut.start() }

        #expect(engine.calls == [.installTap, .start, .removeTap, .stop, .installTap, .start, .removeTap, .stop])
        #expect(!engine.isRunning)
        #expect(log.events == [Self.engineFailed("start"), Self.engineFailed("start")])
    }

    @Test("an engine that fails to start once, as after a Bluetooth route change, is retried after a pause")
    func engineStartRetried() async throws {
        let log = RecordingDiagnostics()
        let pauses = Mutex<[Duration]>([])
        let engine = FakeEngine(startFailures: [EngineFailure()])
        let sut = AVAudioEngineCaptureSource(
            engine: engine, diagnostics: log, inputDevice: { 42 },
            sleep: { duration in pauses.withLock { $0.append(duration) } })
        var chunks = try await sut.start().makeAsyncIterator()

        engine.deliver(Self.deviceBuffer())

        let chunk = try #require(try await chunks.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
        #expect(pauses.withLock { $0 } == [AVAudioEngineCaptureSource.retryDelay])
        // The retry starts over on a fresh engine: the device is chosen again and its format read again.
        #expect(
            engine.calls == [
                .useDevice(42), .installTap, .start, .removeTap, .stop, .useDevice(42), .installTap, .start,
            ])
        #expect(log.events == [Self.engineFailed("start")])
    }

    @Test("a stop during the pause before the retry abandons the start, and nothing is left running")
    func stopDuringStartRetry() async throws {
        let paused = Gate()
        let resume = Gate()
        let engine = FakeEngine(startFailures: [EngineFailure()])
        let sut = AVAudioEngineCaptureSource(
            engine: engine,
            sleep: { _ in
                paused.open()
                await resume.wait()
            })
        let starting = Task { try await sut.start() }
        await paused.wait()

        await sut.stop()
        resume.open()

        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
        #expect(!engine.isRunning)
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

    @Test(
        "a configuration change right after the start, as a Bluetooth headset switching to its call mode makes, restarts the capture in the new format"
    )
    func configurationChangeAtStartRestarts() async throws {
        let log = RecordingDiagnostics()
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log, inputDevice: { 42 }, sleep: Self.noSleep)
        var chunks = try await sut.start().makeAsyncIterator()
        let headset = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)

        engine.format = headset
        engine.signalConfigurationChange()
        try await Self.waitUntilRunning(engine, starts: 2)
        engine.deliver(Self.headsetBuffer())

        let chunk = try #require(try await chunks.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
        #expect(engine.tapFormat == headset)
        #expect(
            engine.calls == [
                .useDevice(42), .installTap, .start, .removeTap, .stop, .useDevice(42), .installTap, .start,
            ])
        #expect(log.events == [.captureReconfigured(sampleRate: 24_000, channels: 1)])
    }

    @Test("a configuration change mid-recording keeps what was captured before it, and the audio after it")
    func configurationChangeMidRecordingKeepsAll() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, sleep: Self.noSleep)
        let stream = try await sut.start()
        for buffer in tapBuffers(sampleRate: 48_000, count: 10, frames: 4_800, sample: tone(sampleRate: 48_000)) {
            engine.deliver(buffer)
        }

        engine.format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)
        engine.signalConfigurationChange()
        try await Self.waitUntilRunning(engine, starts: 2)
        for index in 0..<10 { engine.deliver(Self.headsetBuffer(startingAt: index * 2_400)) }
        await sut.stop()

        // One second before the change and one after, each converted whole, tail included.
        let total = try await Self.drain(stream).reduce(0) { $0 + $1.samples.count }
        #expect(abs(total - 32_000) <= 2)
    }

    @Test("a configuration change that leaves no input device delivers what was captured, then ends as removed")
    func configurationChangeWithoutDeviceEnds() async throws {
        let log = RecordingDiagnostics()
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log, sleep: Self.noSleep)
        let stream = try await sut.start()
        engine.deliver(Self.deviceBuffer())

        engine.format = nil
        engine.signalConfigurationChange()

        let (chunks, failure) = await Self.drainUntilFailure(stream)
        #expect(Self.isConvertedBuffer(chunks.first?.samples.count))
        #expect(failure as? CaptureError == .deviceRemoved)
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
        #expect(log.events.contains(.captureLost(reason: "noInputDevice")))
        await sut.stop()
        #expect(engine.calls == [.installTap, .start, .removeTap, .stop])
    }

    @Test("a restart that fails to start twice ends the capture as a removed device, after what was captured")
    func restartFailureEnds() async throws {
        let log = RecordingDiagnostics()
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log, sleep: Self.noSleep)
        let stream = try await sut.start()
        engine.deliver(Self.deviceBuffer())

        engine.failNextStarts([EngineFailure(), EngineFailure()])
        engine.signalConfigurationChange()

        let (chunks, failure) = await Self.drainUntilFailure(stream)
        #expect(!chunks.isEmpty)
        #expect(failure as? CaptureError == .deviceRemoved)
        #expect(!engine.isRunning)
        #expect(
            log.events.filter { $0 != .captureFirstBuffer(frames: 4_800, sampleRate: 48_000) } == [
                Self.engineFailed("restart"), Self.engineFailed("restart"), .captureLost(reason: "restartFailed"),
            ])
    }

    @Test("a restart whose first start fails is retried once, and the capture goes on")
    func restartRetried() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, sleep: Self.noSleep)
        var chunks = try await sut.start().makeAsyncIterator()

        engine.failNextStarts([EngineFailure()])
        engine.signalConfigurationChange()
        try await Self.waitUntilRunning(engine, starts: 3)
        engine.deliver(Self.deviceBuffer())

        let chunk = try #require(try await chunks.next())
        #expect(Self.isConvertedBuffer(chunk.samples.count))
    }

    @Test("configuration changes that keep coming end the capture once the restarts run out")
    func restartLimit() async throws {
        let log = RecordingDiagnostics()
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log, sleep: Self.noSleep)
        let stream = try await sut.start()
        let limit = AVAudioEngineCaptureSource.maximumRestarts
        for restart in 1...limit {
            engine.signalConfigurationChange()
            try await Self.waitUntilRunning(engine, starts: restart + 1)
        }

        engine.signalConfigurationChange()

        let (chunks, failure) = await Self.drainUntilFailure(stream)
        #expect(chunks.isEmpty)
        #expect(failure as? CaptureError == .deviceRemoved)
        #expect(log.events.last == .captureLost(reason: "restartLimit"))
        #expect(!engine.isRunning)
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

    @Test("the chosen microphone is selected on the engine before its format is read and the tap installed")
    func chosenDevice() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine, inputDevice: { 42 })

        _ = try await sut.start()

        #expect(engine.calls.prefix(2) == [.useDevice(42), .installTap])
    }

    @Test("with no chosen microphone the engine keeps the system default")
    func systemDefaultDevice() async throws {
        let engine = FakeEngine()
        let sut = AVAudioEngineCaptureSource(engine: engine)

        _ = try await sut.start()

        #expect(!engine.calls.contains { if case .useDevice = $0 { true } else { false } })
    }

    @Test("a microphone that cannot be selected is logged, and the capture goes on with the system default")
    func deviceSelectionFails() async throws {
        let log = RecordingDiagnostics()
        let engine = FakeEngine(deviceFailure: InputDeviceError(status: -50))
        let sut = AVAudioEngineCaptureSource(engine: engine, diagnostics: log, inputDevice: { 7 })

        _ = try await sut.start()

        #expect(engine.calls.contains(.start))
        #expect(log.events == [.microphoneSelectionFailed(status: -50)])
    }
}
