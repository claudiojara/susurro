import CoreTestSupport
import Domain
import Foundation
import Settings
import Testing

/// The raw values differ from the case names, so a store that wrote the case name instead would be caught.
enum SampleEdge: String, Sendable {
    case top = "screen-top"
    case bottom = "screen-bottom"
}

struct SampleCombo: Codable, Sendable, Equatable {
    var keyCode: Int
    var modifiers: [String]
}

/// A value that can be turned into its stored form only while `storable` is true.
struct SamplePicky: Codable, Sendable, Equatable {
    var storable: Bool
    var label: String

    func encode(to encoder: any Encoder) throws {
        guard storable else {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "never stored"))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storable, forKey: .storable)
        try container.encode(label, forKey: .label)
    }
}

/// One key of each kind the store handles. Every default differs from what a failed read could produce by accident
/// (false, 0, an empty string), so a read that falls back to the default is told from one that returned garbage.
enum SampleKeys {
    static let defaultCombo = SampleCombo(keyCode: 2, modifiers: ["control", "option"])

    static let launchAtLogin = SettingKey<Bool>(area: "general", name: "launchAtLogin", default: true)
    static let retentionDays = SettingKey<Int>(area: "history", name: "retentionDays", default: 7)
    static let holdThreshold = SettingKey<Double>(area: "hotkey", name: "holdThreshold", default: 0.3)
    static let language = SettingKey<String>(area: "speech", name: "language", default: "auto")
    static let overlayEdge = SettingKey<SampleEdge>(area: "overlay", name: "edge", default: .bottom)
    static let combo = SettingKey<SampleCombo>.json(area: "hotkey", name: "combo", default: defaultCombo)
    static let picky = SettingKey<SamplePicky>.json(
        area: "debug", name: "picky", default: SamplePicky(storable: true, label: "none"))
}

/// Preferences of their own for one test, so it never touches the real ones or another test. `makeDefaults()` opens
/// them: a second call is what a relaunch sees, and a test writes through one the way a person or an older version of
/// the app would.
struct ScratchDefaults: Sendable {
    let suiteName = "dev.claudiojara.susurro.tests.\(UUID().uuidString)"

    func makeDefaults() -> UserDefaults { UserDefaults(suiteName: suiteName)! }

    func remove() { makeDefaults().removePersistentDomain(forName: suiteName) }
}

/// The two implementations of the port, which the same tests must hold for.
enum StoreKind: CaseIterable, Sendable, CustomTestStringConvertible {
    case userDefaults
    case inMemory

    var testDescription: String {
        switch self {
        case .userDefaults: "UserDefaultsSettingsStore"
        case .inMemory: "InMemorySettingsStore"
        }
    }

    func withStore(_ body: (any SettingsStore) async throws -> Void) async rethrows {
        switch self {
        case .userDefaults:
            let scratch = ScratchDefaults()
            defer { scratch.remove() }
            try await body(UserDefaultsSettingsStore(defaults: scratch.makeDefaults()))
        case .inMemory:
            try await body(InMemorySettingsStore())
        }
    }
}

/// A value stored as one kind of number and read as another. The two keys share a storage name, so the second reads what
/// the first wrote, as an older version of the app or a person editing the preferences would leave it. Each read default
/// differs from what a coerced read would give (1 as a Bool is true, true as an Int is 1, 5 as a Double is 5.0), so a
/// store that converts is told from one that falls back to the default.
struct Coercion: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let check: @Sendable (any SettingsStore) -> Void

    private init<Written: SettingStorable & Equatable, Read: SettingStorable & Equatable>(
        _ description: String, written: Written, otherwise: Written, readDefault: Read
    ) {
        let writer = SettingKey<Written>(area: "coercion", name: "number", default: otherwise)
        let reader = SettingKey<Read>(area: "coercion", name: "number", default: readDefault)
        testDescription = description
        check = { store in
            store.set(written, for: writer)
            #expect(store.value(for: writer) == written)
            #expect(store.value(for: reader) == readDefault)
        }
    }

    static let all: [Coercion] = [
        Coercion("an Int is not a Bool", written: 1, otherwise: 0, readDefault: false),
        Coercion("a Bool is not an Int", written: true, otherwise: false, readDefault: 7),
        Coercion("an Int is not a Double", written: 5, otherwise: 0, readDefault: 0.3),
        Coercion("a Double is not an Int", written: 2.0, otherwise: 0.0, readDefault: 7),
        Coercion("a Double is not a Bool", written: 1.0, otherwise: 0.0, readDefault: false),
        Coercion("a Bool is not a Double", written: true, otherwise: false, readDefault: 0.3),
    ]
}
