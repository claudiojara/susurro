import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Skeleton hold-to-talk coordinator", .timeLimit(.minutes(1)))
struct SkeletonCoordinatorTests {
    private static let clip: [Float] = [0.1, 0.2, 0.3]
    private static let capSamples = 60 * 16_000
    /// Presses happen away from the timestamp origin, so a hold is measured from its own press.
    private static let pressTime = Duration.seconds(10)
    private static let transcribed: [PipelineState] = [.transcribing(progress: nil), .inserted, .idle]

    private struct Failure: Error {}

    /// Wires the coordinator to fakes and reads its published states. Tests call `handle` directly, so an ignored
    /// event is provably applied before the next step. One test goes through the hotkey source and `run()`.
    private struct Harness {
        let hotkeys = FakeHotkeySource()
        let capture: FakeAudioCaptureSource
        let recognizer: FakeRecognizer
        let inserter: FakeTextInserter
        let sleeper: FakeSleeper
        let sut: DictationCoordinator
        private var states: AsyncStream<PipelineState>.Iterator

        init(
            permissions: FakePermissionsChecker = FakePermissionsChecker(),
            capture: FakeAudioCaptureSource = FakeAudioCaptureSource(),
            recognizer: FakeRecognizer = FakeRecognizer(),
            inserter: FakeTextInserter = FakeTextInserter(),
            sleeper: FakeSleeper = FakeSleeper()
        ) async {
            self.capture = capture
            self.recognizer = recognizer
            self.inserter = inserter
            self.sleeper = sleeper
            let coordinator = DictationCoordinator(
                hotkeys: hotkeys,
                capture: capture,
                recognizer: recognizer,
                inserter: inserter,
                permissions: permissions,
                sleep: { try await sleeper.sleep($0) }
            )
            sut = coordinator
            states = coordinator.states.makeAsyncIterator()
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

        /// Presses, delivers one chunk, and waits for the recording state.
        mutating func startRecording(samples: [Float] = SkeletonCoordinatorTests.clip) async {
            await sut.handle(.down(at: SkeletonCoordinatorTests.pressTime))
            capture.emit(AudioChunk(samples: samples))
            _ = await read(through: .recording(.hold))
        }

        /// Releases after the given hold and reads the rest of the cycle.
        mutating func release(after milliseconds: Int = 1200) async -> [PipelineState] {
            await sut.handle(.up(at: SkeletonCoordinatorTests.pressTime + .milliseconds(milliseconds)))
            return await read(through: .idle)
        }
    }

    @Test("a held press records, transcribes the whole clip, and inserts the text")
    func heldPressIsInserted() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "hola mundo"))
        let sut = h.sut
        let loop = Task { await sut.run() }
        h.hotkeys.send(.down(at: Self.pressTime))
        h.capture.emit(AudioChunk(samples: [0.1, 0.2]))
        h.capture.emit(AudioChunk(samples: [0.3]))
        let recording = await h.read(through: .recording(.hold))
        h.hotkeys.send(.up(at: Self.pressTime + .milliseconds(1200)))
        let rest = await h.read(through: .idle)
        h.hotkeys.finish()
        await loop.value

        #expect(recording == [.starting, .recording(.hold)])
        #expect(rest == Self.transcribed)
        #expect(h.capture.startCount == 1)
        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.clip)])
        #expect(h.inserter.insertedTexts == ["hola mundo"])
    }

    @Test("a hold shorter than 300 ms is discarded, and 300 ms is kept", arguments: [0, 150, 299, 300, 1200])
    func holdThreshold(heldMilliseconds: Int) async {
        var h = await Harness()
        await h.startRecording()
        let states = await h.release(after: heldMilliseconds)
        let isKept = heldMilliseconds >= 300

        #expect(states == (isKept ? Self.transcribed : [.idle]))
        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips.count == (isKept ? 1 : 0))
        #expect(h.inserter.insertedTexts.count == (isKept ? 1 : 0))
    }

    @Test("a release before any audio arrived is a capture failure, not an empty transcription")
    func releaseWithoutAudio() async {
        var h = await Harness()
        await h.sut.handle(.down(at: Self.pressTime))
        let states = await h.release()

        #expect(states == [.starting, .error(.captureFailed), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    @Test("a microphone that is not granted starts no capture", arguments: [PermissionStatus.denied, .notDetermined])
    func microphoneNotGranted(status: PermissionStatus) async {
        var h = await Harness(permissions: FakePermissionsChecker([.microphone: status]))
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
        let loading = FakeRecognizer(
            readiness: [.loading(progress: 0.4), .loading(progress: 0.4), .loading(progress: 0.8), .ready],
            transcript: "hola"
        )
        var h = await Harness(recognizer: loading)
        await h.startRecording()
        let states = await h.release()

        let progress: [PipelineState] = [.transcribing(progress: 0.4), .transcribing(progress: 0.8)]
        #expect(states == [.transcribing(progress: nil)] + progress + Self.transcribed)
        let polls = Array(repeating: FakeRecognizer.Call.readiness, count: 4)
        #expect(h.recognizer.calls == polls + [.transcribe(AudioClip(samples: Self.clip))])
        #expect(h.sleeper.pauseCount == 2)
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

    @Test("audio delivered after stop returns is still part of the clip")
    func audioDeliveredAfterStop() async {
        var h = await Harness(capture: FakeAudioCaptureSource(onStop: .holdStreamOpen))
        await h.startRecording(samples: [0.1])
        let sut = h.sut
        let release = Task { await sut.handle(.up(at: Self.pressTime + .milliseconds(1200))) }
        await h.capture.stopped.wait()
        // Without the drain wait the coordinator moves on within a few scheduler turns; give it those turns.
        for _ in 0..<50 { await Task.yield() }
        h.capture.emit(AudioChunk(samples: [0.9]))
        h.capture.finish()
        await release.value

        #expect(await h.read(through: .idle) == Self.transcribed)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: [0.1, 0.9])])
    }

    @Test("a capture stream that fails mid-recording keeps the audio captured so far")
    func captureStreamFailure() async {
        var h = await Harness()
        await h.startRecording(samples: [0.1])
        h.capture.fail(CaptureError.noInputDevice)

        #expect(await h.release() == Self.transcribed)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: [0.1])])
    }

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

    @Test("a press while the dictation is being transcribed is ignored")
    func pressWhileProcessing() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "uno", gated: true))
        await h.startRecording()
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(1200)))
        _ = await h.read(through: .transcribing(progress: nil))
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        h.recognizer.releaseTranscription()

        #expect(await h.read(through: .idle) == [.inserted, .idle])
        #expect(h.capture.startCount == 1)
        #expect(h.inserter.insertedTexts == ["uno"])
    }

    @Test("a duplicate press while recording is ignored and does not restart the hold")
    func duplicatePressWhileRecording() async {
        var h = await Harness()
        await h.startRecording()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1100)))

        // A restarted hold would measure 100 ms and be discarded.
        #expect(await h.release() == Self.transcribed)
        #expect(h.capture.startCount == 1)
    }

    @Test("a recognizer stuck loading ends in an error, and a later press works")
    func recognizerStuckLoading() async {
        let recognizer = FakeRecognizer(readiness: [.loading(progress: 0.5)])
        var h = await Harness(recognizer: recognizer)
        await h.startRecording()
        let stuck = await h.release()
        recognizer.setReadiness(.ready)
        await h.startRecording()
        let recovered = await h.release()

        let timedOut: [PipelineState] = [.transcribing(progress: 0.5), .error(.timedOut(.readiness)), .idle]
        #expect(stuck == [.transcribing(progress: nil)] + timedOut)
        #expect(recovered == Self.transcribed)
    }

    @Test("a transcription that never finishes times out")
    func transcriptionTimeout() async {
        let sleeper = FakeSleeper(expiring: [SkeletonLimits.transcriptionTimeout])
        var h = await Harness(recognizer: FakeRecognizer(gated: true), sleeper: sleeper)
        await h.startRecording()

        #expect(await h.release() == [.transcribing(progress: nil), .error(.timedOut(.transcription)), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("an insertion that never finishes times out")
    func insertionTimeout() async {
        let sleeper = FakeSleeper(expiring: [SkeletonLimits.insertionTimeout])
        var h = await Harness(inserter: FakeTextInserter(gated: true), sleeper: sleeper)
        await h.startRecording()

        #expect(await h.release() == [.transcribing(progress: nil), .error(.timedOut(.insertion)), .idle])
    }

    @Test("a capture that never stops times out")
    func captureStopTimeout() async {
        let sleeper = FakeSleeper(expiring: [SkeletonLimits.captureStopTimeout])
        var h = await Harness(capture: FakeAudioCaptureSource(onStop: .hang), sleeper: sleeper)
        await h.startRecording()

        #expect(await h.release() == [.error(.timedOut(.capture)), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    @Test(
        "ending run() mid-recording stops the capture, inserts nothing, and ends the state stream",
        arguments: [true, false])
    func teardownMidRecording(cancelled: Bool) async {
        var h = await Harness()
        let sut = h.sut
        let loop = Task { await sut.run() }
        h.hotkeys.send(.down(at: Self.pressTime))
        h.capture.emit(AudioChunk(samples: Self.clip))
        _ = await h.read(through: .recording(.hold))
        if cancelled { loop.cancel() } else { h.hotkeys.finish() }
        await loop.value

        #expect(await h.read(through: .idle) == [.idle])
        #expect(await h.read(through: .starting).isEmpty)
        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("shutting down during transcription cancels it and inserts nothing")
    func shutdownWhileProcessing() async {
        var h = await Harness(recognizer: FakeRecognizer(gated: true))
        await h.startRecording()
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(1200)))
        _ = await h.read(through: .transcribing(progress: nil))
        await h.sut.shutdown()

        #expect(await h.read(through: .idle) == [.idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("shutting down while the capture is starting leaves the coordinator stopped", arguments: [false, true])
    func shutdownWhileStarting(startFails: Bool) async {
        let failure: (any Error)? = startFails ? CaptureError.noInputDevice : nil
        var h = await Harness(capture: FakeAudioCaptureSource(startFailure: failure, gatesStart: true))
        let sut = h.sut
        let press = Task { await sut.handle(.down(at: Self.pressTime)) }
        _ = await h.read(through: .starting)
        await sut.shutdown()
        h.capture.releaseStart()
        await press.value
        await sut.handle(.down(at: Self.pressTime))

        #expect(h.capture.startCount == 1)
        #expect(h.capture.stopCount == (startFails ? 0 : 1))
        #expect(await h.read(through: .idle) == [.idle])
    }

    @Test("a press while the capture is starting is ignored, and a release then finishes the dictation")
    func pressAndReleaseWhileStarting() async {
        var h = await Harness(capture: FakeAudioCaptureSource(gatesStart: true))
        let sut = h.sut
        let first = Task { await sut.handle(.down(at: Self.pressTime)) }
        _ = await h.read(through: .starting)
        await sut.handle(.down(at: Self.pressTime + .milliseconds(10)))
        await sut.handle(.up(at: Self.pressTime + .milliseconds(1200)))
        h.capture.emit(AudioChunk(samples: Self.clip))
        h.capture.releaseStart()
        await first.value

        #expect(await h.read(through: .idle) == Self.transcribed)
        #expect(h.capture.startCount == 1)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.clip)])
    }

    @Test("text left on the clipboard is a notice, not an insertion")
    func copiedToClipboard() async {
        let inserter = FakeTextInserter(outcome: .copiedToClipboard(.accessibilityMissing))
        var h = await Harness(inserter: inserter)
        await h.startRecording()
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .notice(.copiedToClipboard(.accessibilityMissing)), .idle])
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("two dictations in a row each get their own capture and clip")
    func sequentialDictations() async {
        var h = await Harness()
        await h.startRecording(samples: [0.1])
        _ = await h.release()
        await h.startRecording(samples: [0.7])
        let second = await h.release()

        #expect(second == Self.transcribed)
        #expect(h.capture.startCount == 2)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: [0.1]), AudioClip(samples: [0.7])])
    }

    @Test("a press while the text is being inserted is ignored")
    func pressWhileInserting() async {
        let inserter = FakeTextInserter(gated: true)
        var h = await Harness(inserter: inserter)
        await h.startRecording()
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(1200)))
        await inserter.entered.wait()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        inserter.releaseInsertion()

        #expect(await h.read(through: .idle) == Self.transcribed)
        #expect(h.capture.startCount == 1)
    }

    @Test("a recognizer that throws CancellationError ends in an error, and a later press works")
    func recognizerThrowsCancellation() async {
        var h = await Harness(recognizer: FakeRecognizer(failure: CancellationError()))
        await h.startRecording()
        let first = await h.release()
        await h.startRecording()  // never arrives if the coordinator is stuck processing
        let second = await h.release()

        let failed: [PipelineState] = [.transcribing(progress: nil), .error(.recognitionFailed), .idle]
        #expect(first == failed)
        #expect(second == failed)
        #expect(h.capture.startCount == 2)
    }

    @Test("a caller cancelled while the capture stops does not leave the coordinator stuck")
    func cancelledCallerDuringStop() async {
        var h = await Harness(capture: FakeAudioCaptureSource(onStop: .hang))
        await h.startRecording()
        let sut = h.sut
        let release = Task { await sut.handle(.up(at: Self.pressTime + .milliseconds(1200))) }
        await h.capture.stopped.wait()
        release.cancel()
        await release.value

        #expect(await h.read(through: .idle) == [.error(.captureFailed), .idle])
        await h.startRecording()
        #expect(h.capture.startCount == 2)
    }

    @Test("shutting down while the permissions are checked never starts the capture")
    func shutdownDuringPreconditions() async {
        let permissions = FakePermissionsChecker(gated: true)
        var h = await Harness(permissions: permissions)
        let sut = h.sut
        let press = Task { await sut.handle(.down(at: Self.pressTime)) }
        await permissions.entered.wait()
        await sut.shutdown()
        permissions.releaseStatus()
        await press.value

        #expect(h.capture.startCount == 0)
        #expect(await h.read(through: .idle).isEmpty)
    }

    @Test("shutdown from a cancelled task still stops the capture")
    func shutdownFromCancelledTask() async {
        var h = await Harness()
        await h.startRecording()
        let sut = h.sut
        let gate = Gate()
        let stopper = Task {
            await gate.wait()  // returns at once because the task is cancelled
            await sut.shutdown()
        }
        stopper.cancel()
        await stopper.value

        #expect(h.capture.stopCount == 1)
        #expect(await h.read(through: .idle) == [.idle])
    }

    @Test("reaching the 60 s clip cap finishes the recording and says so")
    func clipCapFinishesRecording() async {
        var h = await Harness()
        await h.sut.handle(.down(at: Self.pressTime))
        h.capture.emit(AudioChunk(samples: [Float](repeating: 0.5, count: Self.capSamples)))
        let states = await h.read(through: .idle)

        #expect(states == [.starting, .recording(.hold), .notice(.capReached)] + Self.transcribed)
        #expect(h.recognizer.transcribedClips.map(\.samples.count) == [Self.capSamples])
        #expect(h.capture.stopCount == 1)
    }

    @Test("one sample short of the cap keeps recording until the release")
    func justUnderTheCap() async {
        var h = await Harness()
        await h.startRecording(samples: [Float](repeating: 0.5, count: Self.capSamples - 1))

        #expect(await h.release(after: 61_000) == Self.transcribed)
        #expect(h.recognizer.transcribedClips.map(\.samples.count) == [Self.capSamples - 1])
    }
}
