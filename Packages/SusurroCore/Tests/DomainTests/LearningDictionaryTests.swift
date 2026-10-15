import CoreTestSupport
import Domain
import Foundation
import Testing

@Suite("Learning dictionary settings")
struct LearningDictionaryTests {
    @Test("learning from corrections is on by default, and the lists start empty")
    func defaults() {
        let settings = InMemorySettingsStore()

        #expect(settings.value(for: DictionarySettings.learnFromCorrections))
        #expect(settings.value(for: DictionarySettings.suggestions).isEmpty)
        #expect(settings.value(for: DictionarySettings.dismissed).isEmpty)
    }

    @Test("the keys are stored under the dictionary area, and no two share a name")
    func keys() throws {
        #expect(DictionarySettings.learnFromCorrections.storageName == "dictionary.learnFromCorrections")
        #expect(DictionarySettings.suggestions.storageName == "dictionary.suggestions")
        #expect(DictionarySettings.dismissed.storageName == "dictionary.dismissed")
        try requireUniqueStorageNames(DictionarySettings.all)
    }

    @Test("a suggestion keeps the term, what was heard, a count, and a date: nothing of the field around it")
    func storedFields() {
        let suggestion = DictionarySuggestion(
            term: "Kaelthorn", heard: "Kyle Thorn", firstSeen: Date(timeIntervalSince1970: 0))
        let labels = Mirror(reflecting: suggestion).children.compactMap(\.label)

        #expect(labels == ["term", "heard", "count", "firstSeen"])
    }

    @Test("a suggestion survives the settings store, and its id ignores case")
    func roundTrip() {
        let settings = InMemorySettingsStore()
        let suggestion = DictionarySuggestion(
            term: "Kaelthorn", heard: "Kyle Thorn", count: 2, firstSeen: Date(timeIntervalSince1970: 100))

        settings.set([suggestion], for: DictionarySettings.suggestions)

        #expect(settings.value(for: DictionarySettings.suggestions) == [suggestion])
        #expect(suggestion.id == "kaelthorn")
    }
}
