import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Testing

@Suite("Retention sweeper", .timeLimit(.minutes(1)))
struct RetentionSweeperTests {
    private static let day: TimeInterval = 86_400

    private let dates = FakeDateSource()
    private let repository = InMemoryHistoryRepository()
    private let deleter = FakeAudioFileDeleter()
    private let clock = ManualClock()

    private func makeSweeper() -> RetentionSweeper {
        RetentionSweeper(repository: repository, deleter: deleter, dates: dates, clock: clock)
    }

    /// A record `days` old with its audio stored.
    private func record(daysOld days: Double, status: DictationStatus = .succeeded) -> DictationRecord {
        let id = UUID()
        return DictationRecord(
            id: id, createdAt: dates.now().addingTimeInterval(-days * Self.day), duration: .seconds(3), status: status,
            rawText: "text", audioURL: URL(filePath: "/audio/\(id.uuidString).caf"))
    }

    @Test("audio of 8 days is deleted and the record shows it expired, while its text stays")
    func expiry() async throws {
        let old = record(daysOld: 8)
        try await repository.insert(old)

        let report = try await makeSweeper().sweep()

        #expect(deleter.deleted == [old.audioURL])
        let stored = try #require(try await repository.record(id: old.id))
        #expect(stored.audioExpired)
        #expect(stored.audioURL == nil)
        #expect(stored.rawText == "text")
        #expect(report == RetentionSweeper.Report(expired: 1, failed: 0))
    }

    @Test("audio of 6 days remains")
    func notYetExpired() async throws {
        let fresh = record(daysOld: 6)
        try await repository.insert(fresh)

        let report = try await makeSweeper().sweep()

        #expect(deleter.attempts.isEmpty)
        #expect(try await repository.record(id: fresh.id) == fresh)
        #expect(report == RetentionSweeper.Report(expired: 0, failed: 0))
    }

    @Test("the text of a record of 400 days is intact")
    func textIsKept() async throws {
        let ancient = record(daysOld: 400)
        try await repository.insert(ancient)

        try await makeSweeper().sweep()

        let stored = try #require(try await repository.record(id: ancient.id))
        #expect(stored.rawText == "text")
        #expect(stored.audioExpired)
        #expect(try await repository.page(offset: 0, limit: 10).count == 1)
    }

    @Test("a cancelled record expires like any other, and so does a failed one")
    func everyStatusExpires() async throws {
        let cancelled = record(daysOld: 9, status: .cancelled)
        let failed = record(daysOld: 9, status: .failed)
        try await repository.insert(cancelled)
        try await repository.insert(failed)

        let report = try await makeSweeper().sweep()

        #expect(report.expired == 2)
        #expect(Set(deleter.deleted) == [cancelled.audioURL, failed.audioURL])
    }

    @Test("a deletion that fails is retried on the next run, and the record is not marked until it works")
    func failedDeletionIsRetried() async throws {
        let old = record(daysOld: 8)
        let url = try #require(old.audioURL)
        try await repository.insert(old)
        deleter.setFailing([url])
        let sweeper = makeSweeper()

        let first = try await sweeper.sweep()
        #expect(first == RetentionSweeper.Report(expired: 0, failed: 1))
        #expect(try await repository.record(id: old.id) == old)

        deleter.setFailing([])
        let second = try await sweeper.sweep()
        #expect(second == RetentionSweeper.Report(expired: 1, failed: 0))
        #expect(deleter.attempts == [url, url])
        #expect(try await repository.record(id: old.id)?.audioExpired == true)
    }

    @Test("one file that cannot be deleted does not stop the others")
    func oneFailureDoesNotStopTheRest() async throws {
        let stuck = record(daysOld: 8)
        let fine = record(daysOld: 8)
        try await repository.insert(stuck)
        try await repository.insert(fine)
        deleter.setFailing([try #require(stuck.audioURL)])

        let report = try await makeSweeper().sweep()

        #expect(report == RetentionSweeper.Report(expired: 1, failed: 1))
        #expect(try await repository.record(id: fine.id)?.audioExpired == true)
        #expect(try await repository.record(id: stuck.id)?.audioExpired == false)
    }

    @Test("it sweeps when it starts and again every 6 hours")
    func runsAtLaunchAndEverySixHours() async throws {
        let first = record(daysOld: 8)
        try await repository.insert(first)
        let sweeper = makeSweeper()

        let running = Task { await sweeper.run() }
        await clock.waitForSleeps(1)
        #expect(deleter.deleted == [first.audioURL])

        let second = record(daysOld: 8)
        try await repository.insert(second)
        clock.advance(by: .seconds(6 * 3600) - .seconds(1))
        #expect(deleter.deleted == [first.audioURL])

        clock.advance(by: .seconds(1))
        await clock.waitForSleeps(2)
        #expect(deleter.deleted == [first.audioURL, second.audioURL])

        running.cancel()
        await running.value
    }

    @Test("a history that cannot be read does not stop the schedule")
    func unreadableHistoryDoesNotStopTheSchedule() async throws {
        struct Unreadable: Error {}
        repository.failAllCalls(with: Unreadable())
        let sweeper = makeSweeper()

        let running = Task { await sweeper.run() }
        await clock.waitForSleeps(1)
        repository.failAllCalls(with: nil)
        let old = record(daysOld: 8)
        try await repository.insert(old)
        clock.advance(by: .seconds(6 * 3600))
        await clock.waitForSleeps(2)

        #expect(deleter.deleted == [old.audioURL])
        running.cancel()
        await running.value
    }
}
