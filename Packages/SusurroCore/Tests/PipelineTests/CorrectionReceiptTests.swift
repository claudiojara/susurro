import CoreTestSupport
import Domain
import Foundation
import Synchronization
import Testing
import TextShaping

@testable import Pipeline

/// Records what the pipeline hands to the correction watch.
private final class SpyCorrectionWatch: CorrectionWatching {
    private let state = Mutex<(receipts: [InsertionReceipt], handoffs: [DictationContext])>(([], []))
    var receipts: [InsertionReceipt] { state.withLock { $0.receipts } }
    var handoffs: [DictationContext] { state.withLock { $0.handoffs } }

    func watch(_ receipt: InsertionReceipt) async { state.withLock { $0.receipts.append(receipt) } }
    func handoff(_ context: DictationContext) async { state.withLock { $0.handoffs.append(context) } }
}

@Suite("Pipeline and the correction watch", .timeLimit(.minutes(1)))
struct CorrectionReceiptTests {
    private static let context = DictationContext(
        app: .mail, beforeCursor: String(repeating: "b", count: 100) + "Hello team. ",
        afterCursor: " See you." + String(repeating: "a", count: 100))

    private static func harness(
        watch: any CorrectionWatching, inserter: FakeTextInserter = FakeTextInserter(),
        context: DictationContext = context, history: InMemoryHistoryRepository = InMemoryHistoryRepository()
    ) async -> CoordinatorHarness {
        let frontmost = await MainActor.run { FakeFrontmostAppProvider(.mail) }
        return await CoordinatorHarness(
            recognizer: FakeRecognizer(transcript: CorrectionWatchTests.inserted), inserter: inserter, history: history,
            frontmost: frontmost, context: ContextPipeline(source: FakeContextSource(context: context)),
            corrections: watch)
    }

    @Test("a pasted dictation is handed to the watch, with 80 characters around it and where it went")
    func insertedRegistersReceipt() async throws {
        let spy = SpyCorrectionWatch()
        var h = await Self.harness(watch: spy)
        await h.startRecording()
        _ = await h.release()

        let receipt = try #require(spy.receipts.first)
        #expect(spy.receipts.count == 1)
        #expect(receipt.finalText == CorrectionWatchTests.inserted)
        #expect(receipt.anchorBefore == String(Self.context.beforeCursor.suffix(80)))
        #expect(receipt.anchorAfter == String(Self.context.afterCursor.prefix(80)))
        #expect(receipt.target == .mail)
        #expect(receipt.category == .email)
        #expect(!receipt.isSecureField)
        #expect(spy.handoffs == [Self.context])
    }

    @Test("a dictation copied to the clipboard instead is not watched")
    func copiedIsNotWatched() async {
        let spy = SpyCorrectionWatch()
        var h = await Self.harness(watch: spy, inserter: FakeTextInserter(outcome: .copiedToClipboard(.pasteFailed)))
        await h.startRecording()
        _ = await h.release()

        #expect(spy.receipts.isEmpty)
    }

    @Test("the text of the field read by the watch never reaches the history")
    func historyPrivacy() async throws {
        let settings = InMemorySettingsStore()
        let reader = MutableFocusedContextReader()
        let field =
            "SENTINEL_FIELD_HEAD " + Self.context.beforeCursor + "I spoke with Kaelthorn about the launch."
            + Self.context.afterCursor + " SENTINEL_FIELD_TAIL"
        reader.set(FocusedContext(fieldText: field, selection: field.utf16.count..<field.utf16.count))
        let clock = ManualClock()
        let frontmost = await MainActor.run { FakeFrontmostAppProvider(.mail) }
        let watch = CorrectionWatch(
            reader: reader, frontmost: frontmost, store: SuggestionStore(settings: settings), dictionaryTerms: { [] },
            filter: SuggestionFilter(tagger: FakeEntityTagger()), settings: settings,
            sleep: { try await clock.sleep(for: $0) })
        let history = InMemoryHistoryRepository()
        var h = await Self.harness(watch: watch, history: history)
        await h.startRecording()
        _ = await h.release()
        await clock.waitForSleeps(1)
        clock.advance(by: CorrectionWatch.rereadDelay)
        await watch.settled()

        #expect(SuggestionStore(settings: settings).suggestions().map(\.term) == ["Kaelthorn"])
        let records = String(describing: history.allRecords)
        #expect(!records.contains("SENTINEL"))
        #expect(!records.contains("Kaelthorn"))
    }
}
