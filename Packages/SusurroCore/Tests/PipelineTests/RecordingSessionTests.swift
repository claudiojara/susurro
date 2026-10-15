import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing

@Suite("Recording session", .timeLimit(.minutes(1)))
struct RecordingSessionTests {
    private static func chunk(seconds: Double, value: Float = 0.1) -> AudioChunk {
        AudioChunk(samples: Array(repeating: value, count: Int(seconds * Double(AudioClip.sampleRate))))
    }

    /// The recording and the notice of a result that kept the audio. Records an issue for any other.
    private static func kept(_ result: RecordingResult) -> (VerifiedRecording, NoticeKind?)? {
        guard case .recorded(let recording, let notice) = result else {
            Issue.record("the audio was not kept: \(result)")
            return nil
        }
        return (recording, notice)
    }

    private struct Rig {
        let capture: FakeAudioCaptureSource
        let store: FakeRecordingStore
        let session: RecordingSession
        var events: AsyncStream<RecordingSession.Event>.Iterator

        init(
            capture: FakeAudioCaptureSource = FakeAudioCaptureSource(),
            store: FakeRecordingStore = FakeRecordingStore(),
            maximumDuration: Duration? = nil
        ) {
            self.capture = capture
            self.store = store
            session = RecordingSession(capture: capture, store: store, maximumDuration: maximumDuration)
            events = session.events.makeAsyncIterator()
        }

        /// Reads events until `target`, returning the ones before it.
        mutating func read(through target: RecordingSession.Event) async -> [RecordingSession.Event] {
            var seen: [RecordingSession.Event] = []
            while let event = await events.next() {
                if event == target { break }
                seen.append(event)
            }
            return seen
        }
    }

    // MARK: Readiness and incremental writes

    @Test("ready is signaled at the first buffer, which a slow device delivers 300 ms after the start")
    func readyAtFirstBuffer() async throws {
        let clock = ManualClock()
        var rig = Rig()
        try await rig.session.start()
        let capture = rig.capture
        let delivery = Task {
            try await clock.sleep(for: .milliseconds(300))
            capture.emit(Self.chunk(seconds: 0.1))
        }
        await clock.waitForSleeps(1)

        #expect(await rig.session.isReady == false)
        clock.advance(by: .milliseconds(300))
        try await delivery.value
        let first = await rig.events.next()

        #expect(first == .ready)
        #expect(await rig.session.isReady)
    }

    @Test("chunks reach the store while the recording goes on, before it is finished")
    func chunksAreWrittenIncrementally() async throws {
        let rig = Rig()
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 1))
        await rig.store.waitForAppended(samples: 16_000)

        #expect(rig.store.samples(of: rig.session.id).count == 16_000)
        rig.capture.emit(Self.chunk(seconds: 1))
        await rig.store.waitForAppended(samples: 32_000)
        #expect(rig.store.finished.isEmpty)

        let result = await rig.session.finish()
        guard let (recording, notice) = Self.kept(result) else { return }
        #expect(notice == nil)
        #expect(recording.id == rig.session.id)
        #expect(recording.duration == .seconds(2))
    }

    // MARK: Bounded memory

    @Test("a scripted ten-minute stream never holds more than 30 s of audio")
    func boundedMemory() async throws {
        let rig = Rig()
        try await rig.session.start()
        let chunksPerSecond = 10
        for _ in 0..<(600 * chunksPerSecond) { rig.capture.emit(Self.chunk(seconds: 0.1)) }
        await rig.store.waitForAppended(samples: 600 * AudioClip.sampleRate)

        let peak = await rig.session.peakBufferedDuration
        #expect(peak <= RecordingLimits.maximumBufferedAudio)
        #expect(peak > .zero)
        let result = await rig.session.finish()
        guard let (recording, _) = Self.kept(result) else { return }
        #expect(recording.duration == .seconds(600))
        #expect(rig.store.samples(of: rig.session.id).count == 600 * AudioClip.sampleRate)
    }

    // MARK: Minimum duration

    @Test("a 200 ms recording is discarded and its file deleted, and 300 ms is kept", arguments: [200, 299, 300, 450])
    func minimumDuration(milliseconds: Int) async throws {
        let rig = Rig()
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: Double(milliseconds) / 1000))
        let result = await rig.session.finish()

        if milliseconds >= 300 {
            #expect(Self.kept(result) != nil)
            #expect(rig.store.aborted.isEmpty)
        } else {
            #expect(result == .tooShort)
            #expect(rig.store.aborted == [rig.session.id])
        }
    }

    @Test("a submitted recording passes no minimum, so a short one is kept, and a recording with no audio is not")
    func noMinimumForASubmission() async throws {
        let rig = Rig()
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 0.2))
        let result = await rig.session.finish(minimumDuration: .zero)

        guard let (recording, _) = Self.kept(result) else { return }
        #expect(recording.duration == .milliseconds(200))
        #expect(rig.store.aborted.isEmpty)

        let empty = Rig()
        try await empty.session.start()
        #expect(await empty.session.finish(minimumDuration: .zero) == .failed(.capture("no audio was captured")))
    }

    // MARK: Store failures

    @Test("a write that fails gives a persistence failure and no recording")
    func writeFailure() async throws {
        let rig = Rig(store: FakeRecordingStore(.init(appendFailsFromCall: 2)))
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 1))
        rig.capture.emit(Self.chunk(seconds: 1))
        rig.capture.emit(Self.chunk(seconds: 1))
        let result = await rig.session.finish()

        #expect(result == .failed(.persistence))
        #expect(rig.store.finished.isEmpty)
        #expect(rig.store.aborted == [rig.session.id])
    }

    @Test("a file that cannot be finished or verified gives a persistence failure and no recording")
    func verificationFailure() async throws {
        let faults: [FakeRecordingStore.Faults] = [
            .init(finishError: .verificationFailed("unreadable")),
            .init(finishError: .verificationFailed("empty")),
            .init(finishError: .writeFailed("disk full")),
            .init(reportedSampleCount: 16_000),
        ]
        for fault in faults {
            let rig = Rig(store: FakeRecordingStore(fault))
            try await rig.session.start()
            rig.capture.emit(Self.chunk(seconds: 2))
            let result = await rig.session.finish()

            #expect(result == .failed(.persistence))
            #expect(rig.store.aborted == [rig.session.id])
        }
    }

    @Test("a store that refuses to begin fails the start with a persistence failure, and nothing records")
    func beginFailure() async {
        let rig = Rig(store: FakeRecordingStore(.init(beginFails: true)))

        await #expect(throws: RecordingFailure.persistence) { try await rig.session.start() }
        #expect(rig.capture.stopCount == rig.capture.startCount)
    }

    // MARK: Device failures

    @Test("no input device fails the start, before anything is recorded")
    func noInputDevice() async {
        let rig = Rig(capture: FakeAudioCaptureSource(startFailure: CaptureError.noInputDevice))

        await #expect(throws: CaptureError.noInputDevice) { try await rig.session.start() }
        #expect(rig.store.begun.isEmpty)
    }

    @Test("a device removed after 4 s completes with the 4 s stored and a disconnect notice")
    func deviceRemoved() async throws {
        var rig = Rig()
        try await rig.session.start()
        for _ in 0..<4 { rig.capture.emit(Self.chunk(seconds: 1)) }
        rig.capture.fail(CaptureError.deviceRemoved)
        _ = await rig.read(through: .deviceRemoved)
        let result = await rig.session.finish()

        guard let (recording, notice) = Self.kept(result) else { return }
        #expect(recording.duration == .seconds(4))
        #expect(notice == .deviceDisconnected)
        #expect(rig.store.samples(of: rig.session.id).count == 4 * AudioClip.sampleRate)
    }

    @Test("a capture that fails with no audio is a capture failure that names the error")
    func failureWithoutAudio() async throws {
        struct Broken: Error {}
        let rig = Rig()
        try await rig.session.start()
        rig.capture.fail(Broken())
        let result = await rig.session.finish()

        #expect(result == .failed(.capture(String(describing: Broken()))))
    }

    @Test("a capture that fails after some audio keeps the audio")
    func failureAfterAudio() async throws {
        struct Broken: Error {}
        let rig = Rig()
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 1))
        rig.capture.fail(Broken())
        let result = await rig.session.finish()

        guard let (recording, notice) = Self.kept(result) else { return }
        #expect(notice == nil)
        #expect(recording.duration == .seconds(1))
    }

    // MARK: Levels and limit

    @Test("a constant-amplitude chunk gives its amplitude as the level")
    func level() async throws {
        var rig = Rig()
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 0.1, value: 0.5))
        let seen = await rig.events.next()
        let level = await rig.events.next()

        #expect(seen == .ready)
        guard case .level(let rms)? = level else {
            Issue.record("no level: \(String(describing: level))")
            return
        }
        #expect(abs(rms - 0.5) < 0.0001)
    }

    @Test("audio past the maximum duration is dropped, and the limit is reported once")
    func maximumDuration() async throws {
        var rig = Rig(maximumDuration: .seconds(1))
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 0.6))
        rig.capture.emit(Self.chunk(seconds: 0.6))
        rig.capture.emit(Self.chunk(seconds: 0.6))
        _ = await rig.read(through: .limitReached)
        let result = await rig.session.finish()

        guard let (recording, notice) = Self.kept(result) else { return }
        #expect(notice == nil)
        #expect(recording.duration == .seconds(1))
    }

    @Test("the audio that is kept reaches the samples handler as it arrives, and the audio past the limit does not")
    func samplesHandler() async throws {
        let heard = Mutex<[Float]>([])
        let capture = FakeAudioCaptureSource()
        let session = RecordingSession(
            capture: capture, store: FakeRecordingStore(), maximumDuration: .seconds(1),
            samples: { samples in heard.withLock { $0 += samples } })
        var events = session.events.makeAsyncIterator()
        try await session.start()
        capture.emit(Self.chunk(seconds: 0.6, value: 0.1))
        capture.emit(Self.chunk(seconds: 0.6, value: 0.2))
        while let event = await events.next(), event != .limitReached {}

        #expect(heard.withLock { $0 } == Self.chunk(seconds: 0.6).samples + Self.chunk(seconds: 0.4, value: 0.2).samples)
        _ = await session.finish()
    }

    // MARK: Abort and the end of the events

    @Test("an aborted recording stops the capture and deletes the file")
    func abort() async throws {
        let rig = Rig()
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 1))
        await rig.store.waitForAppended(samples: 16_000)
        await rig.session.abort()

        #expect(rig.capture.stopCount == 1)
        #expect(rig.store.aborted == [rig.session.id])
    }

    @Test("the events end with the recording, so a reader of them never waits for good")
    func eventsEnd() async throws {
        var rig = Rig()
        try await rig.session.start()
        rig.capture.emit(Self.chunk(seconds: 1))
        _ = await rig.session.finish()

        let seen = await rig.read(through: .limitReached)
        #expect(seen.count == 2)
        #expect(seen.first == .ready)
    }
}
