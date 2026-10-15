import CoreTestSupport
import Testing
import TextShaping

@Suite("Suggestion filter")
struct SuggestionFilterTests {
    private static let text = "the region the user edited"

    private static func accepts(
        _ heard: String, _ corrected: String, known: [String] = [], tagged: [String] = []
    ) -> Bool {
        let filter = SuggestionFilter(tagger: FakeEntityTagger([text: tagged]))
        return filter.accepts(WordCorrection(heard: heard, corrected: corrected), in: text, known: known)
    }

    @Test(
        "a mishearing of a name is a term worth suggesting",
        arguments: [("Kyle Thorn", "Kaelthorn"), ("Ramon", "Ramón"), ("get hub", "GitHub"), ("Sean", "Shaun")])
    func mishearing(heard: String, corrected: String) {
        #expect(Self.accepts(heard, corrected))
    }

    @Test(
        "the corrected word must be 5 to 40 characters",
        arguments: [("Jon", "Jhon", false), ("Ana", "Anna", false), ("Marc", "Marco", true)])
    func length(heard: String, corrected: String, expected: Bool) {
        #expect(Self.accepts(heard, corrected) == expected)
        #expect(!Self.accepts("Kael", "K" + String(repeating: "a", count: 40)))
    }

    @Test(
        "the corrected word is letters, digits, hyphens and apostrophes, and not only digits",
        arguments: [
            ("Odonel", "O'Donnell", true), ("Mary Ann", "Mary-Anne", true), ("GPT four", "GPT4o", true),
            ("one two three", "12345", false), ("Kael", "Kael@thorn", false), ("Kael", "Kael.thorn", false),
        ])
    func charset(heard: String, corrected: String, expected: Bool) {
        #expect(Self.accepts(heard, corrected) == expected)
    }

    @Test("a stopword is never a term")
    func stopword() {
        #expect(!Self.accepts("Their", "There", tagged: ["There"]))
        #expect(!Self.accepts("Beeing", "Being", tagged: ["Being"]))
    }

    @Test("a term already in the dictionary, or dismissed, is not suggested again, whatever the case")
    func known() {
        #expect(!Self.accepts("Kyle Thorn", "Kaelthorn", known: ["kaelthorn"]))
        #expect(Self.accepts("Kyle Thorn", "Kaelthorn", known: ["Kaelthorne"]))
    }

    @Test("a rewording is not a mishearing: the two sides must be close in spelling")
    func rewording() {
        #expect(!Self.accepts("reunion", "Calendario"))
        #expect(!Self.accepts("Bob", "Roberto"))
    }

    @Test("a lowercase common word is not a term unless the tagger calls it a name")
    func properNoun() {
        #expect(!Self.accepts("recieve", "receive"))
        #expect(Self.accepts("kaelthorm", "kaelthorn", tagged: ["kaelthorn"]))
    }

    @Test("the suggestions of a dictation are the accepted corrections, each term once")
    func suggestions() {
        let filter = SuggestionFilter(tagger: FakeEntityTagger())
        let corrections = [
            WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn"),
            WordCorrection(heard: "Jon", corrected: "Jhon"),
            WordCorrection(heard: "kyle thorn", corrected: "kaelThorn"),
        ]

        #expect(
            filter.suggestions(from: corrections, in: Self.text, known: [])
                == [WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn")])
    }
}
