import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Dictation coordinator", .timeLimit(.minutes(1)))
struct DictationCoordinatorTests {
    /// A second of audio: a recording shorter than 300 ms is discarded by the recording itself.
    static let clip = audio(0.1)
    static func audio(_ value: Float, seconds: Double = 1) -> [Float] {
        [Float](repeating: value, count: Int(seconds * Double(AudioClip.sampleRate)))
    }
    /// A short recording cap, so that a test reaches it without holding minutes of audio.
    static let cap = Duration.seconds(2)
    static let capSamples = 2 * AudioClip.sampleRate
    /// Presses happen away from the timestamp origin, so a hold is measured from its own press.
    static let pressTime = Duration.seconds(10)
    static let transcribed: [PipelineState] = [.transcribing(progress: nil), .inserted, .idle]

    private struct Failure: Error {}
    private static let noInputDevice = String(describing: CaptureError.noInputDevice)

    typealias Harness = CoordinatorHarness

    @Test("a held press records, transcribes the whole clip, and inserts the text")
    func heldPressIsInserted() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "hola mundo"))
        let sut = h.sut
        let loop = Task { await sut.run() }
        h.hotkeys.send(.down(at: Self.pressTime))
        h.capture.emit(AudioChunk(samples: Array(Self.clip[..<8_000])))
        h.capture.emit(AudioChunk(samples: Array(Self.clip[8_000...])))
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

        #expect(states == [.starting, .error(.captureFailed("no audio was captured")), .idle])
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
        let recognizer = FakeRecognizer(readiness: [.notInstalled])
        var h = await Harness(recognizer: recognizer)
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.recognizerNotInstalled), .idle])
        #expect(h.capture.startCount == 0)
        #expect(recognizer.calls == [.readiness])  // nothing to prepare: the way out is in settings
    }

    @Test("a recognizer that is loading records, and transcription waits for ready while showing progress")
    func loadingRecognizer() async {
        let loading = FakeRecognizer(readiness: [.loading(progress: 0.4)], transcript: "hola")
        let sleeper = FakeSleeper(blocksPauses: true)
        var h = await Harness(recognizer: loading, sleeper: sleeper)
        await h.startRecording()  // a model that is loading does not stop the recording
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(1200)))
        let waiting = await h.read(through: .transcribing(progress: 0.4))

        // The state follows the model: the dictation waits, showing the progress, and nothing is transcribed yet.
        #expect(waiting == [.transcribing(progress: nil), .transcribing(progress: 0.4)])
        #expect(loading.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
        loading.setReadiness(.ready)
        sleeper.fire(DictationLimits.readinessPollInterval)

        #expect(await h.read(through: .idle) == Self.transcribed)
        #expect(loading.transcribedClips == [AudioClip(samples: Self.clip)])
        #expect(h.inserter.insertedTexts == ["hola"])
    }

    @Test(
        "a cloud provider that is not turned on, or has no key, starts no capture and says what is missing",
        arguments: [(false, ProviderBlocker.notEnabled), (true, .missingKey)]
    )
    func cloudProviderNotUsable(enabled: Bool, blocker: ProviderBlocker) async {
        let cloud = FakeRecognizer(id: ASRProviderID("cloud-fake"), locality: .cloud)
        let settings = InMemorySettingsStore()
        settings.set(enabled, for: RecognitionSettings.cloudEnabled(for: cloud.id))
        var h = await Harness(recognizer: cloud, settings: settings)
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.providerNotUsable(blocker)), .idle])
        #expect(h.capture.startCount == 0)
        #expect(cloud.calls == [])
    }

    @Test("a recognizer whose load failed starts no capture, asks to try again, and is prepared again")
    func unavailableRecognizer() async {
        let recognizer = FakeRecognizer(readiness: [.unavailable("no network", retryable: true)])
        var h = await Harness(recognizer: recognizer)
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.recognizerUnavailable("no network", retryable: true)), .idle])
        #expect(h.capture.startCount == 0)
        #expect(recognizer.calls == [.readiness, .prepare, .readiness])
    }

    @Test("whether a failed load can be retried reaches the error", arguments: [true, false])
    func retryabilityReachesTheError(retryable: Bool) async {
        var h = await Harness(recognizer: FakeRecognizer(readiness: [.unavailable("why", retryable: retryable)]))
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.recognizerUnavailable("why", retryable: retryable)), .idle])
    }

    @Test("the error comes from the readiness read after prepare, not from the one before it")
    func freshReadinessDecidesTheError() async {
        let recognizer = FakeRecognizer(readiness: [
            .unavailable("stale", retryable: true), .unavailable("fresh", retryable: false),
        ])
        var h = await Harness(recognizer: recognizer)
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.recognizerUnavailable("fresh", retryable: false)), .idle])
    }

    @Test("a press prepares a recognizer that was never prepared, and the clip is transcribed")
    func neverPreparedRecognizer() async {
        let recognizer = FakeRecognizer(readiness: [.loading(progress: 0)], transcript: "hola", readyAfterPrepare: true)
        var h = await Harness(recognizer: recognizer)
        await h.startRecording()
        let states = await h.release()

        #expect(states == Self.transcribed)
        let calls: [FakeRecognizer.Call] = [.readiness, .prepare, .readiness, .readiness]
        #expect(recognizer.calls == calls + [.transcribe(AudioClip(samples: Self.clip))])
        #expect(h.inserter.insertedTexts == ["hola"])
    }

    @Test("a recognizer that is ready is not prepared on a press")
    func readyRecognizerIsNotPrepared() async {
        var h = await Harness()
        await h.startRecording()
        _ = await h.release()

        #expect(h.recognizer.calls == [.readiness, .readiness, .transcribe(AudioClip(samples: Self.clip))])
    }

    @Test("a prepare that never returns times out the press and starts no capture")
    func prepareTimeout() async {
        let recognizer = FakeRecognizer(readiness: [.loading(progress: 0)], gatedPrepare: true)
        let sleeper = FakeSleeper(expiring: [DictationLimits.prepareTimeout])
        var h = await Harness(recognizer: recognizer, sleeper: sleeper)
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.error(.timedOut(.readiness)), .idle])
        #expect(h.capture.startCount == 0)
    }

    @Test(
        "a model that fails to load while the clip waits ends in the unavailable error, and the press that follows works",
        arguments: [true, false]
    )
    func modelFailsWhileWaiting(retryable: Bool) async {
        let recognizer = FakeRecognizer(readiness: [
            .loading(progress: 0.5), .loading(progress: 0.6), .loading(progress: 0.7),
            .unavailable("disk full", retryable: retryable),
        ])
        var h = await Harness(recognizer: recognizer)
        await h.startRecording()
        let failed = await h.release()
        recognizer.setReadiness(.ready)
        await h.startRecording()
        let recovered = await h.release()

        let progress: [PipelineState] = [.transcribing(progress: 0.7)]
        let error: [PipelineState] = [.error(.recognizerUnavailable("disk full", retryable: retryable)), .idle]
        #expect(failed == [.transcribing(progress: nil)] + progress + error)
        #expect(recovered == Self.transcribed)
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

        #expect(await h.read(through: .idle) == [.starting, .error(.captureFailed(Self.noInputDevice)), .idle])
        #expect(h.capture.startCount == 1)
    }

    @Test("audio delivered after stop returns is still part of the clip")
    func audioDeliveredAfterStop() async {
        var h = await Harness(capture: FakeAudioCaptureSource(onStop: .holdStreamOpen))
        await h.startRecording(samples: Self.audio(0.1))
        let sut = h.sut
        let release = Task { await sut.handle(.up(at: Self.pressTime + .milliseconds(1200))) }
        await h.capture.stopped.wait()
        // Without the drain wait the coordinator moves on within a few scheduler turns; give it those turns.
        for _ in 0..<50 { await Task.yield() }
        h.capture.emit(AudioChunk(samples: Self.audio(0.9, seconds: 0.5)))
        h.capture.finish()
        await release.value

        #expect(await h.read(through: .idle) == Self.transcribed)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.audio(0.1) + Self.audio(0.9, seconds: 0.5))])
    }

    @Test("a capture stream that fails mid-recording keeps the audio captured so far")
    func captureStreamFailure() async {
        var h = await Harness()
        await h.startRecording(samples: Self.audio(0.1))
        h.capture.fail(Failure())
        let states = await h.release()

        #expect(states == Self.transcribed)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.audio(0.1))])
    }

    @Test("a device removed mid-recording is transcribed at once with a notice, and the text waits for the release")
    func deviceRemovedMidRecording() async {
        var h = await Harness()
        await h.startRecording(samples: Self.audio(0.1, seconds: 1.5))
        h.capture.fail(CaptureError.deviceRemoved)
        let started = await h.read(through: .transcribing(progress: nil))
        let rest = await h.release(after: 5_000)

        #expect(started == [.notice(.deviceDisconnected), .transcribing(progress: nil)])
        #expect(rest == [.inserted, .idle])
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.audio(0.1, seconds: 1.5))])
    }

    @Test("a recording is written to the store while it is captured, and the store holds it after the dictation")
    func recordingIsInTheStore() async {
        var h = await Harness()
        await h.startRecording()
        _ = await h.release()

        #expect(h.recordings.begun.count == 1)
        #expect(h.recordings.finished == h.recordings.begun)
        #expect(h.recordings.samples(of: h.recordings.begun[0]) == Self.clip)
    }

    @Test("a store that cannot write ends the dictation in a persistence error, and the recognizer is never invoked")
    func storeFailure() async {
        let recordings = FakeRecordingStore(.init(appendFailsFromCall: 1))
        var h = await Harness(recordings: recordings)
        await h.startRecording()
        let states = await h.release()

        #expect(states == [.error(.persistenceFailed("the recording could not be saved")), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("a hold that is too short deletes the file it began")
    func shortHoldDeletesTheFile() async {
        var h = await Harness()
        await h.startRecording()
        _ = await h.release(after: 150)

        #expect(h.recordings.aborted == h.recordings.begun)
        #expect(h.recordings.finished.isEmpty)
    }

    @Test("a capture stream that fails before any audio reports its error")
    func captureStreamFailureBeforeAudio() async {
        var h = await Harness()
        await h.sut.handle(.down(at: Self.pressTime))
        h.capture.fail(CaptureError.noInputDevice)

        #expect(await h.release() == [.starting, .error(.captureFailed(Self.noInputDevice)), .idle])
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

        #expect(
            states == [.transcribing(progress: nil), .error(.recognitionFailed(String(describing: Failure()))), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("the default recording cap is ten minutes")
    func defaultCap() {
        #expect(DictationLimits.recordingCap == .seconds(600))
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

    // MARK: Readiness wait

    private static let stallPolls = Int(DictationLimits.readinessStallTimeout / DictationLimits.readinessPollInterval)
    private static let hardCapPolls = Int(DictationLimits.readinessHardCap / DictationLimits.readinessPollInterval)

    /// Readiness whose progress differs on every poll.
    private static func advancing(_ polls: Int) -> [RecognizerReadiness] {
        (0..<polls).map { .loading(progress: Double($0) / Double(polls + 1)) }
    }

    /// Readiness that sits at one progress for a number of polls.
    private static func plateau(_ progress: Double, polls: Int) -> [RecognizerReadiness] {
        Array(repeating: .loading(progress: progress), count: polls)
    }

    @Test("progress that keeps advancing outlasts the stall budget, and the clip is still transcribed")
    func advancingProgressOutlastsTheStallBudget() async {
        let loading = Self.advancing(Self.stallPolls + 100)
        let recognizer = FakeRecognizer(readiness: loading + [.ready], transcript: "hola")
        var h = await Harness(recognizer: recognizer)
        await h.startRecording()
        let states = await h.release()

        #expect(Array(states.suffix(3)) == Self.transcribed)
        #expect(h.sleeper.pauseCount == Self.stallPolls + 98)
        #expect(recognizer.transcribedClips == [AudioClip(samples: Self.clip)])
        #expect(h.inserter.insertedTexts == ["hola"])
    }

    @Test("plateaus shorter than the stall budget do not add up, like the compile that sits at one value")
    func plateausDoNotAddUp() async {
        // The first load of the app's speech model sits at 0.5 for about 30 s while Core ML compiles it.
        let compile = Self.stallPolls / 2
        let loading = [0.1, 0.5, 0.9].flatMap { Self.plateau($0, polls: compile) }
        var h = await Harness(recognizer: FakeRecognizer(readiness: loading + [.ready]))
        await h.startRecording()
        let states = await h.release()

        #expect(Array(states.suffix(3)) == Self.transcribed)
        #expect(h.sleeper.pauseCount > Self.stallPolls)
    }

    @Test("progress that stops advancing ends in an error after the stall budget")
    func stalledProgressGivesUp() async {
        let readiness = Self.advancing(10) + [.loading(progress: 0.9)]
        var h = await Harness(recognizer: FakeRecognizer(readiness: readiness))
        await h.startRecording()
        let states = await h.release()

        #expect(Array(states.suffix(2)) == [.error(.timedOut(.readiness)), .idle])
        #expect(h.sleeper.pauseCount == 8 + Self.stallPolls)
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    @Test("progress that never stops advancing still ends in an error at the hard cap")
    func hardCapEndsTheWait() async {
        var h = await Harness(recognizer: FakeRecognizer(readiness: Self.advancing(Self.hardCapPolls + 500)))
        await h.startRecording()
        let states = await h.release()

        #expect(Array(states.suffix(2)) == [.error(.timedOut(.readiness)), .idle])
        #expect(h.sleeper.pauseCount == Self.hardCapPolls)
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    @Test("a transcription that never finishes times out")
    func transcriptionTimeout() async {
        let sleeper = FakeSleeper(expiring: [DictationLimits.transcriptionTimeout])
        var h = await Harness(recognizer: FakeRecognizer(gated: true), sleeper: sleeper)
        await h.startRecording()

        #expect(await h.release() == [.transcribing(progress: nil), .error(.timedOut(.transcription)), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("an insertion that never finishes times out")
    func insertionTimeout() async {
        let sleeper = FakeSleeper(expiring: [DictationLimits.insertionTimeout])
        var h = await Harness(inserter: FakeTextInserter(gated: true), sleeper: sleeper)
        await h.startRecording()

        #expect(await h.release() == [.transcribing(progress: nil), .error(.timedOut(.insertion)), .idle])
    }

    @Test("a capture that never stops times out")
    func captureStopTimeout() async {
        let sleeper = FakeSleeper(expiring: [DictationLimits.captureStopTimeout])
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

    @Test(
        "Accessibility missing still records: only the paste suffers, so the text goes to the clipboard with a notice",
        arguments: [PermissionStatus.denied, .notDetermined]
    )
    func accessibilityMissingStillRecords(status: PermissionStatus) async {
        let permissions = FakePermissionsChecker([.microphone: .granted, .accessibility: status])
        let inserter = FakeTextInserter(outcome: .copiedToClipboard(.accessibilityMissing))
        var h = await Harness(permissions: permissions, inserter: inserter)
        await h.startRecording()
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .notice(.copiedToClipboard(.accessibilityMissing)), .idle])
        #expect(h.capture.startCount == 1)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: Self.clip)])
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test(
        "text that is neither inserted nor on the clipboard is an error, not a notice",
        arguments: [NotInsertedReason.clipboardChanged, .clipboardWriteFailed]
    )
    func notInserted(reason: NotInsertedReason) async {
        let inserter = FakeTextInserter(outcome: .notInserted(reason))
        var h = await Harness(inserter: inserter)
        await h.startRecording()
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .error(.notInserted(reason)), .idle])
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("two dictations in a row each get their own capture and clip")
    func sequentialDictations() async {
        var h = await Harness()
        await h.startRecording(samples: Self.audio(0.1))
        _ = await h.release()
        await h.startRecording(samples: Self.audio(0.7))
        let second = await h.release()

        #expect(second == Self.transcribed)
        #expect(h.capture.startCount == 2)
        #expect(
            h.recognizer.transcribedClips == [AudioClip(samples: Self.audio(0.1)), AudioClip(samples: Self.audio(0.7))])
    }

    @Test("a recognizer that throws CancellationError ends in an error, and a later press works")
    func recognizerThrowsCancellation() async {
        let cancelled = String(describing: CancellationError())
        var h = await Harness(recognizer: FakeRecognizer(failure: CancellationError()))
        await h.startRecording()
        let first = await h.release()
        await h.startRecording()  // never arrives if the coordinator is stuck processing
        let second = await h.release()

        let failed: [PipelineState] = [.transcribing(progress: nil), .error(.recognitionFailed(cancelled)), .idle]
        #expect(first == failed)
        #expect(second == failed)
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

    @Test("reaching the recording cap finishes the recording and says so")
    func clipCapFinishesRecording() async {
        var h = await Harness()
        await h.sut.handle(.down(at: Self.pressTime))
        h.capture.emit(AudioChunk(samples: [Float](repeating: 0.5, count: Self.capSamples)))
        let capped = await h.read(through: .notice(.capReached))
        // The key is still down, so the text waits for the release (see CapReleaseWaitTests).
        let rest = await h.release(after: 61_000)

        #expect(capped == [.starting, .recording(.hold), .notice(.capReached)])
        #expect(rest == Self.transcribed)
        #expect(h.recognizer.transcribedClips.map(\.samples.count) == [Self.capSamples])
        #expect(h.capture.stopCount == 1)
    }

    @Test("audio and a release after the cap fired stop and transcribe only once")
    func releaseAfterCap() async {
        var h = await Harness()
        await h.sut.handle(.down(at: Self.pressTime))
        h.capture.emit(AudioChunk(samples: [Float](repeating: 0.5, count: Self.capSamples)))
        h.capture.emit(AudioChunk(samples: [0.5]))
        _ = await h.read(through: .notice(.capReached))

        #expect(await h.release(after: 61_000) == Self.transcribed)
        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips.count == 1)
    }

    @Test("one sample short of the cap keeps recording until the release")
    func justUnderTheCap() async {
        var h = await Harness()
        await h.startRecording(samples: [Float](repeating: 0.5, count: Self.capSamples - 1))

        #expect(await h.release(after: 61_000) == Self.transcribed)
        #expect(h.recognizer.transcribedClips.map(\.samples.count) == [Self.capSamples - 1])
        #expect(!h.diagnostics.events.contains(.recordingCapReached))  // the cap was not reached, so it is not logged
    }
}
