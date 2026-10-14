import Domain
import Foundation
import Synchronization

/// A settings store that keeps the stored forms of the values in memory, as the real store keeps them on disk, so a
/// value of the wrong type reads as the default here too, and is recorded in the log.
public final class InMemorySettingsStore: SettingsStore {
    private let stored = Mutex<[String: any Sendable]>([:])
    private let diagnostics: any DiagnosticsLog
    private let broadcaster = SettingChangeBroadcaster()

    public init(diagnostics: any DiagnosticsLog = NoDiagnostics()) {
        self.diagnostics = diagnostics
    }

    public func value<Value>(for key: SettingKey<Value>) -> Value {
        let form = stored.withLock { $0[key.storageName] }
        return key.value(stored: form, reportingTo: diagnostics)
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        guard let encoded = key.storedForm(of: value, reportingTo: diagnostics) else { return }
        stored.withLock { $0[key.storageName] = encoded }
        broadcaster.send(SettingChange(name: key.storageName))
    }

    public func remove<Value>(_ key: SettingKey<Value>) {
        stored.withLock { _ = $0.removeValue(forKey: key.storageName) }
        broadcaster.send(SettingChange(name: key.storageName))
    }

    public func changes() -> AsyncStream<SettingChange> { broadcaster.stream() }
}
