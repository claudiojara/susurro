import Domain
import Foundation

/// The user's dictionary, kept in the settings store as one list. A term is trimmed, cannot be empty, and cannot repeat
/// another one when case is ignored.
public final class SettingsDictionaryTerms: DictionaryTermStore {
    /// The longest term kept, in characters. The vocabulary sent to a recognizer is bounded to the same length.
    public static let termLimit = 40

    private let settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    private static let terms = SettingKey<[String]>.json(area: "dictionary", name: "terms", default: [])

    public static var keys: [any AnySettingKey] { [terms] }

    public func terms() -> [String] {
        settings.value(for: Self.terms)
    }

    public func add(_ term: String) throws {
        let clean = try Self.checked(term)
        var all = terms()
        guard !all.contains(where: { Self.same($0, clean) }) else { throw DictionaryTermError.duplicate }
        all.append(clean)
        settings.set(all, for: Self.terms)
    }

    public func edit(_ old: String, to new: String) throws {
        let clean = try Self.checked(new)
        var all = terms()
        guard let index = all.firstIndex(of: old) else { return }
        guard !all.enumerated().contains(where: { $0.offset != index && Self.same($0.element, clean) }) else {
            throw DictionaryTermError.duplicate
        }
        all[index] = clean
        settings.set(all, for: Self.terms)
    }

    public func remove(_ term: String) {
        var all = terms()
        all.removeAll { $0 == term }
        settings.set(all, for: Self.terms)
    }

    private static func checked(_ term: String) throws -> String {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { throw DictionaryTermError.empty }
        if clean.count > termLimit { throw DictionaryTermError.tooLong(limit: termLimit) }
        return clean
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }
}
