import Domain
import Foundation
import Synchronization

/// The suggested terms and the dismissed ones, kept as two settings of the dictionary area (`dictionary.suggestions`,
/// `dictionary.dismissed`), so they persist with the other settings. Several stores over one settings store share one
/// lock, so the watch that records and the settings screen that accepts or dismisses cannot lose each other's change.
public final class SuggestionStore: DictionarySuggestionStore {
    private static let edits = Mutex(())
    private let settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    public func suggestions() -> [DictionarySuggestion] {
        settings.value(for: DictionarySettings.suggestions)
    }

    public func dismissed() -> [String] {
        settings.value(for: DictionarySettings.dismissed)
    }

    public func record(term: String, heard: String, at date: Date) {
        let key = term.lowercased()
        Self.edits.withLock { _ in
            guard !dismissed().contains(where: { $0.lowercased() == key }) else { return }
            var list = suggestions()
            if let index = list.firstIndex(where: { $0.id == key }) {
                list[index].count += 1
            } else {
                list.append(DictionarySuggestion(term: term, heard: heard, firstSeen: date))
                list.sort { $0.firstSeen < $1.firstSeen }
                if list.count > DictionarySuggestionLimits.maxSuggestions {
                    list.removeFirst(list.count - DictionarySuggestionLimits.maxSuggestions)
                }
            }
            settings.set(list, for: DictionarySettings.suggestions)
        }
    }

    public func remove(_ term: String) {
        Self.edits.withLock { _ in drop(term) }
    }

    public func dismiss(_ term: String) {
        let key = term.lowercased()
        Self.edits.withLock { _ in
            drop(term)
            var list = dismissed()
            guard !list.contains(where: { $0.lowercased() == key }) else { return }
            list.append(term)
            if list.count > DictionarySuggestionLimits.maxDismissed {
                list.removeFirst(list.count - DictionarySuggestionLimits.maxDismissed)
            }
            settings.set(list, for: DictionarySettings.dismissed)
        }
    }

    /// Removes the suggestion of `term`, under the lock the caller holds.
    private func drop(_ term: String) {
        let key = term.lowercased()
        var list = suggestions()
        guard let index = list.firstIndex(where: { $0.id == key }) else { return }
        list.remove(at: index)
        settings.set(list, for: DictionarySettings.suggestions)
    }
}
