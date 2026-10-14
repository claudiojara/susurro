import CoreTestSupport
import Domain
import Pipeline
import Testing

/// The coordinator with a cleanup stage and a source of surroundings: the vocabulary reaches the recognizer and the
/// cleaner, the polishing state shows, and the inserted text is the cleaned one, shaped for the cursor.
@Suite("Cleanup in the dictation flow", .timeLimit(.minutes(1)))
struct CleanupFlowTests {
    private static let email = StyleProfile(category: .email, tone: .formal)

    private struct Flow {
        let recognizer: FakeRecognizer
        let inserter = FakeTextInserter()
        let capture = FakeAudioCaptureSource()
        let hotkeys = FakeHotkeySource()
        let coordinator: DictationCoordinator
        var states: AsyncStream<PipelineState>.Iterator

        init(
            transcript: String = "hola equipo", cleaner: FakeCleaner?, enabled: Bool = true,
            surroundings: DictationSurroundings
        ) async {
            recognizer = FakeRecognizer(transcript: transcript)
            let sleeper = FakeSleeper()
            let stage = cleaner.map { cleaner in
                CleanupStage(
                    isEnabled: { enabled }, cleaner: { cleaner }, sleep: { try await sleeper.sleep($0) })
            }
            coordinator = DictationCoordinator(
                hotkeys: hotkeys, capture: capture, recognizer: recognizer, inserter: inserter,
                permissions: FakePermissionsChecker(), sleep: { try await sleeper.sleep($0) }, cleanup: stage,
                surroundings: FakeSurroundingsSource(surroundings))
            states = coordinator.states.makeAsyncIterator()
            _ = await states.next()
        }

        /// Dictates once and returns the states of the processing.
        mutating func dictate() async -> [PipelineState] {
            let press = DictationCoordinatorTests.pressTime
            await coordinator.handle(.down(at: press))
            capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
            while let state = await states.next(), state != .recording(.hold) {}
            await coordinator.handle(.up(at: press + .milliseconds(1200)))
            var seen: [PipelineState] = []
            while let state = await states.next() {
                seen.append(state)
                if state == .idle { break }
            }
            return seen
        }
    }

    @Test("the cleaned text is inserted, shaped for the cursor, and the overlay shows polishing")
    func cleanedTextIsInserted() async {
        let cleaner = FakeCleaner(answer: .text("Hola, equipo."))
        let around = DictationSurroundings(
            style: Self.email, vocabulary: ["Acme"], cursor: CursorContext(before: "Dear team,", after: ""))
        var flow = await Flow(cleaner: cleaner, surroundings: around)
        let states = await flow.dictate()

        #expect(states == [.transcribing(progress: nil), .polishing, .inserted, .idle])
        #expect(flow.inserter.insertedTexts == [" hola, equipo."])
        let request = try? #require(cleaner.payloads.first).requireLocal()
        #expect(request?.style == Self.email)
        #expect(request?.vocabulary == ["Acme"])
        #expect(request?.beforeCursor == "Dear team,")
    }

    @Test("the recognizer receives the vocabulary")
    func recognizerGetsVocabulary() async {
        let around = DictationSurroundings(style: Self.email, vocabulary: ["Maria Gonzalez", "Acme"])
        var flow = await Flow(cleaner: FakeCleaner(), surroundings: around)
        _ = await flow.dictate()
        #expect(flow.recognizer.transcribedOptions == [RecognitionOptions(vocabulary: ["Maria Gonzalez", "Acme"])])
    }

    @Test("a cloud cleaner gets the vocabulary and none of the context")
    func cloudCleanerGetsNoContext() async throws {
        let cleaner = FakeCleaner(id: CleanerProviderID("cloud"), locality: .cloud, answer: .text("Hola, Acme."))
        let around = DictationSurroundings(
            style: Self.email, vocabulary: ["Acme"],
            cursor: CursorContext(before: "BEFORE-SENTINEL", after: "AFTER-SENTINEL"))
        var flow = await Flow(transcript: "hola acme", cleaner: cleaner, surroundings: around)
        _ = await flow.dictate()

        let payload = try #require(cleaner.payloads.first)
        let request = try payload.requireCloud()
        #expect(request.vocabulary == ["Acme"])
        let dump = String(reflecting: payload)
        for sentinel in ["BEFORE-SENTINEL", "AFTER-SENTINEL"] { #expect(!dump.contains(sentinel)) }
        #expect(flow.inserter.insertedTexts.count == 1)
    }

    @Test("a cleaner that fails inserts the raw transcript and the overlay still moves on")
    func failureInsertsRaw() async {
        let cleaner = FakeCleaner(answer: .failure(.failed("boom")))
        var flow = await Flow(cleaner: cleaner, surroundings: DictationSurroundings(style: Self.email))
        let states = await flow.dictate()
        #expect(states == [.transcribing(progress: nil), .polishing, .inserted, .idle])
        #expect(flow.inserter.insertedTexts == ["hola equipo"])
    }

    @Test("cleanup that is off inserts the transcript without a polishing state")
    func cleanupOff() async {
        let cleaner = FakeCleaner()
        var flow = await Flow(cleaner: cleaner, enabled: false, surroundings: DictationSurroundings(style: Self.email))
        let states = await flow.dictate()
        #expect(states == [.transcribing(progress: nil), .inserted, .idle])
        #expect(flow.inserter.insertedTexts == ["hola equipo"])
        #expect(cleaner.callCount == 0)
    }

    @Test("a verbatim style never reaches the cleaner")
    func verbatimSkipsCleaner() async {
        let cleaner = FakeCleaner()
        let around = DictationSurroundings(style: StyleProfile(category: .terminal, tone: .verbatim))
        var flow = await Flow(cleaner: cleaner, surroundings: around)
        let states = await flow.dictate()
        #expect(states == [.transcribing(progress: nil), .inserted, .idle])
        #expect(cleaner.callCount == 0)
        #expect(flow.inserter.insertedTexts == ["hola equipo"])
    }
}
