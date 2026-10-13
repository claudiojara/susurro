import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing

@Suite("Skeleton hold-to-talk coordinator", .timeLimit(.minutes(1)))
struct SkeletonCoordinatorTests {
    private static let clip: [Float] = [0.1, 0.2, 0.3]
    private static let capSamples = 60 * 16_000

    private struct Failure: Error {}

    private final class SleepCounter: Sendable {
        private let count = Mutex(0)
        func record() { count.withLock { $0 += 1 } }
        var value: Int { count.withLock { $0 } }
    }

    /// Wires the coordinator to fakes and reads its published states. Tests call `handle` directly, so an ignored
    /// event is provably applied before the next step. One test goes through the hotkey source and `run()`.
    private struct Harness {
        let hotkeys = FakeHotkeySource()
        let capture: FakeAudioCaptureSource
        let recognizer: FakeRecognizer
        let inserter = FakeTextInserter()
        let sut: DictationCoordinator
        private var states: AsyncStream<PipelineState>.Iterator

        init(
            microphone: PermissionStatus = .granted,
            capture: FakeAudioCaptureSource = FakeAudioCaptureSource(),
            recognizer: FakeRecognizer = FakeRecognizer(),
            sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
        ) async {
            self.capture = capture
            self.recognizer = recognizer
            let coordinator = DictationCoordinator(
                hotkeys: hotkeys,
                capture: capture,
                recognizer: recognizer,
                inserter: inserter,
                permissions: FakePermissionsChecker([.microphone: microphone]),
                sleep: sleep
            )
            sut = coordinator
            states = await coordinator.states().makeAsyncIterator()
            _ = await states.next()  // the current state is replayed on subscription
        }

        /// Reads published states up to and including `target`.
        mutating func read(through target: PipelineState) async -> [PipelineState] {
            var seen: [PipelineState] = []
            while let state = await states.next() {
                seen.append(state)
                if state == target { break }
            }
            return seen
        }

        /// Presses at t=0, delivers one chunk, and waits for the recording state.
        mutating func startRecording(samples: [Float] = SkeletonCoordinatorTests.clip) async {
            await sut.handle(.down(at: .zero))
            capture.emit(AudioChunk(samples: samples))
            _ = await read(through: .recording(.hold))
        }

        /// Releases at the given time and reads the rest of the cycle.
        mutating func release(at milliseconds: Int = 1200) async -> [PipelineState] {
            await sut.handle(.up(at: .milliseconds(milliseconds)))
            return await read(through: .idle)
        }
    }

    // MARK: Hold-to-talk

    @Test("a held press records, transcribes the whole clip, and inserts the text")
    func heldPressIsInserted() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "hola mundo"))
        let sut = h.sut
        let loop = Task { await sut.run() }

        h.hotkeys.send(.down(at: .zero))
        h.capture.emit(AudioChunk(samples: [0.1, 0.2]))
        h.capture.emit(AudioChunk(samples: [0.3]))
        let recording = await h.read(through: .recording(.hold))
        h.hotkeys.send(.up(at: .milliseconds(1200)))
        let rest = await h.read(through: .idle)
        h.hotkeys.finish()
        await loop.value

        #expect(recording == [.starting, .recording(.hold)])
        #expect(rest == [.transcribing(progress: nil), .inserted, .idle])
        #expect(h.capture.startCount == 1)
        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.clip)])
        #expect(h.inserter.insertedTexts == ["hola mundo"])
    }

    @Test("a new subscriber starts from the current state")
    func subscriberReplaysCurrentState() async {
        var h = await Harness()
        await h.startRecording()
        var late = await h.sut.states().makeAsyncIterator()

        #expect(await late.next() == .recording(.hold))
    }

    // MARK: Minimum duration

    @Test("a release under 300 ms is discarded", arguments: [0, 150, 299])
    func shortReleaseIsDiscarded(heldMilliseconds: Int) async {
        var h = await Harness()
        await h.startRecording()

        let states = await h.release(at: heldMilliseconds)

        #expect(states == [.idle])
        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("a release at exactly 300 ms is kept")
    func thresholdReleaseIsKept() async {
        var h = await Harness()
        await h.startRecording()

        let states = await h.release(at: 300)

        #expect(states == [.transcribing(progress: nil), .inserted, .idle])
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.clip)])
    }

    @Test("a release before any audio arrived is a capture failure, not an empty transcription")
    func releaseWithoutAudio() async {
        var h = await Harness()
        await h.sut.handle(.down(at: .zero))

        let states = await h.release()

        #expect(states == [.starting, .error(.captureFailed), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    // MARK: Start preconditions

    @Test("a microphone that is not granted starts no capture", arguments: [PermissionStatus.denied, .notDetermined])
    func microphoneNotGranted(status: PermissionStatus) async {
        var h = await Harness(microphone: status)
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.microphoneNotGranted), .idle])
        #expect(h.capture.startCount == 0)
    }

    @Test("a recognizer that is not installed starts no capture")
    func recognizerNotInstalled() async {
        var h = await Harness(recognizer: FakeRecognizer(readiness: [.notInstalled]))
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.recognizerNotInstalled), .idle])
        #expect(h.capture.startCount == 0)
    }

    @Test("a recognizer that is loading records, and transcription waits for ready while showing progress")
    func loadingRecognizer() async {
        let sleeps = SleepCounter()
        let loading = FakeRecognizer(
            readiness: [.loading(progress: 0.4), .loading(progress: 0.4), .loading(progress: 0.8), .ready],
            transcript: "hola"
        )
        var h = await Harness(recognizer: loading, sleep: { _ in sleeps.record() })
        await h.startRecording()

        let states = await h.release()

        #expect(
            states == [
                .transcribing(progress: nil), .transcribing(progress: 0.4), .transcribing(progress: 0.8),
                .transcribing(progress: nil), .inserted, .idle,
            ])
        let polls = Array(repeating: FakeRecognizer.Call.readiness, count: 4)
        #expect(h.recognizer.calls == polls + [.transcribe(AudioClip(samples: Self.clip))])
        #expect(sleeps.value == 2)
        #expect(h.inserter.insertedTexts == ["hola"])
    }

    @Test("a model that disappears before transcription fails with the settings error")
    func modelRemovedWhileRecording() async {
        var h = await Harness(recognizer: FakeRecognizer(readiness: [.ready, .notInstalled]))
        await h.startRecording()

        #expect(await h.release() == [.transcribing(progress: nil), .error(.recognizerNotInstalled), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    @Test("a capture that fails to start reports an error and returns to idle")
    func captureStartFailure() async {
        var h = await Harness(capture: FakeAudioCaptureSource(startFailure: CaptureError.noInputDevice))
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.starting, .error(.captureFailed), .idle])
        #expect(h.capture.startCount == 1)
    }

    @Test("a capture stream that fails mid-recording keeps the audio captured so far")
    func captureStreamFailure() async {
        var h = await Harness()
        await h.startRecording(samples: [0.1])
        h.capture.fail(CaptureError.noInputDevice)

        #expect(await h.release() == [.transcribing(progress: nil), .inserted, .idle])
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: [0.1])])
    }

    // MARK: Transcription outcomes

    @Test("a blank transcript inserts nothing and reports no speech", arguments: ["", "   ", " \n\t "])
    func blankTranscript(text: String) async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: text))
        await h.startRecording()

        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .notice(.noSpeech), .idle])
        #expect(h.recognizer.transcribedClips.count == 1)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("a recognizer that throws reports an error and inserts nothing")
    func recognizerFailure() async {
        var h = await Harness(recognizer: FakeRecognizer(failure: Failure()))
        await h.startRecording()

        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .error(.recognitionFailed), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    // MARK: Ignored presses

    @Test("a press while the dictation is being transcribed is ignored")
    func pressWhileProcessing() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "uno", gated: true))
        await h.startRecording()
        await h.sut.handle(.up(at: .milliseconds(1200)))
        _ = await h.read(through: .transcribing(progress: nil))

        await h.sut.handle(.down(at: .milliseconds(1300)))
        h.recognizer.releaseTranscription()

        #expect(await h.read(through: .idle) == [.inserted, .idle])
        #expect(h.capture.startCount == 1)
        #expect(h.inserter.insertedTexts == ["uno"])
    }

    @Test("a duplicate press while recording is ignored and does not restart the hold")
    func duplicatePressWhileRecording() async {
        var h = await Harness()
        await h.startRecording()

        await h.sut.handle(.down(at: .milliseconds(1100)))

        // A restarted hold would measure 100 ms and be discarded.
        #expect(await h.release() == [.transcribing(progress: nil), .inserted, .idle])
        #expect(h.capture.startCount == 1)
    }

    // MARK: Clip cap

    @Test("reaching the 60 s clip cap finishes the recording and says so")
    func clipCapFinishesRecording() async {
        var h = await Harness()
        await h.sut.handle(.down(at: .zero))
        h.capture.emit(AudioChunk(samples: [Float](repeating: 0.5, count: Self.capSamples)))

        let states = await h.read(through: .idle)

        #expect(
            states == [
                .starting, .recording(.hold), .notice(.capReached), .transcribing(progress: nil), .inserted, .idle,
            ])
        #expect(h.recognizer.transcribedClips.map(\.samples.count) == [Self.capSamples])
        #expect(h.capture.stopCount == 1)
    }

    @Test("one sample short of the cap keeps recording until the release")
    func justUnderTheCap() async {
        var h = await Harness()
        await h.startRecording(samples: [Float](repeating: 0.5, count: Self.capSamples - 1))

        #expect(await h.release(at: 61_000) == [.transcribing(progress: nil), .inserted, .idle])
        #expect(h.recognizer.transcribedClips.map(\.samples.count) == [Self.capSamples - 1])
    }
}
