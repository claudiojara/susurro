import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Testing

@Suite("Last dictation", .timeLimit(.minutes(1)))
struct LastDictationTests {
    private let repository = InMemoryHistoryRepository()
    private let clipboard = FakeClipboardWriter()

    private func last(inserter: FakeTextInserter = FakeTextInserter(), pageSize: Int = 50) -> LastDictation {
        LastDictation(repository: repository, inserter: inserter, clipboard: clipboard, pageSize: pageSize)
    }

    @discardableResult
    private func record(
        _ finalText: String?, status: DictationStatus = .succeeded, age: TimeInterval
    ) async throws -> DictationRecord {
        let record = DictationRecord(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 - age), duration: .seconds(2), status: status,
            rawText: finalText, finalText: finalText)
        try await repository.insert(record)
        return record
    }

    @Test("the text is the final text of the newest dictation that succeeded")
    func newestSucceeded() async throws {
        try await record("older", age: 30)
        try await record("newest", age: 10)
        try await record(nil, status: .failed, age: 5)
        try await record(nil, status: .noSpeech, age: 4)
        try await record("cancelled", status: .cancelled, age: 3)
        try await record(nil, status: .processing, age: 1)

        #expect(await last().text() == "newest")
    }

    @Test("a command is never the last dictation, even one whose record had text")
    func skipsCommands() async throws {
        try await record("dictated", age: 30)
        let command = DictationRecord(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 - 10), duration: .seconds(2), status: .succeeded,
            rawText: "make it formal", finalText: "make it formal", kind: .command)
        try await repository.insert(command)

        #expect(await last().text() == "dictated")
    }

    @Test("a dictation that succeeded with no text is skipped for the one before it")
    func skipsEmptyText() async throws {
        try await record("kept", age: 30)
        try await record("", age: 10)

        #expect(await last().text() == "kept")
    }

    @Test("the search goes on past the first page")
    func pages() async throws {
        try await record("far back", age: 100)
        for age in 1...5 { try await record(nil, status: .failed, age: TimeInterval(age)) }

        #expect(await last(pageSize: 2).text() == "far back")
    }

    @Test("an empty history, or one that cannot be read, has no text")
    func noText() async throws {
        #expect(await last().text() == nil)

        try await record("text", age: 1)
        repository.failAllCalls(with: HistoryError.recordNotFound(UUID()))
        #expect(await last().text() == nil)
    }

    @Test("paste hands the text to the inserter, with no target, and reports what the inserter did")
    func paste() async throws {
        try await record("hello there", age: 1)
        let inserter = FakeTextInserter(outcome: .copiedToClipboard(.pasteFailed))

        let outcome = await last(inserter: inserter).paste()

        #expect(outcome == .pasted(.copiedToClipboard(.pasteFailed)))
        #expect(inserter.insertedTexts == ["hello there"])
        #expect(inserter.targets == [nil])
    }

    @Test("paste with an empty history inserts nothing and says there was nothing")
    func pasteNothing() async {
        let inserter = FakeTextInserter()

        #expect(await last(inserter: inserter).paste() == .nothing)
        #expect(inserter.insertedTexts.isEmpty)
    }

    @Test("copy puts the text on the clipboard, and with an empty history copies nothing")
    func copy() async throws {
        #expect(await last().copy() == .nothing)
        #expect(clipboard.copiedTexts.isEmpty)

        try await record("copy me", age: 1)
        #expect(await last().copy() == .copied)
        #expect(clipboard.copiedTexts == ["copy me"])
    }

    @Test("the notice tells an empty history and a paste left on the clipboard, and nothing else")
    func notices() {
        #expect(LastDictationOutcome.nothing.notice == .noLastDictation)
        #expect(LastDictationOutcome.copied.notice == .lastDictationCopied)
        #expect(LastDictationOutcome.pasted(.inserted).notice == nil)
        #expect(
            LastDictationOutcome.pasted(.copiedToClipboard(.accessibilityMissing)).notice
                == .copiedToClipboard(.accessibilityMissing))
        #expect(LastDictationOutcome.pasted(.notInserted(.clipboardChanged)).notice == nil)
    }
}
