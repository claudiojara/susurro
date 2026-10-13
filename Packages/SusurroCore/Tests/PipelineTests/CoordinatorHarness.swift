import CoreTestSupport
import Domain
import Pipeline

/// Wires the coordinator to fakes and reads its published states. Tests call `handle` directly, so an ignored event is
/// provably applied before the next step. The suites of the coordinator share it.
struct CoordinatorHarness {
    let hotkeys = FakeHotkeySource()
    let capture: FakeAudioCaptureSource
    let recognizer: FakeRecognizer
    let inserter: FakeTextInserter
    let sleeper: FakeSleeper
    let diagnostics: RecordingDiagnostics
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
        let diagnostics = RecordingDiagnostics()
        self.diagnostics = diagnostics
        let coordinator = DictationCoordinator(
            hotkeys: hotkeys,
            capture: capture,
            recognizer: recognizer,
            inserter: inserter,
            permissions: permissions,
            diagnostics: diagnostics,
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
    mutating func startRecording(samples: [Float] = DictationCoordinatorTests.clip) async {
        await sut.handle(.down(at: DictationCoordinatorTests.pressTime))
        capture.emit(AudioChunk(samples: samples))
        _ = await read(through: .recording(.hold))
    }

    /// Releases after the given hold and reads the rest of the cycle.
    mutating func release(after milliseconds: Int = 1200) async -> [PipelineState] {
        await sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(milliseconds)))
        return await read(through: .idle)
    }

    /// Presses and releases a hold that is long enough to be kept, then waits for the dictation to be processing.
    mutating func startProcessing() async {
        await startRecording()
        await sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(1200)))
        _ = await read(through: .transcribing(progress: nil))
    }
}
