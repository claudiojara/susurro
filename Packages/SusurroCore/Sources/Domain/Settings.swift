import Foundation
import Synchronization

/// A type a setting can hold as it is stored, one that a property list keeps as itself.
public protocol SettingStorable: Sendable {}
extension Bool: SettingStorable {}
extension Int: SettingStorable {}
extension Double: SettingStorable {}
extension String: SettingStorable {}

/// One setting: where it is stored, what it is when nobody set it, and how its value goes to and from the stored form.
/// A stored value that does not read back as `Value` is ignored and the default is used instead.
///
/// A key is named by its area, the part of the app the setting belongs to (`hotkey`, `overlay`, `history`), and its
/// name in camel case, and is stored as `<area>.<name>`. Declaring the two parts apart is what keeps every key in that
/// form.
public struct SettingKey<Value: Sendable>: Sendable {
    public let storageName: String
    public let defaultValue: Value
    private let encoder: @Sendable (Value) -> (any Sendable)?
    private let decoder: @Sendable (Any) -> Value?

    private init(
        area: String,
        name: String,
        defaultValue: Value,
        encoder: @escaping @Sendable (Value) -> (any Sendable)?,
        decoder: @escaping @Sendable (Any) -> Value?
    ) {
        storageName = "\(area).\(name)"
        self.defaultValue = defaultValue
        self.encoder = encoder
        self.decoder = decoder
    }

    /// The stored form of a value, or nil for a value that cannot be stored.
    public func encode(_ value: Value) -> (any Sendable)? { encoder(value) }

    /// The value a stored form stands for, or nil when it is not one.
    public func decode(_ stored: Any) -> Value? { decoder(stored) }
}

extension SettingKey where Value: SettingStorable {
    /// A setting stored as itself.
    public init(area: String, name: String, default defaultValue: Value) {
        self.init(
            area: area,
            name: name,
            defaultValue: defaultValue,
            encoder: { $0 },
            decoder: { StoredScalar.read($0, as: Value.self) }
        )
    }
}

extension SettingKey where Value: RawRepresentable, Value.RawValue: SettingStorable {
    /// A setting stored as the raw value of an enum.
    public init(area: String, name: String, default defaultValue: Value) {
        self.init(
            area: area,
            name: name,
            defaultValue: defaultValue,
            encoder: { $0.rawValue },
            decoder: { StoredScalar.read($0, as: Value.RawValue.self).flatMap(Value.init(rawValue:)) }
        )
    }
}

extension SettingKey where Value: Codable {
    /// A setting stored as JSON data.
    public static func json(area: String, name: String, default defaultValue: Value) -> SettingKey {
        SettingKey(
            area: area,
            name: name,
            defaultValue: defaultValue,
            encoder: { try? JSONEncoder().encode($0) },
            decoder: { ($0 as? Data).flatMap { try? JSONDecoder().decode(Value.self, from: $0) } }
        )
    }
}

/// A setting that was set, named by the `storageName` of its key. A subscriber reads the key again for the new value.
public struct SettingChange: Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// The user's settings, one value per key. Reading never fails: a key nobody set, or one that holds something that is
/// not its type, gives the key's default, and a damaged key cannot affect another.
public protocol SettingsStore: Sendable {
    func value<Value>(for key: SettingKey<Value>) -> Value
    func set<Value>(_ value: Value, for key: SettingKey<Value>)
    /// Each call returns a stream of its own, which gets the sets made after the call.
    func changes() -> AsyncStream<SettingChange>
}

/// Hands each change to every subscriber. The stores that implement `SettingsStore` share it.
public final class SettingChangeBroadcaster: Sendable {
    private struct State {
        var nextID = 0
        var subscribers: [Int: AsyncStream<SettingChange>.Continuation] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    var subscriberCount: Int { state.withLock { $0.subscribers.count } }

    /// A stream of the changes sent from now on. It stays subscribed until its consumer stops or its task is cancelled.
    public func stream() -> AsyncStream<SettingChange> {
        AsyncStream { continuation in
            let id = state.withLock { state in
                let id = state.nextID
                state.nextID += 1
                state.subscribers[id] = continuation
                return id
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
            }
        }
    }

    public func send(_ change: SettingChange) {
        let subscribers = state.withLock { Array($0.subscribers.values) }
        for subscriber in subscribers { subscriber.yield(change) }
    }
}
