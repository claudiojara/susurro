import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Testing

@Suite("Suggestion store")
struct SuggestionStoreTests {
    private let settings = InMemorySettingsStore()
    private var store: SuggestionStore { SuggestionStore(settings: settings) }
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a new term is added once, and a repeat counts it again, case ignored")
    func recordAndCount() {
        store.record(term: "Kaelthorn", heard: "Kyle Thorn", at: Self.day)
        store.record(term: "kaelthorn", heard: "Kale Thorn", at: Self.day.addingTimeInterval(60))

        #expect(
            store.suggestions() == [
                DictionarySuggestion(term: "Kaelthorn", heard: "Kyle Thorn", count: 2, firstSeen: Self.day)
            ])
    }

    @Test("the list keeps at most 20, and the oldest goes first")
    func eviction() {
        for index in 0...DictionarySuggestionLimits.maxSuggestions {
            store.record(term: "Term\(index)", heard: "heard", at: Self.day.addingTimeInterval(Double(index)))
        }

        let terms = store.suggestions().map(\.term)
        #expect(terms.count == DictionarySuggestionLimits.maxSuggestions)
        #expect(terms.first == "Term1")
        #expect(terms.last == "Term\(DictionarySuggestionLimits.maxSuggestions)")
    }

    @Test("an accepted suggestion is removed, and may be suggested again later")
    func remove() {
        store.record(term: "Kaelthorn", heard: "Kyle Thorn", at: Self.day)
        store.remove("KAELTHORN")

        #expect(store.suggestions().isEmpty)
        #expect(store.dismissed().isEmpty)
    }

    @Test("a dismissed term is removed, kept in the dismissed list, and never recorded again")
    func dismiss() {
        store.record(term: "Kaelthorn", heard: "Kyle Thorn", at: Self.day)
        store.dismiss("Kaelthorn")
        store.record(term: "kaelthorn", heard: "Kyle Thorn", at: Self.day)

        #expect(store.suggestions().isEmpty)
        #expect(store.dismissed() == ["Kaelthorn"])
        store.dismiss("kaelthorn")
        #expect(store.dismissed() == ["Kaelthorn"])
    }

    @Test("the lists are the settings of the dictionary area")
    func persisted() {
        store.record(term: "Kaelthorn", heard: "Kyle Thorn", at: Self.day)
        store.dismiss("Shaun")

        #expect(settings.value(for: DictionarySettings.suggestions).map(\.term) == ["Kaelthorn"])
        #expect(settings.value(for: DictionarySettings.dismissed) == ["Shaun"])
    }
}
