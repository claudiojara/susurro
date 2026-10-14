import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Testing

@Suite("History actions", .timeLimit(.minutes(1)))
struct HistoryActionsTests {
    private let repository = InMemoryHistoryRepository()
    private let deleter = FakeAudioFileDeleter()
    private let clipboard = FakeClipboardWriter()

    private var actions: HistoryActions {
        HistoryActions(repository: repository, deleter: deleter, clipboard: clipboard)
    }

    private func record(
        status: DictationStatus = .succeeded, age: TimeInterval = 0, audio: Bool = true
    ) async throws -> DictationRecord {
        let id = UUID()
        let record = DictationRecord(
            id: id, createdAt: Date(timeIntervalSince1970: 1_800_000_000 - age), duration: .seconds(2), status: status,
            rawText: "raw text", cleanedText: "Cleaned text", finalText: "Cleaned text",
            audioURL: audio ? URL(filePath: "/audio/\(id.uuidString).caf") : nil, audioExpired: !audio)
        try await repository.insert(record)
        return record
    }

    @Test("copy raw puts the raw text on the clipboard, and copy cleaned the cleaned text")
    func copyRawAndCleaned() async throws {
        let record = try await record()

        try await actions.copyRaw(record.id)
        try await actions.copyCleaned(record.id)

        #expect(clipboard.copiedTexts == ["raw text", "Cleaned text"])
    }

    @Test("there is nothing to copy when the text is missing, and nothing is put on the clipboard")
    func nothingToCopy() async throws {
        var record = try await record()
        record.cleanedText = nil
        record.rawText = nil
        try await repository.update(record)

        await #expect(throws: HistoryActionError.nothingToCopy) { try await actions.copyRaw(record.id) }
        await #expect(throws: HistoryActionError.nothingToCopy) { try await actions.copyCleaned(record.id) }
        await #expect(throws: HistoryActionError.recordNotFound) { try await actions.copyRaw(UUID()) }
        #expect(clipboard.copiedTexts.isEmpty)
    }

    @Test("deleting one removes the record and its audio file, and no other record")
    func deleteOne() async throws {
        let doomed = try await record()
        let kept = try await record(age: 10)

        try await actions.delete(doomed.id)

        #expect(deleter.deleted == [doomed.audioURL])
        #expect(try await repository.record(id: doomed.id) == nil)
        #expect(try await repository.record(id: kept.id) == kept)
    }

    @Test("deleting a record whose audio expired deletes no file")
    func deleteExpired() async throws {
        let expired = try await record(audio: false)

        try await actions.delete(expired.id)

        #expect(deleter.attempts.isEmpty)
        #expect(try await repository.record(id: expired.id) == nil)
    }

    @Test("a file that cannot be deleted is reported, and the record stays so the audio is not left behind")
    func deleteOneFileFails() async throws {
        let stuck = try await record()
        deleter.setFailing([try #require(stuck.audioURL)])

        await #expect(throws: HistoryActionError.audioNotDeleted(count: 1)) { try await actions.delete(stuck.id) }

        #expect(try await repository.record(id: stuck.id) == stuck)
        deleter.setFailing([])
        try await actions.delete(stuck.id)
        #expect(try await repository.record(id: stuck.id) == nil)
    }

    @Test("deleting a record that is not there is not an error")
    func deleteMissing() async throws {
        try await actions.delete(UUID())
        #expect(deleter.attempts.isEmpty)
    }

    @Test("delete all removes every record and every audio file")
    func deleteAll() async throws {
        let first = try await record()
        let second = try await record(age: 10)
        _ = try await record(status: .failed, age: 20, audio: false)

        try await actions.deleteAll()

        #expect(Set(deleter.deleted) == [first.audioURL, second.audioURL])
        #expect(try await repository.page(offset: 0, limit: 10).isEmpty)
    }

    @Test("delete all keeps a dictation that is still being processed")
    func deleteAllKeepsProcessing() async throws {
        let live = try await record(status: .processing)
        _ = try await record(age: 10)

        try await actions.deleteAll()

        #expect(try await repository.page(offset: 0, limit: 10) == [live])
        #expect(deleter.deleted.count == 1)
    }

    @Test("delete all removes what it can, keeps the records whose file could not be deleted, and reports them")
    func deleteAllWithFailures() async throws {
        let stuck = try await record()
        let fine = try await record(age: 10)
        let textOnly = try await record(age: 20, audio: false)
        deleter.setFailing([try #require(stuck.audioURL)])

        await #expect(throws: HistoryActionError.audioNotDeleted(count: 1)) { try await actions.deleteAll() }

        #expect(try await repository.page(offset: 0, limit: 10) == [stuck])
        #expect(try await repository.record(id: fine.id) == nil)
        #expect(try await repository.record(id: textOnly.id) == nil)
    }
}
