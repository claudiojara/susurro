import CoreTestSupport
import Domain
import Pipeline

/// Wires the coordinator to fakes and reads its published states. Tests call `handle` directly, so an ignored event is
/// provably applied before the next step. The suites of the coordinator share it.
struct CoordinatorHarness {
    let hotkeys = FakeHotkeySource()
    let capture: FakeAudioCaptureSource
    let recordings: FakeRecordingStore
    let recognizer: FakeRecognizer
    let inserter: FakeTextInserter
    let history: InMemoryHistoryRepository
    let vad: FakeVoiceActivityDetector
    let settings: InMemorySettingsStore
    let sleeper: FakeSleeper
    let clock: ManualClock
    let diagnostics: RecordingDiagnostics
    let pipeline: DictationPipeline
    let sut: DictationCoordinator
    private var states: AsyncStream<PipelineState>.Iterator

    init(
        permissions: FakePermissionsChecker = FakePermissionsChecker(),
        capture: FakeAudioCaptureSource = FakeAudioCaptureSource(),
        recordings: FakeRecordingStore = FakeRecordingStore(),
        recognizer: FakeRecognizer = FakeRecognizer(),
        inserter: FakeTextInserter = FakeTextInserter(),
        history: InMemoryHistoryRepository = InMemoryHistoryRepository(),
        vad: FakeVoiceActivityDetector = FakeVoiceActivityDetector(),
        settings: InMemorySettingsStore = InMemorySettingsStore(),
        sleeper: FakeSleeper = FakeSleeper(),
        recordingCap: Duration = DictationCoordinatorTests.cap,
        frontmost: FakeFrontmostAppProvider? = nil,
        context: ContextPipeline? = nil,
        diagnostics: RecordingDiagnostics = RecordingDiagnostics(),
        clock: ManualClock = ManualClock(),
        cleanup: CleanupStage? = nil,
        vocabulary: VocabularyPipeline? = nil,
        preview: LiveTranscriptPreview? = nil,
        command: CommandStage? = nil,
        corrections: (any CorrectionWatching)? = nil
    ) async {
        self.capture = capture
        self.recordings = recordings
        self.recognizer = recognizer
        self.inserter = inserter
        self.history = history
        self.vad = vad
        self.settings = settings
        self.sleeper = sleeper
        self.clock = clock
        self.diagnostics = diagnostics
        let sleep: @Sendable (Duration) async throws -> Void = { try await sleeper.sleep($0) }
        let registry = RecognizerRegistry(providers: [recognizer], defaultProvider: recognizer.id, settings: settings)
        let pipeline = DictationPipeline(
            recordings: recordings,
            history: history,
            detector: vad,
            runner: RecognitionRunner(
                registry: registry, language: SettingsLanguagePreference(settings: settings),
                diagnostics: diagnostics, sleep: sleep),
            inserter: inserter,
            cleanup: cleanup,
            diagnostics: diagnostics,
            corrections: corrections,
            sleep: sleep,
            command: command
        )
        self.pipeline = pipeline
        let coordinator = DictationCoordinator(
            hotkeys: hotkeys,
            capture: capture,
            recordings: recordings,
            recognizers: registry,
            pipeline: pipeline,
            permissions: permissions,
            frontmost: frontmost,
            context: context,
            recordingCap: recordingCap,
            diagnostics: diagnostics,
            sleep: sleep,
            clock: clock,
            vocabulary: vocabulary,
            preview: preview
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
