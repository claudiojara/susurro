import Domain
import Foundation
import Synchronization

/// Keeps each setting in `UserDefaults` under its own key, so a damaged value affects only its own setting. A value
/// that cannot be read as the key's type is ignored and the default is used.
public final class UserDefaultsSettingsStore: SettingsStore {
    // `UserDefaults` is not marked `Sendable` in the SDK, so the store holds it behind a lock instead of claiming it.
    private let defaults: Mutex<UserDefaults>
    private let broadcaster = SettingChangeBroadcaster()

    /// `defaults` is the app's own preferences unless a test passes a suite of its own.
    public init(defaults: sending UserDefaults = .standard) {
        self.defaults = Mutex(defaults)
    }

    public func value<Value>(for key: SettingKey<Value>) -> Value {
        defaults.withLock { $0.object(forKey: key.storageName).flatMap { key.decode($0) } } ?? key.defaultValue
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        guard let encoded = key.encode(value) else { return }
        defaults.withLock { $0.set(encoded, forKey: key.storageName) }
        broadcaster.send(SettingChange(name: key.storageName))
    }

    public func changes() -> AsyncStream<SettingChange> { broadcaster.stream() }
}
