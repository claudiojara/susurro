import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing
import TextShaping

/// The coordinator with a context, a vocabulary, and a cleanup stage: the vocabulary reaches the recognizer and the
/// cleaner, the polishing state shows, and the inserted text is the cleaned one, shaped for the cursor.
@Suite("Cleanup in the dictation flow", .timeLimit(.minutes(1)))
struct CleanupFlowTests {
    private struct Terms: UserDictionary {
        let list: [String]
        /// The written forms of replacement rules, which the vocabulary takes after the terms.
        var written: [String] = []
        func terms() -> [String] { list }
        func vocabularyTerms() -> [String] { list + written }
    }

    private struct Fixture {
        let cleaner: FakeCleaner
        var harness: CoordinatorHarness

        init(
            transcript: String = "hola equipo", cleaner: FakeCleaner = FakeCleaner(answer: .text("Hola, equipo.")),
            enabled: Bool = true, app: AppIdentity = .mail, before: String = "Dear team,",
            dictionary: [String] = ["Acme"], written: [String] = [], tagger: FakeEntityTagger = FakeEntityTagger(),
            enrichment: ContextEnrichment? = nil
        ) async {
            self.cleaner = cleaner
            // The 300 ms wait for the context is a pause, which a plain sleeper ends at once: the context would then
            // lose the race against its own capture. Blocking pauses lets the capture finish, as it does in the app.
            let sleeper = FakeSleeper(blocksPauses: true)
            let settings = InMemorySettingsStore()
            settings.set(enabled, for: CleanupSettings.enabled)
            settings.set(cleaner.id.rawValue, for: CleanupSettings.provider)
            let entry: CleanerRegistry.Entry =
                cleaner.locality == .cloud ? .cloud(cleaner, isEnabled: { true }, hasKey: { true }) : .local(cleaner)
            let stage = CleanupStage(
                settings: settings, registry: CleanerRegistry(settings: settings, entries: [entry]),
                sleep: { try await sleeper.sleep($0) })
            let source = FakeContextSource(context: DictationContext(app: app, beforeCursor: before))
            let frontmost = await MainActor.run { FakeFrontmostAppProvider(app) }
            harness = await CoordinatorHarness(
                recognizer: FakeRecognizer(transcript: transcript), sleeper: sleeper, frontmost: frontmost,
                context: ContextPipeline(source: source), cleanup: stage,
                vocabulary: VocabularyPipeline(
                    dictionary: Terms(list: dictionary, written: written), builder: VocabularyBuilder(tagger: tagger),
                    enrichment: enrichment))
        }

        mutating func dictate() async -> [PipelineState] {
            await harness.startRecording()
            return await harness.release()
        }
    }

    @Test("the cleaned text is inserted, shaped for the cursor, and the overlay shows polishing")
    func cleanedTextIsInserted() async throws {
        var f = await Fixture()
        let states = await f.dictate()
        #expect(states == [.transcribing(progress: nil), .polishing, .inserted, .idle])
        #expect(f.harness.inserter.insertedTexts == [" hola, equipo."])

        let request = try #require(f.cleaner.payloads.first).requireLocal()
        #expect(request.style == StyleProfile(category: .email, tone: .formal, source: .bundle))
        #expect(request.vocabulary == ["Acme"])
        #expect(request.beforeCursor == "Dear team,")
    }

    @Test("the recognizer receives the dictionary and the names found around the cursor")
    func recognizerGetsVocabulary() async {
        let before = "Meeting with Maria Gonzalez about Acme tomorrow"
        let tagger = FakeEntityTagger([before: ["Maria Gonzalez", "Acme", "Zed"]])
        var f = await Fixture(before: before, dictionary: ["Zed", "Yara"], tagger: tagger)
        _ = await f.dictate()
        #expect(
            f.harness.recognizer.transcribedOptions.map(\.vocabulary) == [["Zed", "Yara", "Maria Gonzalez", "Acme"]])
        #expect(tagger.taggedTexts == [before])
    }

    @Test("only the dictionary is offered for boosting: the names around the cursor and on the screen are not")
    func recognizerBoostsTheDictionaryAlone() async {
        let before = "Meeting with Maria Gonzalez about Acme tomorrow"
        let tagger = FakeEntityTagger([before: ["Maria Gonzalez", "Acme", "Zed"]])
        var f = await Fixture(
            before: before, dictionary: ["Zed", " Yara ", "zed", String(repeating: "x", count: 41)], tagger: tagger)
        _ = await f.dictate()
        // The dictionary as the vocabulary holds it: trimmed, without repeats, within the length limit.
        #expect(f.harness.recognizer.transcribedOptions.map(\.boostTerms) == [["Zed", "Yara"]])
    }

    @Test("the written forms of the replacement rules are boosted and in the vocabulary, after the terms")
    func replacementsFeedTheVocabulary() async {
        var f = await Fixture(dictionary: ["Zed"], written: ["Jira"])
        _ = await f.dictate()
        #expect(f.harness.recognizer.transcribedOptions.map(\.boostTerms) == [["Zed", "Jira"]])
        #expect(f.harness.recognizer.transcribedOptions.map(\.vocabulary) == [["Zed", "Jira"]])
    }

    @Test("a cloud cleaner gets the vocabulary and none of the context")
    func cloudCleanerGetsNoContext() async throws {
        let cloud = FakeCleaner(id: CleanerProviderID("cloud"), locality: .cloud, answer: .text("Hola, Acme."))
        var f = await Fixture(transcript: "hola acme", cleaner: cloud, before: "BEFORE-SENTINEL")
        _ = await f.dictate()

        let payload = try #require(cloud.payloads.first)
        #expect(try payload.requireCloud().vocabulary == ["Acme"])
        #expect(!String(reflecting: payload).contains("BEFORE-SENTINEL"))
        #expect(f.harness.inserter.insertedTexts.count == 1)
    }

    @Test("a cleaner that fails inserts the raw transcript")
    func failureInsertsRaw() async {
        var f = await Fixture(cleaner: FakeCleaner(answer: .failure(.failed("boom"))), before: "")
        let states = await f.dictate()
        #expect(states == [.transcribing(progress: nil), .polishing, .inserted, .idle])
        #expect(f.harness.inserter.insertedTexts == ["hola equipo"])
    }

    @Test("cleanup that is off inserts the transcript without a polishing state")
    func cleanupOff() async {
        var f = await Fixture(enabled: false, before: "")
        let states = await f.dictate()
        #expect(states == [.transcribing(progress: nil), .inserted, .idle])
        #expect(f.harness.inserter.insertedTexts == ["hola equipo"])
        #expect(f.cleaner.callCount == 0)
    }

    @Test("a terminal dictation is verbatim and never reaches the cleaner")
    func verbatimSkipsCleaner() async {
        let terminal = AppIdentity(processID: 300, name: "Terminal", bundleID: "com.apple.Terminal")
        var f = await Fixture(app: terminal, before: "")
        let states = await f.dictate()
        #expect(states == [.transcribing(progress: nil), .inserted, .idle])
        #expect(f.cleaner.callCount == 0)
        #expect(f.harness.inserter.insertedTexts == ["hola equipo"])
    }

    @Test("a field with nothing around the cursor leaves the text as the cleaner wrote it")
    func emptyFieldLeavesTextAlone() async {
        var f = await Fixture(cleaner: FakeCleaner(answer: .text("The report.")), before: "")
        _ = await f.dictate()
        #expect(f.harness.inserter.insertedTexts == ["The report."])
    }

    @Test("a dictation with no vocabulary pipeline has none, and no context terms")
    func noVocabularyPipeline() async {
        let recognizer = FakeRecognizer()
        var harness = await CoordinatorHarness(recognizer: recognizer)
        await harness.startRecording()
        _ = await harness.release()
        #expect(recognizer.transcribedOptions.map(\.vocabulary) == [[]])
        #expect(recognizer.transcribedOptions.map(\.boostTerms) == [[]])
    }

    @Test("names read from the screen join the vocabulary, and the screen text itself goes nowhere else")
    func screenNamesJoinTheVocabulary() async throws {
        let ocrLine = "OCR-SENTINEL Acme Corp"
        let screen = FakeScreenTextRecognizer(lines: [ocrLine])
        let tagger = FakeEntityTagger([ocrLine: ["Acme Corp"]])
        let settings = InMemorySettingsStore()
        settings.set(true, for: ContextSettings.ocrEnabled)
        let read = Gate()
        let enrichment = ContextEnrichment(
            settings: settings, permissions: FakePermissionsChecker([.screenRecording: .granted]), recognizer: screen,
            frontmost: {
                read.open()
                return ScreenTarget(app: .mail)
            })
        var f = await Fixture(dictionary: [], tagger: tagger, enrichment: enrichment)
        await f.harness.startRecording()
        // The reading ends once the app is checked again, which is its last step. What is left to do then is a store of the
        // lines in a task of utility priority, with nothing to wait on from outside: on a busy machine the scheduler can
        // leave that task idle for longer than any number of yields, so it is given real time to finish.
        await read.wait()
        try await Task.sleep(for: .milliseconds(200))
        _ = await f.harness.release()

        #expect(f.harness.recognizer.transcribedOptions.map(\.vocabulary) == [["Acme Corp"]])
        let payload = try #require(f.cleaner.payloads.first)
        #expect(try payload.requireLocal().vocabulary == ["Acme Corp"])
        #expect(!String(reflecting: payload).contains("OCR-SENTINEL"))
        #expect(screen.recognizedTargets == [ScreenTarget(app: .mail)])
    }
}
