import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Testing

@Suite("Retry service", .timeLimit(.minutes(1)))
struct RetryServiceTests {
    private let repository = InMemoryHistoryRepository()
    private let loader = FakeAudioClipLoader()
    private let clip = AudioClip(samples: [0.1, 0.2, 0.3])

    private func makeService(_ reprocessor: FakeDictationReprocessor) -> RetryService {
        RetryService(repository: repository, loader: loader, reprocessor: reprocessor)
    }

    /// A failed record with its audio stored, whose style was email in a formal tone.
    private func failedRecord(status: DictationStatus = .failed) async throws -> DictationRecord {
        let id = UUID()
        let url = URL(filePath: "/audio/\(id.uuidString).caf")
        loader.set(clip, at: url)
        let record = DictationRecord(
            id: id, createdAt: Date(timeIntervalSince1970: 1_800_000_000), duration: .seconds(4), status: status,
            rawText: "old raw", cleanedText: "Old cleaned", finalText: "Old cleaned",
            asrProvider: ASRProviderID("parakeet-v3"), appName: "Mail", bundleID: "com.apple.mail", category: "email",
            tone: "formal", delivery: .notInserted, audioURL: url, failure: "timedOut.transcription")
        try await repository.insert(record)
        return record
    }

    @Test("retrying a failed record runs the stages again with its stored category and tone, and it becomes succeeded")
    func retryAFailure() async throws {
        let record = try await failedRecord()
        let reprocessor = FakeDictationReprocessor(
            result: .success(
                .text(
                    ReprocessedText(
                        rawText: "new raw", cleanedText: "New cleaned", finalText: "New cleaned",
                        asrProvider: ASRProviderID("parakeet-v3"), cleanerProvider: "foundation-models"))))

        let result = try await makeService(reprocessor).retry(record.id)

        guard case .completed(let updated) = result else {
            Issue.record("expected a completed retry, got \(result)")
            return
        }
        #expect(updated.status == .succeeded)
        #expect(updated.rawText == "new raw")
        #expect(updated.cleanedText == "New cleaned")
        #expect(updated.finalText == "New cleaned")
        #expect(updated.cleanerProvider == "foundation-models")
        #expect(updated.failure == nil)
        // The new text was not delivered anywhere, and the audio and the style stay as they were.
        #expect(updated.delivery == nil)
        #expect(updated.audioURL == record.audioURL)
        #expect(updated.category == "email")
        #expect(updated.tone == "formal")
        #expect(updated.createdAt == record.createdAt)
        #expect(try await repository.record(id: record.id) == updated)
        #expect(reprocessor.reprocessedRecords.map(\.category) == ["email"])
        #expect(reprocessor.reprocessedRecords.map(\.tone) == ["formal"])
        #expect(reprocessor.reprocessedClips == [clip])
    }

    @Test("a cancelled record can be retried too, and a recording with no speech ends as no speech")
    func cancelledAndNoSpeech() async throws {
        let cancelled = try await failedRecord(status: .cancelled)
        let reprocessor = FakeDictationReprocessor(result: .success(.noSpeech))

        let result = try await makeService(reprocessor).retry(cancelled.id)

        guard case .completed(let updated) = result else {
            Issue.record("expected a completed retry, got \(result)")
            return
        }
        #expect(updated.status == .noSpeech)
        #expect(updated.failure == nil)
    }

    @Test("a retry that fails leaves the record failed, with the name of the failure and the old text kept")
    func retryFails() async throws {
        let record = try await failedRecord()
        let reprocessor = FakeDictationReprocessor(result: .failure(PipelineError.recognitionFailed("secret words")))

        let result = try await makeService(reprocessor).retry(record.id)

        guard case .completed(let updated) = result else {
            Issue.record("expected a completed retry, got \(result)")
            return
        }
        #expect(updated.status == .failed)
        #expect(updated.failure == "recognitionFailed")
        #expect(updated.rawText == "old raw")
        #expect(updated.audioURL == record.audioURL)
        #expect(updated.hasAudio)
    }

    @Test("audio that cannot be read ends the retry as failed, and the record can be retried again")
    func unreadableAudio() async throws {
        let record = try await failedRecord()
        let missing = URL(filePath: "/audio/gone.caf")
        var broken = record
        broken.audioURL = missing
        try await repository.update(broken)

        let result = try await makeService(FakeDictationReprocessor(text: "x")).retry(record.id)

        guard case .completed(let updated) = result else {
            Issue.record("expected a completed retry, got \(result)")
            return
        }
        #expect(updated.status == .failed)
        #expect(updated.failure == "audioUnreadable")
        #expect(updated.audioURL == missing)
    }

    @Test("retry is refused with a reason when the audio expired, and nothing changes")
    func expiredAudio() async throws {
        var record = try await failedRecord()
        record.audioURL = nil
        record.audioExpired = true
        try await repository.update(record)
        let reprocessor = FakeDictationReprocessor(text: "x")

        let result = try await makeService(reprocessor).retry(record.id)

        #expect(result == .refused(.audioExpired))
        #expect(reprocessor.reprocessedRecords.isEmpty)
        #expect(try await repository.record(id: record.id) == record)
    }

    @Test("retry is refused for a record with no audio, one that is still processing, and one that is not there")
    func otherRefusals() async throws {
        var noAudio = try await failedRecord()
        noAudio.audioURL = nil
        try await repository.update(noAudio)
        let processing = try await failedRecord(status: .processing)
        let service = makeService(FakeDictationReprocessor(text: "x"))

        #expect(try await service.retry(noAudio.id) == .refused(.noAudio))
        #expect(try await service.retry(processing.id) == .refused(.stillProcessing))
        #expect(try await service.retry(UUID()) == .refused(.recordNotFound))
    }

    @Test("retry is refused for a command record, which stays as it was")
    func commandRefused() async throws {
        var command = try await failedRecord()
        command.kind = .command
        try await repository.update(command)
        let reprocessor = FakeDictationReprocessor(text: "x")

        let result = try await makeService(reprocessor).retry(command.id)

        #expect(result == .refused(.command))
        #expect(reprocessor.reprocessedRecords.isEmpty)
        #expect(try await repository.record(id: command.id) == command)
    }

    @Test("while a retry runs the record shows processing, and a second retry of it is refused")
    func processingWhileRetrying() async throws {
        let record = try await failedRecord()
        let reprocessor = FakeDictationReprocessor(text: "again", gated: true)
        let service = makeService(reprocessor)

        let first = Task { try await service.retry(record.id) }
        await reprocessor.entered.wait()
        #expect(try await repository.record(id: record.id)?.status == .processing)
        #expect(try await service.retry(record.id) == .refused(.alreadyRetrying))

        reprocessor.release()
        guard case .completed(let updated) = try await first.value else {
            Issue.record("expected the first retry to complete")
            return
        }
        #expect(updated.status == .succeeded)
        #expect(reprocessor.reprocessedRecords.count == 1)
    }

    @Test("a cancelled retry puts the record back as it was")
    func cancelledRetry() async throws {
        let record = try await failedRecord()
        let reprocessor = FakeDictationReprocessor(text: "again", gated: true)
        let service = makeService(reprocessor)

        let retry = Task { try await service.retry(record.id) }
        await reprocessor.entered.wait()
        retry.cancel()

        await #expect(throws: CancellationError.self) { try await retry.value }
        #expect(try await repository.record(id: record.id) == record)
        // It can be retried again.
        reprocessor.release()
        #expect(try await service.retry(record.id) != .refused(.alreadyRetrying))
    }

    @Test("a retry neither inserts nor holds back a live dictation that is being inserted at the same time")
    func retryDoesNotBlockLiveInsertion() async throws {
        let record = try await failedRecord()
        let reprocessor = FakeDictationReprocessor(text: "retried", gated: true)
        let service = makeService(reprocessor)
        let queue = ProcessingQueue()
        let inserter = FakeTextInserter()

        let retry = Task { try await service.retry(record.id) }
        await reprocessor.entered.wait()
        await queue.enqueue(UUID()) {
            _ = await inserter.insert("live dictation")
            return .succeeded
        }
        await queue.drain()
        #expect(inserter.insertedTexts == ["live dictation"])

        reprocessor.release()
        _ = try await retry.value
        #expect(inserter.insertedTexts == ["live dictation"])
        #expect(try await repository.record(id: record.id)?.rawText == "retried")
    }
}
