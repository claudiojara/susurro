import Foundation
import Synchronization

/// A setting key whatever its value type, for code that handles a list of keys, as a check that none share a name.
public protocol AnySettingKey: Sendable {
    var storageName: String { get }
}

/// A part of a key name: the area or the name.
enum SettingKeyPart {
    /// Whether `part` can be one. A dot would let two different keys be stored under one name (`a.b` and `c` against `a`
    /// and `b.c`), and an empty part would hide that a key lacks an area or a name.
    static func isValid(_ part: String) -> Bool {
        !part.isEmpty && !part.contains(".")
    }
}

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
/// form. Neither part may be empty or contain a dot, so that no two keys share a storage name by accident; a key that
/// breaks the rule stops the app where it is declared.
public struct SettingKey<Value: Sendable>: Sendable, AnySettingKey {
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
        precondition(
            SettingKeyPart.isValid(area), "A setting key needs an area that is not empty and has no dot: \(area)")
        precondition(
            SettingKeyPart.isValid(name), "A setting key needs a name that is not empty and has no dot: \(name)")
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

extension SettingKey {
    /// The value for the stored form a store holds under this key, or nil when it holds none. A stored form that does
    /// not read as a `Value` gives the default and is recorded in `diagnostics`, by the name of the key and never by what
    /// it holds.
    public func value(stored: Any?, reportingTo diagnostics: any DiagnosticsLog) -> Value {
        guard let stored else { return defaultValue }
        if let value = decode(stored) { return value }
        diagnostics.record(.settingUnreadable(key: storageName))
        return defaultValue
    }

    /// The stored form of a value. A value with no stored form gives nil and is recorded in `diagnostics`, by the name
    /// of the key and never by the value.
    public func storedForm(of value: Value, reportingTo diagnostics: any DiagnosticsLog) -> (any Sendable)? {
        let stored = encode(value)
        if stored == nil { diagnostics.record(.settingNotStored(key: storageName)) }
        return stored
    }
}

/// A setting that was set or removed, named by the `storageName` of its key. A subscriber reads the key again for the
/// new value, or uses `SettingsStore.values(for:)`, which does it.
public struct SettingChange: Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// The user's settings, one value per key. Reading never fails: a key nobody set, or one that holds something that is
/// not its type, gives the key's default, and a damaged key cannot affect another. What a store would otherwise swallow
/// is recorded in its `DiagnosticsLog`, by key name only: a value that cannot be stored, which `set` leaves out, and a
/// stored value that cannot be read, which reads as the default.
///
/// A store is a class: a stream made from it must be able to hold it weakly, so that a stream a consumer keeps does not
/// keep the store alive.
public protocol SettingsStore: AnyObject, Sendable {
    func value<Value>(for key: SettingKey<Value>) -> Value
    func set<Value>(_ value: Value, for key: SettingKey<Value>)
    /// Deletes what the key holds, so it reads as its default again, as if nobody had set it. Storing the default is not
    /// a removal: the key would then hold a value of its own that a later change of the default would not reach. It
    /// clears a value the key cannot read too. The key is announced even when it held nothing.
    func remove<Value>(_ key: SettingKey<Value>)
    /// Each call returns a stream of its own, which gets the sets and removals made after the call.
    func changes() -> AsyncStream<SettingChange>
}

extension SettingsStore {
    /// The value of `key` each time the key is set or removed, as a `Value`, so a consumer never compares key names.
    /// A value is read when the consumer takes it, never when the change was made, so it is not older than the last
    /// change. Other keys are skipped.
    ///
    /// The stream does not begin with the current value, which `value(for:)` gives. The subscription starts when this
    /// is called, so a change made after the call is not missed whichever of the two the caller runs first. The stream
    /// ends when the store goes away; it does not keep the store alive.
    public func values<Value>(for key: SettingKey<Value>) -> AsyncStream<Value> {
        var changes = changes().makeAsyncIterator()
        let name = key.storageName
        return AsyncStream(unfolding: { [weak self] in
            while let change = await changes.next() {
                guard change.name == name else { continue }
                return self?.value(for: key)
            }
            return nil
        })
    }
}

/// Hands each change to every subscriber, and ends every stream when it is released. The stores that implement `SettingsStore` share it.
public final class SettingChangeBroadcaster: Sendable {
    private struct State {
        var nextID = 0
        var subscribers: [Int: AsyncStream<SettingChange>.Continuation] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    deinit {
        // The streams end instead of waiting for a change that can no longer come. What they already hold is delivered.
        let subscribers = state.withLock { Array($0.subscribers.values) }
        for subscriber in subscribers { subscriber.finish() }
    }

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
