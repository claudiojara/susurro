import CoreTestSupport
import DesignSystem
import Domain
import Foundation
import Presentation
import Testing

@testable import Composition

/// A history window that counts how many times it was shown.
@MainActor
final class SpyHistoryWindow: HistorySurface {
    private(set) var shown = 0

    func show() { shown += 1 }
}

/// What the app does with the history when it starts: recover the attempts a quit left unfinished, run the retention job,
/// follow the repository for the screen, and open the window from the menu.
@MainActor
@Suite("App environment history", .timeLimit(.minutes(1)))
struct AppEnvironmentHistoryTests {
    private static let day: TimeInterval = 86_400

    private let repository = InMemoryHistoryRepository()
    private let deleter = FakeAudioFileDeleter()
    private let dates = FakeDateSource()
    private let window = SpyHistoryWindow()

    private func makeFixture() -> AppEnvironmentFixture {
        let window = window
        return AppEnvironmentFixture(
            history: HistoryDependencies(
                repository: repository, deleter: deleter, loader: FakeAudioClipLoader(), clipboard: FakeClipboardWriter(),
                reprocessor: FakeDictationReprocessor(text: "again"), dates: dates, window: { _, _ in window }))
    }

    private func record(
        _ status: DictationStatus = .succeeded, daysOld: Double = 0, audio: Bool = true
    ) -> DictationRecord {
        let id = UUID()
        return DictationRecord(
            id: id, createdAt: dates.now().addingTimeInterval(-daysOld * Self.day), duration: .seconds(3),
            status: status, rawText: "text", audioURL: audio ? URL(filePath: "/audio/\(id.uuidString).caf") : nil)
    }

    @Test("an attempt that a quit left processing is marked failed at launch, with its audio kept for a retry")
    func interruptedAttemptsAreRecovered() async throws {
        let stale = record(.processing, daysOld: 0.5)
        try await repository.insert(stale)
        let f = makeFixture()

        f.environment.start()
        await f.eventually("the recovery") { repository.allRecords.first?.status == .failed }

        let recovered = try #require(repository.allRecords.first)
        #expect(recovered.failure == DictationRecord.interruptedFailure)
        #expect(recovered.audioURL == stale.audioURL)
        await f.environment.shutdown()
    }

    @Test("the retention job runs at launch, and again after 6 hours")
    func retentionRuns() async throws {
        let first = record(daysOld: 8)
        try await repository.insert(first)
        let f = makeFixture()

        f.environment.start()
        await f.eventually("the first sweep") { deleter.deleted == [first.audioURL] }

        let second = record(daysOld: 9)
        try await repository.insert(second)
        await f.advance(by: .seconds(6 * 3_600), until: "the second sweep") { deleter.deleted.count == 2 }

        #expect(Set(deleter.deleted) == [first.audioURL, second.audioURL])
        #expect(repository.allRecords.allSatisfy { $0.audioExpired })
        await f.environment.shutdown()
    }

    @Test("the history screen follows the repository once the app has started")
    func historyModelFollowsTheRepository() async throws {
        let f = makeFixture()
        f.environment.start()

        try await repository.insert(record())
        await f.eventually("the row") { f.environment.historyModel.state.rows.count == 1 }

        #expect(f.environment.historyModel.state.rows.first?.status == .succeeded)
        await f.environment.shutdown()
    }

    @Test("the menu's History item opens the history window")
    func menuOpensTheWindow() async {
        let f = makeFixture()

        f.environment.menu.openHistory()
        f.environment.menu.openHistory()

        #expect(window.shown == 2)
        await f.environment.shutdown()
    }
}
