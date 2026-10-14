import CoreTestSupport
import Domain
import Testing
import TextShaping

@testable import Pipeline

@Suite("Dictionary surroundings")
struct DictionarySurroundingsTests {
    private struct Terms: UserDictionary {
        let list: [String]
        func terms() -> [String] { list }
    }

    @Test("the dictionary is the vocabulary, with the style of an unknown app and no text around the cursor")
    func dictionaryOnly() async {
        let source = DictionarySurroundings(
            dictionary: Terms(list: ["Acme", "acme", "Maria Gonzalez"]),
            builder: VocabularyBuilder(tagger: FakeEntityTagger()))
        let surroundings = await source.surroundings()
        #expect(surroundings.vocabulary == ["Acme", "Maria Gonzalez"])
        #expect(surroundings.cursor == nil)
        #expect(surroundings.style == StyleProfile(category: .other, tone: .neutral))
    }

    @Test("an empty dictionary gives an empty vocabulary")
    func emptyDictionary() async {
        let source = DictionarySurroundings(
            dictionary: Terms(list: []), builder: VocabularyBuilder(tagger: FakeEntityTagger()))
        #expect(await source.surroundings() == .unknown)
    }
}
