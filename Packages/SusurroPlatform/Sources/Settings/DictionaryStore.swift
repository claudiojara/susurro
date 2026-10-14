import Domain
import Foundation
import Synchronization

/// The user's dictionary: names and words the recognizer and the cleaner should get right. The list is one setting
/// (`dictionary.terms`), so it persists with the other settings and survives a relaunch. Terms keep the spelling the user
/// typed; two terms that differ only in case are one term.
public final class DictionaryStore: UserDictionary, DictionaryTermStore {
    private let settings: any SettingsStore
    /// Serializes a read-change-write, so two edits at once cannot lose one of them.
    private let edits = Mutex(())

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    public func terms() -> [String] {
        settings.value(for: DictionarySettings.terms)
    }

    /// Adds a term at the end of the list.
    public func add(_ term: String) throws {
        try edit { terms in
            let term = try Self.validated(term)
            guard !Self.contains(term, in: terms) else { throw DictionaryError.duplicate }
            terms.append(term)
        }
    }

    /// Replaces `old` with `new`, in the same place. A new spelling of the same term (only the case differs) is allowed.
    public func replace(_ old: String, with new: String) throws {
        try edit { terms in
            guard let index = Self.index(of: old, in: terms) else { throw DictionaryError.notFound }
            let new = try Self.validated(new)
            var others = terms
            others.remove(at: index)
            guard !Self.contains(new, in: others) else { throw DictionaryError.duplicate }
            terms[index] = new
        }
    }

    /// Replaces `old` with `new` for the settings screen, where a term that is gone already changes nothing.
    public func edit(_ old: String, to new: String) throws {
        do {
            try replace(old, with: new)
        } catch DictionaryError.notFound {
            return
        }
    }

    /// Removes the term. A term that is not in the list is ignored.
    public func remove(_ term: String) {
        try? edit { terms in
            guard let index = Self.index(of: term, in: terms) else { return }
            terms.remove(at: index)
        }
    }

    private func edit(_ change: (inout [String]) throws -> Void) throws {
        try edits.withLock { _ in
            var terms = settings.value(for: DictionarySettings.terms)
            try change(&terms)
            settings.set(terms, for: DictionarySettings.terms)
        }
    }

    private static func validated(_ term: String) throws -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.empty }
        guard trimmed.count <= VocabularyLimits.maxTermLength else { throw DictionaryError.tooLong }
        return trimmed
    }

    private static func index(of term: String, in terms: [String]) -> Int? {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return terms.firstIndex { $0.lowercased() == key }
    }

    private static func contains(_ term: String, in terms: [String]) -> Bool {
        index(of: term, in: terms) != nil
    }
}
