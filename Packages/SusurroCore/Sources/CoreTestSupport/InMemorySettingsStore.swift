import Domain
import Foundation
import Synchronization

/// A settings store that keeps the stored forms of the values in memory, as the real store keeps them on disk, so a
/// value of the wrong type reads as the default here too.
public final class InMemorySettingsStore: SettingsStore {
    private let stored = Mutex<[String: any Sendable]>([:])
    private let broadcaster = SettingChangeBroadcaster()

    public init() {}

    public func value<Value>(for key: SettingKey<Value>) -> Value {
        stored.withLock { values in values[key.storageName].flatMap { key.decode($0) } } ?? key.defaultValue
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        guard let encoded = key.encode(value) else { return }
        stored.withLock { $0[key.storageName] = encoded }
        broadcaster.send(SettingChange(name: key.storageName))
    }

    public func changes() -> AsyncStream<SettingChange> { broadcaster.stream() }
}
