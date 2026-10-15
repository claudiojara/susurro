import CoreTestSupport
import Domain
import Foundation
import Observation
import Pipeline
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("History view model", .timeLimit(.minutes(1)))
struct HistoryViewModelTests {
    private let repository = InMemoryHistoryRepository()
    private let deleter = FakeAudioFileDeleter()
    private let clipboard = FakeClipboardWriter()
    private let loader = FakeAudioClipLoader()
    private let dates = FakeDateSource(Date(timeIntervalSince1970: 1_800_000_000))
    private let reprocessor = FakeDictationReprocessor(text: "a new transcript")

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeModel() -> HistoryViewModel {
        HistoryViewModel(
            repository: repository,
            actions: HistoryActions(repository: repository, deleter: deleter, clipboard: clipboard),
            retries: RetryService(repository: repository, loader: loader, reprocessor: reprocessor),
            dates: dates, calendar: Self.calendar, locale: Locale(identifier: "en_GB"))
    }

    /// A record `age` seconds old with audio, which the loader can read.
    @discardableResult
    private func add(
        _ status: DictationStatus = .succeeded, age: TimeInterval = 0, audio: Bool = true,
        configure: (inout DictationRecord) -> Void = { _ in }
    ) async throws -> DictationRecord {
        let id = UUID()
        let url = URL(filePath: "/audio/\(id.uuidString).caf")
        var record = DictationRecord(
            id: id, createdAt: dates.now().addingTimeInterval(-age), duration: .seconds(12), status: status,
            rawText: "raw words", cleanedText: "Clean words.", finalText: "Clean words.", appName: "Notes",
            audioURL: audio ? url : nil, audioExpired: !audio)
        configure(&record)
        if audio { loader.set(AudioClip(samples: [0.1, 0.2]), at: url) }
        try await repository.insert(record)
        return record
    }

    // MARK: Paging

    @Test(
        "the list is the newest dictations first, a page at a time, and the button to show older ones goes at the end")
    func paging() async throws {
        for index in 0..<120 { try await add(age: Double(index)) }
        let model = makeModel()

        await model.reload()
        #expect(model.state.rows.count == HistoryViewModel.pageSize)
        #expect(model.state.loadMoreTitle == "Show older")

        await model.loadMore()
        #expect(model.state.rows.count == 2 * HistoryViewModel.pageSize)
        #expect(model.state.loadMoreTitle == "Show older")

        await model.loadMore()
        #expect(model.state.rows.count == 120)
        #expect(model.state.loadMoreTitle == nil)

        let stored = try await repository.page(offset: 0, limit: 120)
        #expect(model.state.rows.map(\.id) == stored.map(\.id))
        #expect(stored.first?.createdAt ?? .distantPast > stored.last?.createdAt ?? .distantFuture)
    }

    @Test("a history with exactly one page has no button to show older ones")
    func exactlyOnePage() async throws {
        for index in 0..<HistoryViewModel.pageSize { try await add(age: Double(index)) }
        let model = makeModel()

        await model.reload()

        #expect(model.state.rows.count == HistoryViewModel.pageSize)
        #expect(model.state.loadMoreTitle == nil)
    }

    @Test("an empty history shows the empty message and nothing to delete")
    func emptyHistory() async {
        let model = makeModel()

        await model.reload()

        #expect(model.state.rows.isEmpty)
        #expect(model.state.emptyMessage == HistoryCopy.emptyMessage)
        #expect(model.state.deleteAllTitle == nil)
        #expect(model.state.loadMoreTitle == nil)
    }

    // MARK: Status mapping

    @Test(
        "each status has its word and its status, and a dictation in progress has no buttons",
        arguments: [
            (DictationStatus.processing, HistoryRowStatus.processing, "Processing…"),
            (.succeeded, .succeeded, "Done"),
            (.noSpeech, .noSpeech, "No speech"),
            (.failed, .failed, "Failed"),
            (.cancelled, .cancelled, "Cancelled"),
        ])
    func statusMapping(status: DictationStatus, row: HistoryRowStatus, label: String) async throws {
        try await add(status)
        let model = makeModel()

        await model.reload()

        let shown = try #require(model.state.rows.first)
        #expect(shown.status == row)
        #expect(shown.statusLabel == label)
        #expect(shown.actions.isEmpty == (status == .processing))
    }

    @Test("a done dictation offers both copies, retry, and delete, and shows its final text")
    func succeededRow() async throws {
        try await add()
        let model = makeModel()

        await model.reload()

        let row = try #require(model.state.rows.first)
        #expect(row.actions.map(\.kind) == [.copyRaw, .copyCleaned, .retry, .delete])
        #expect(row.actions.allSatisfy { $0.isAvailable })
        #expect(row.text == "Clean words.")
        #expect(row.detail == "Notes · 12 s")
        #expect(row.note == nil)
    }

    @Test("a dictation with no cleaned text offers no copy cleaned, and one with no text shows what stands in for it")
    func missingText() async throws {
        try await add(age: 10) {
            $0.cleanedText = nil; $0.finalText = nil
        }
        try await add(.failed, age: 20) {
            $0.rawText = nil; $0.cleanedText = nil; $0.finalText = nil
        }
        try await add(.noSpeech, age: 30) {
            $0.rawText = nil; $0.cleanedText = nil; $0.finalText = nil
        }
        let model = makeModel()

        await model.reload()

        let rows = model.state.rows
        #expect(rows[0].actions.map(\.kind) == [.copyRaw, .retry, .delete])
        #expect(rows[0].text == "raw words")
        #expect(rows[1].actions.map(\.kind) == [.retry, .delete])
        #expect(rows[1].text == "No text yet.")
        #expect(rows[2].text == "No speech was found.")
    }

    @Test("a failure says what went wrong and how to go on, and never quotes anything")
    func failureNote() async throws {
        try await add(.failed) { $0.failure = "timedOut.transcription" }
        let model = makeModel()

        await model.reload()

        #expect(model.state.rows.first?.note == "The transcription took too long. Retry to run it again.")
    }

    @Test("a dictation that quit midway, a cancelled one, and one that was not inserted each say so")
    func otherNotes() async throws {
        try await add(.failed, age: 10) { $0.failure = DictationRecord.interruptedFailure }
        try await add(.cancelled, age: 20)
        try await add(age: 30) { $0.delivery = .notInserted }
        try await add(age: 40) { $0.delivery = .copiedToClipboard }
        try await add(age: 50) {
            $0.cleanedText = nil; $0.fallbackReason = "cleanup timed out"
        }
        let model = makeModel()

        await model.reload()

        #expect(
            model.state.rows.map(\.note) == [
                "Susurro quit before this dictation was finished. Retry to run it again.",
                "You cancelled this dictation. The audio is kept.",
                "The text was not inserted. Copy it from here.",
                "The text was left on the clipboard.",
                "Cleanup did not run, so this is the raw text.",
            ])
    }

    // MARK: Retry availability

    @Test("retry is unavailable with a reason when the audio expired, and the row says the audio expired")
    func retryUnavailableWhenExpired() async throws {
        try await add(audio: false)
        let model = makeModel()

        await model.reload()

        let row = try #require(model.state.rows.first)
        let retry = try #require(row.actions.first { $0.kind == .retry })
        #expect(!retry.isAvailable)
        #expect(retry.unavailableReason == "Audio expired after 7 days.")
        #expect(row.detail == "Notes · 12 s · Audio expired")
    }

    @Test("retry runs the dictation again and the row shows the new text, with nothing pasted")
    func retryUpdatesTheRow() async throws {
        let failed = try await add(.failed) { $0.failure = "recognitionFailed" }
        let model = makeModel()
        await model.reload()

        await model.retry(failed.id)

        let row = try #require(model.state.rows.first)
        #expect(row.status == .succeeded)
        #expect(row.text == "a new transcript")
        #expect(model.state.errorMessage == nil)
        #expect(reprocessor.reprocessedRecords.map(\.id) == [failed.id])
    }

    @Test("a retry that is refused shows why")
    func retryRefused() async throws {
        let expired = try await add(audio: false)
        let model = makeModel()
        await model.reload()

        await model.retry(expired.id)

        #expect(model.state.errorMessage == "Audio expired after 7 days.")
        #expect(reprocessor.reprocessedRecords.isEmpty)
    }

    // MARK: Copy

    @Test("copy raw and copy cleaned put those texts on the clipboard")
    func copyActions() async throws {
        let record = try await add()
        let model = makeModel()

        await model.copyRaw(record.id)
        await model.copyCleaned(record.id)

        #expect(clipboard.copiedTexts == ["raw words", "Clean words."])
        #expect(model.state.errorMessage == nil)
    }

    @Test("copying a text that is not there shows an error and copies nothing")
    func copyMissing() async throws {
        let record = try await add { $0.cleanedText = nil }
        let model = makeModel()

        await model.copyCleaned(record.id)

        #expect(clipboard.copiedTexts.isEmpty)
        #expect(model.state.errorMessage == HistoryCopy.nothingToCopy)
        model.dismissError()
        #expect(model.state.errorMessage == nil)
    }

    // MARK: Deleting

    @Test("deleting one asks first: nothing is deleted until the question is answered")
    func deleteOneAsksFirst() async throws {
        let record = try await add()
        let model = makeModel()
        await model.reload()

        model.requestDelete(record.id)

        #expect(model.state.confirmation?.message == HistoryCopy.deleteOneQuestion)
        #expect(model.state.confirmation?.confirmTitle == "Delete")
        #expect(try await repository.record(id: record.id) != nil)
        #expect(deleter.attempts.isEmpty)

        model.cancelDeletion()
        #expect(model.state.confirmation == nil)
        await model.confirmDeletion()
        #expect(try await repository.record(id: record.id) != nil)
        #expect(deleter.attempts.isEmpty)
    }

    @Test("confirming the deletion of one removes the record and its audio and the row goes")
    func deleteOneConfirmed() async throws {
        let doomed = try await add()
        let kept = try await add(age: 10)
        let model = makeModel()
        await model.reload()

        model.requestDelete(doomed.id)
        await model.confirmDeletion()

        #expect(model.state.confirmation == nil)
        #expect(model.state.rows.map(\.id) == [kept.id])
        #expect(deleter.deleted == [doomed.audioURL])
        #expect(try await repository.record(id: doomed.id) == nil)
    }

    @Test("deleting all asks first, and confirming removes every record and every audio file")
    func deleteAll() async throws {
        let first = try await add()
        let second = try await add(age: 10)
        let model = makeModel()
        await model.reload()

        model.requestDeleteAll()
        #expect(model.state.confirmation?.message == HistoryCopy.deleteAllQuestion)
        #expect(try await repository.page(offset: 0, limit: 10).count == 2)

        await model.confirmDeletion()

        #expect(model.state.rows.isEmpty)
        #expect(Set(deleter.deleted) == [first.audioURL, second.audioURL])
        #expect(model.state.deleteAllTitle == nil)
    }

    @Test("a request to delete a dictation that is not in the list, or an empty list, asks nothing")
    func nothingToDelete() async {
        let model = makeModel()
        await model.reload()

        model.requestDelete(UUID())
        model.requestDeleteAll()

        #expect(model.state.confirmation == nil)
    }

    @Test("audio that cannot be deleted is reported and its dictation is kept")
    func deleteFailureIsShown() async throws {
        let stuck = try await add()
        deleter.setFailing([try #require(stuck.audioURL)])
        let model = makeModel()
        await model.reload()

        model.requestDelete(stuck.id)
        await model.confirmDeletion()

        #expect(model.state.errorMessage == HistoryCopy.audioNotDeleted(count: 1))
        #expect(model.state.rows.map(\.id) == [stuck.id])
    }

    // MARK: Following the history

    @Test("a dictation added while the screen is open shows up, and so does a change to one that is there")
    func liveUpdates() async throws {
        let model = makeModel()
        let following = Task { await model.run() }
        defer { following.cancel() }

        // The first reading happens after the subscription, so the screen starts empty and then follows.
        for await count in Observations({ model.state.rows.count }) where count == 0 { break }
        let record = try await add(.processing)
        for await count in Observations({ model.state.rows.count }) where count == 1 { break }
        #expect(model.state.rows.first?.status == .processing)

        var done = record
        done.status = .succeeded
        try await repository.update(done)
        for await status in Observations({ model.state.rows.first?.status }) where status == .succeeded { break }

        try await repository.delete(record.id)
        for await count in Observations({ model.state.rows.count }) where count == 0 { break }
    }

    @Test("a history that cannot be read keeps what was shown and says so")
    func unreadableHistory() async throws {
        try await add()
        let model = makeModel()
        await model.reload()
        struct Unreadable: Error {}
        repository.failAllCalls(with: Unreadable())

        await model.reload()

        #expect(model.state.rows.count == 1)
        #expect(model.state.errorMessage == HistoryCopy.historyUnreadable)
    }

    // MARK: Commands

    @Test("a command shows its instruction and says it was a command, and one that replaced nothing says why")
    func commands() {
        let mapper = HistoryRowMapper(calendar: Self.calendar, locale: Locale(identifier: "en_GB"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let replaced = DictationRecord(
            createdAt: now, duration: .seconds(2), status: .succeeded, rawText: "make it formal", delivery: .inserted,
            kind: .command)
        var unchanged = replaced
        unchanged.status = .failed
        unchanged.failure = "commandNoResult"
        unchanged.delivery = nil

        let row = mapper.row(for: replaced, now: now)

        #expect(row.text == "make it formal")
        #expect(row.note == HistoryCopy.command)
        #expect(mapper.row(for: unchanged, now: now).note?.hasPrefix(HistoryCopy.command) == true)
        #expect(mapper.row(for: unchanged, now: now).note?.contains(HistoryCopy.failure("commandNoResult")) == true)
    }

    // MARK: Timestamps

    @Test("a dictation of today, yesterday, this year, and an earlier year each get their form of the date")
    func timestamps() {
        let mapper = HistoryRowMapper(calendar: Self.calendar, locale: Locale(identifier: "en_GB"))
        // 2027-01-15 08:00 UTC.
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(mapper.timestamp(of: now.addingTimeInterval(-3_600), now: now) == "Today, 07:00")
        #expect(mapper.timestamp(of: now.addingTimeInterval(-86_400), now: now) == "Yesterday, 08:00")
        #expect(mapper.timestamp(of: now.addingTimeInterval(-3 * 86_400), now: now) == "12 Jan, 08:00")
        #expect(mapper.timestamp(of: now.addingTimeInterval(-30 * 86_400), now: now) == "16 Dec 2026, 08:00")
    }

    @Test("a length is in seconds under a minute and in minutes after it, and never zero")
    func lengths() {
        #expect(HistoryRowMapper.length(.milliseconds(200)) == "1 s")
        #expect(HistoryRowMapper.length(.seconds(12)) == "12 s")
        #expect(HistoryRowMapper.length(.seconds(60)) == "1 min")
        #expect(HistoryRowMapper.length(.seconds(65)) == "1 min 5 s")
    }
}
