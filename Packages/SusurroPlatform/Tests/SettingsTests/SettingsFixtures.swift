import CoreTestSupport
import Domain
import Foundation
import Settings

enum SampleEdge: String, Sendable {
    case top
    case bottom
}

struct SampleCombo: Codable, Sendable, Equatable {
    var keyCode: Int
    var modifiers: [String]
}

/// One key of each kind the store handles. Every default differs from what a failed read could produce by accident
/// (false, 0, an empty string), so a read that falls back to the default is told from one that returned garbage.
enum SampleKeys {
    static let defaultCombo = SampleCombo(keyCode: 2, modifiers: ["control", "option"])

    static let launchAtLogin = SettingKey<Bool>("general.launchAtLogin", default: true)
    static let retentionDays = SettingKey<Int>("history.retentionDays", default: 7)
    static let holdThreshold = SettingKey<Double>("hotkey.holdThreshold", default: 0.3)
    static let language = SettingKey<String>("speech.language", default: "auto")
    static let overlayEdge = SettingKey<SampleEdge>("overlay.edge", default: .bottom)
    static let combo = SettingKey<SampleCombo>.json("hotkey.combo", default: defaultCombo)
}

/// Preferences of their own for one test, so it never touches the real ones or another test, and a place to write
/// values the way a person or an older version of the app would.
final class ScratchDefaults: Sendable {
    let suiteName = "dev.claudiojara.susurro.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    /// What a relaunch sees: a new object over the same stored preferences.
    func reopened() -> UserDefaults { UserDefaults(suiteName: suiteName)! }

    func remove() { defaults.removePersistentDomain(forName: suiteName) }
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
            try await body(UserDefaultsSettingsStore(defaults: scratch.defaults))
        case .inMemory:
            try await body(InMemorySettingsStore())
        }
    }
}
