import CoreTestSupport
import Domain
import Foundation
import Testing

@testable import Pipeline

/// Command mode end to end on fakes: the command hotkey records an instruction over the selection, the on-device model
/// rewrites the selection, and the result replaces it, or goes to the clipboard when the selection changed meanwhile.
@Suite("Command mode in the dictation flow", .timeLimit(.minutes(1)))
struct CommandPipelineTests {
    private static let instruction = "make it formal"
    private static let selection = "hey, can't come tomorrow"
    private static let result = "Hello, I will not be able to attend tomorrow."
    /// The limit of a rewrite of `instruction` over `selection`: 3 s and 12 ms a character.
    private static let rewriteLimit = CommandLimits.timeout(instruction: instruction.count, selection: selection.count)

    private struct Fixture {
        let rewriter: FakeSelectionRewriter
        let reader: any FocusedContextReader
        let clipboard = FakeClipboardWriter()
        let settings = InMemorySettingsStore()
        var harness: CoordinatorHarness

        init(
            rewriter: FakeSelectionRewriter = FakeSelectionRewriter(reply: .text(CommandPipelineTests.result)),
            reader: any FocusedContextReader = FakeFocusedContextReader(selection: CommandPipelineTests.selection),
            enabled: Bool = true,
            permissions: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted],
            transcript: String = CommandPipelineTests.instruction,
            diagnostics: RecordingDiagnostics = RecordingDiagnostics(),
            corrections: (any CorrectionWatching)? = nil
        ) async {
            self.rewriter = rewriter
            self.reader = reader
            settings.set(enabled, for: CommandSettings.enabled)
            let sleeper = FakeSleeper()
            let settings = settings
            harness = await CoordinatorHarness(
                permissions: FakePermissionsChecker(permissions), recognizer: FakeRecognizer(transcript: transcript),
                settings: settings, sleeper: sleeper, diagnostics: diagnostics,
                command: CommandStage(
                    isEnabled: { settings.value(for: CommandSettings.enabled) }, rewriter: rewriter, reader: reader,
                    clipboard: clipboard),
                corrections: corrections)
        }

        /// Presses the command hotkey and waits until it records.
        mutating func press() async {
            await harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime, role: .command))
            harness.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
            _ = await harness.read(through: .recording(.hold))
        }

        func letGo(after milliseconds: Int = 1_200) async {
            await harness.sut.handle(
                .up(at: DictationCoordinatorTests.pressTime + .milliseconds(milliseconds), role: .command))
        }

        mutating func command() async -> [PipelineState] {
            await press()
            await letGo()
            return await harness.read(through: .idle)
        }
    }

    // MARK: Replacement

    @Test("the instruction over the selection is rewritten and the result replaces the selection")
    func replaces() async throws {
        var f = await Fixture()

        let states = await f.command()

        #expect(states == [.transcribing(progress: nil), .rewriting, .replaced, .idle])
        #expect(f.rewriter.requests == [LocalCommandRequest(instruction: Self.instruction, selection: Self.selection)])
        #expect(f.harness.inserter.insertedTexts == [Self.result])
        #expect(f.clipboard.copiedTexts.isEmpty)
    }

    @Test("a replacement ends the correction watch, so the rewrite is not learned as the user's correction")
    func replacementEndsCorrectionWatch() async {
        let spy = SpyCorrectionWatch()
        var f = await Fixture(corrections: spy)

        _ = await f.command()

        #expect(spy.cancels == 1)
        #expect(spy.receipts.isEmpty)
    }

    @Test("a result left on the clipboard does not touch the field, and the correction watch goes on")
    func clipboardKeepsCorrectionWatch() async {
        let spy = SpyCorrectionWatch()
        let reader = FakeFocusedContextReader([
            FocusedContext(selectedText: Self.selection), FocusedContext(selectedText: "something else"),
        ])
        var f = await Fixture(reader: reader, corrections: spy)

        _ = await f.command()

        #expect(f.clipboard.copiedTexts == [Self.result])
        #expect(spy.cancels == 0)
    }

    @Test("the record is a command that keeps the instruction and its audio, and neither the selection nor the result")
    func record() async throws {
        var f = await Fixture()

        _ = await f.command()

        let record = try #require(f.harness.history.allRecords.first)
        #expect(record.kind == .command)
        #expect(record.status == .succeeded)
        #expect(record.rawText == Self.instruction)
        #expect(record.cleanedText == nil)
        #expect(record.finalText == nil)
        #expect(record.delivery == .inserted)
        #expect(record.audioURL != nil)
    }

    @Test("a selection that ends a line keeps its line break")
    func trailingNewline() async {
        var f = await Fixture(reader: FakeFocusedContextReader(selection: Self.selection + "\n"))

        _ = await f.command()

        #expect(f.harness.inserter.insertedTexts == [Self.result + "\n"])
    }

    @Test("a selection that changed while the model worked is left alone, and the result goes to the clipboard")
    func selectionChanged() async {
        let reader = FakeFocusedContextReader([
            FocusedContext(selectedText: Self.selection), FocusedContext(selectedText: "something else"),
        ])
        var f = await Fixture(reader: reader)

        let states = await f.command()

        #expect(states.contains(.notice(.command(.selectionChanged))))
        #expect(f.harness.inserter.insertedTexts.isEmpty)
        #expect(f.clipboard.copiedTexts == [Self.result])
        #expect(f.harness.history.allRecords.first?.delivery == .copiedToClipboard)
    }

    @Test("a selection that is gone by then is a changed one too")
    func selectionGone() async {
        let reader = FakeFocusedContextReader([FocusedContext(selectedText: Self.selection), FocusedContext()])
        var f = await Fixture(reader: reader)

        _ = await f.command()

        #expect(f.harness.inserter.insertedTexts.isEmpty)
        #expect(f.clipboard.copiedTexts == [Self.result])
    }

    @Test(
        "a reply that is unusable, or a model that fails, leaves the text as it is",
        arguments: [
            FakeSelectionRewriter.Reply.text(""), .text(CommandPipelineTests.selection),
            .text("I'm sorry, I can't help with that."), .failure(FakeSelectionRewriter.EngineFailure()),
        ])
    func noResult(reply: FakeSelectionRewriter.Reply) async throws {
        var f = await Fixture(rewriter: FakeSelectionRewriter(reply: reply))

        let states = await f.command()

        #expect(states.contains(.notice(.command(.noResult))))
        #expect(f.harness.inserter.insertedTexts.isEmpty)
        #expect(f.clipboard.copiedTexts.isEmpty)
        let record = try #require(f.harness.history.allRecords.first)
        #expect(record.status == .failed)
        #expect(record.kind == .command)
    }

    // MARK: Time and Esc

    @Test("a rewrite that runs out of time is cancelled, and nothing is pasted")
    func timeout() async {
        let rewriter = FakeSelectionRewriter(gated: true)
        var f = await Fixture(rewriter: rewriter)
        await f.press()
        await f.letGo()
        await rewriter.entered.wait()
        await f.harness.sleeper.entered(Self.rewriteLimit).wait()

        f.harness.sleeper.fire(Self.rewriteLimit)
        let states = await f.harness.read(through: .idle)

        #expect(states.contains(.notice(.command(.noResult))))
        #expect(f.harness.inserter.insertedTexts.isEmpty)
        #expect(await eventually { rewriter.cancellations == 1 })
    }

    @Test("Esc while the model works cancels the rewrite: nothing is pasted, and the audio is kept")
    func escape() async throws {
        let rewriter = FakeSelectionRewriter(gated: true)
        var f = await Fixture(rewriter: rewriter)
        await f.press()
        await f.letGo()
        _ = await f.harness.read(through: .rewriting)
        await rewriter.entered.wait()

        await f.harness.sut.handle(.escape)
        _ = await f.harness.read(through: .idle)

        #expect(f.harness.inserter.insertedTexts.isEmpty)
        #expect(await eventually { rewriter.cancellations == 1 })
        let record = try #require(f.harness.history.allRecords.first)
        #expect(record.status == .cancelled)
        #expect(record.audioURL != nil)
    }

    // MARK: Start

    @Test(
        "a command that cannot run says why, and records nothing",
        arguments: [
            (
                true, PermissionStatus.granted, CleanerAvailability.unavailable("x"),
                CommandUnavailableReason.modelUnavailable
            ),
            (false, .granted, .available, .turnedOff),
            (true, .denied, .available, .accessibilityMissing),
        ])
    func unavailable(
        enabled: Bool, accessibility: PermissionStatus, availability: CleanerAvailability,
        reason: CommandUnavailableReason
    ) async {
        var f = await Fixture(
            rewriter: FakeSelectionRewriter(availability: availability), enabled: enabled,
            permissions: [.microphone: .granted, .accessibility: accessibility])

        await f.harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime, role: .command))
        let states = await f.harness.read(through: .idle)

        #expect(states.contains(.error(.commandUnavailable(reason))))
        #expect(f.harness.history.allRecords.isEmpty)
        #expect(f.harness.recordings.finished.isEmpty)
    }

    @Test(
        "without a usable selection the command says so and records nothing",
        arguments: [
            (FocusedContext?(FocusedContext(fieldText: "abc", selection: 1..<1)), CommandNotice.noSelection),
            (FocusedContext(isSecure: true), .secureField),
            (
                FocusedContext(selectedText: String(repeating: "a", count: CommandLimits.maxSelection + 1)),
                .selectionTooLong
            ),
            (nil, .selectionUnreadable),
        ])
    func noUsableSelection(snapshot: FocusedContext?, notice: CommandNotice) async {
        var f = await Fixture(reader: FakeFocusedContextReader([snapshot]))

        await f.harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime, role: .command))
        let states = await f.harness.read(through: .idle)
        await f.letGo()

        #expect(states.contains(.notice(.command(notice))))
        #expect(f.harness.history.allRecords.isEmpty)
        #expect(f.harness.recordings.finished.isEmpty)
    }

    @Test("the command key starts the capture at once, while the selection is still being read")
    func capturesWhileReadingTheSelection() async {
        let reader = GatedFocusedContextReader(FocusedContext(selectedText: Self.selection))
        var f = await Fixture(reader: reader)

        // The first words of the instruction are heard while the app is still being asked for its selection.
        await f.press()
        #expect(f.harness.capture.startCount == 1)
        reader.release()
        await f.letGo()
        let states = await f.harness.read(through: .idle)

        #expect(states.contains(.replaced))
        #expect(f.rewriter.requests == [LocalCommandRequest(instruction: Self.instruction, selection: Self.selection)])
    }

    @Test("a selection read that finds nothing to rewrite ends the recording with the notice, and keeps nothing")
    func endsTheRecordingWithoutASelection() async {
        let reader = GatedFocusedContextReader(FocusedContext(fieldText: "abc", selection: 1..<1))
        var f = await Fixture(reader: reader)
        await f.press()

        reader.release()
        let states = await f.harness.read(through: .idle)
        await f.letGo()

        #expect(states.contains(.notice(.command(.noSelection))))
        #expect(f.harness.history.allRecords.isEmpty)
        #expect(f.harness.recordings.finished.isEmpty)
        #expect(f.harness.recordings.aborted.count == 1)
        #expect(f.rewriter.requests.isEmpty)
    }

    @Test("a selection read that is still running when the key comes up is waited for before the job is queued")
    func waitsForTheSelectionOnRelease() async {
        let reader = GatedFocusedContextReader(FocusedContext(selectedText: Self.selection))
        var f = await Fixture(reader: reader)
        await f.press()

        // The release returns once the recording is finished, which waits for the selection.
        let coordinator = f.harness.sut
        let release = Task {
            await coordinator.handle(
                .up(at: DictationCoordinatorTests.pressTime + .milliseconds(1_200), role: .command))
        }
        reader.release()
        await release.value
        let states = await f.harness.read(through: .idle)

        #expect(states.contains(.replaced))
        #expect(f.harness.inserter.insertedTexts == [Self.result])
    }

    @Test("the key-down reads only the selection: no window title, no page address")
    func readsTheSelectionOnly() async {
        let reader = FakeFocusedContextReader(selection: Self.selection)
        var f = await Fixture(reader: reader)

        _ = await f.command()

        #expect(reader.callCount == 0)
        #expect(reader.selectionCallCount == 2)  // at key-down, and again before the paste
    }

    // MARK: Roles

    @Test("the command key cannot finish a dictation hold: its press and release go nowhere")
    func commandKeyDuringDictation() async {
        var f = await Fixture()
        await f.harness.startRecording()

        await f.harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime + .milliseconds(400), role: .command))
        await f.harness.sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(900), role: .command))
        let states = await f.harness.release(after: 1_500)

        #expect(states == DictationCoordinatorTests.transcribed)
        #expect(f.harness.inserter.insertedTexts == [Self.instruction])
        #expect(f.rewriter.requests.isEmpty)
    }

    @Test("command mode is hold only: a second tap of the command key starts a hold, never hands-free")
    func holdOnly() async {
        var f = await Fixture()
        await f.press()
        await f.letGo(after: 100)
        _ = await f.harness.read(through: .idle)

        await f.harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime + .milliseconds(200), role: .command))
        f.harness.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        let states = await f.harness.read(through: .recording(.hold))

        #expect(!states.contains(.recording(.handsFree)))
    }

    // MARK: Privacy

    @Test("the selection and the result never reach the history or the log")
    func sentinel() async throws {
        let selection = "SENTINEL-SELECTION-7f3a quarterly numbers"
        let result = "SENTINEL-RESULT-91bc Quarterly numbers."
        let diagnostics = RecordingDiagnostics()
        var f = await Fixture(
            rewriter: FakeSelectionRewriter(reply: .text(result)),
            reader: FakeFocusedContextReader(selection: selection), diagnostics: diagnostics)

        _ = await f.command()

        #expect(f.harness.inserter.insertedTexts == [result])
        let stored = f.harness.history.allRecords.map { String(describing: $0) }.joined()
        let logged = diagnostics.events.map { String(describing: $0) }.joined()
        for sentinel in ["SENTINEL-SELECTION", "SENTINEL-RESULT"] {
            #expect(!stored.contains(sentinel))
            #expect(!logged.contains(sentinel))
        }
    }

    @Test("a rewriter that is not on this Mac is never handed the selection")
    func cloudRewriterIsRefused() async {
        let rewriter = FakeSelectionRewriter(reply: .text(Self.result), locality: .cloud)
        var f = await Fixture(rewriter: rewriter)

        let states = await f.command()

        #expect(rewriter.requests.isEmpty)
        #expect(states.contains(.notice(.command(.noResult))))
        #expect(f.harness.inserter.insertedTexts.isEmpty)
    }

    @Test("the only request a rewrite takes holds the instruction and the selection, and nothing for the cloud")
    func requestShape() {
        let fields = Mirror(reflecting: LocalCommandRequest(instruction: "a", selection: "b")).children.map(\.label)

        #expect(fields == ["instruction", "selection"])
    }

    /// Polls a condition a few times, yielding in between, for work that ends in a task of its own.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}

/// A reader whose first read waits until the test releases it, as a slow app answers Accessibility.
private final class GatedFocusedContextReader: FocusedContextReader {
    private let context: FocusedContext?
    private let gate = Gate()

    init(_ context: FocusedContext?) {
        self.context = context
    }

    func release() { gate.open() }

    func snapshot() async -> FocusedContext? {
        await selectionSnapshot()
    }

    func selectionSnapshot() async -> FocusedContext? {
        await gate.wait()
        // Every later read answers at once.
        gate.open()
        return context
    }
}
