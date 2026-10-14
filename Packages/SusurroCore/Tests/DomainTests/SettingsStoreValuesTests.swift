import Domain
import Synchronization
import Testing

/// A store whose changes the test feeds by hand. Each read answers how many reads have been made, so the values a
/// stream yields show how many times it read.
private final class ScriptedStore: SettingsStore {
    private let source: AsyncStream<SettingChange>
    private let feed: AsyncStream<SettingChange>.Continuation
    private let reads = Mutex(0)

    init() {
        (source, feed) = AsyncStream.makeStream()
    }

    func send(_ name: String) { feed.yield(SettingChange(name: name)) }
    func end() { feed.finish() }

    func value<Value>(for key: SettingKey<Value>) -> Value {
        let count = reads.withLock { reads in
            reads += 1
            return reads
        }
        return key.decode(count) ?? key.defaultValue
    }

    func set<Value>(_ value: Value, for key: SettingKey<Value>) {}
    func remove<Value>(_ key: SettingKey<Value>) {}
    func changes() -> AsyncStream<SettingChange> { source }
}

@Suite("Settings store value streams", .timeLimit(.minutes(1)))
struct SettingsStoreValuesTests {
    private static let days = SettingKey<Int>(area: "history", name: "retentionDays", default: -1)

    @Test("a stream yields one fresh read for each change of its key, and nothing for the other keys")
    func oneReadPerChangeOfTheKey() async {
        let store = ScriptedStore()
        let values = store.values(for: Self.days)
        store.send("overlay.edge")
        store.send("history.retentionDays")
        store.send("history.retentionDaysLimit")
        store.send("retentionDays")
        store.send("history.retentionDays")
        store.end()

        var seen: [Int] = []
        for await value in values { seen.append(value) }

        #expect(seen == [1, 2])
    }
}
