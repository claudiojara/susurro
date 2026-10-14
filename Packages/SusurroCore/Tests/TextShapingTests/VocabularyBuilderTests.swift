import CoreTestSupport
import Domain
import Testing

@testable import TextShaping

@Suite("Vocabulary builder")
struct VocabularyBuilderTests {
    private static func sources(
        dictionary: [String] = [], before: String = "", after: String = "", selection: String = "",
        screenText: [String] = [], isSecure: Bool = false
    ) -> VocabularySources {
        VocabularySources(
            dictionary: dictionary, beforeCursor: before, afterCursor: after, selection: selection,
            screenText: screenText, isSecureField: isSecure)
    }

    @Test("names in the text before the cursor are extracted")
    func extraction() {
        let text = "Meeting with Maria Gonzalez about Acme tomorrow"
        let builder = VocabularyBuilder(tagger: FakeEntityTagger([text: ["Maria Gonzalez", "Acme"]]))
        let terms = builder.build(Self.sources(before: text))
        #expect(terms.contains("Maria Gonzalez"))
        #expect(terms.contains("Acme"))
    }

    @Test("three dictionary terms and a hundred context terms give fifty terms with the dictionary in")
    func boundAndPriority() {
        let context = (0..<100).map { "Context\($0)" }
        let builder = VocabularyBuilder(tagger: FakeEntityTagger(["before": context]))
        let terms = builder.build(Self.sources(dictionary: ["Zed", "Yara", "Xavi"], before: "before"))
        #expect(terms.count == 50)
        #expect(Array(terms.prefix(3)) == ["Zed", "Yara", "Xavi"])
        #expect(terms[3] == "Context0")
    }

    @Test("the order is the dictionary, then field and selection nouns, then screen nouns")
    func priorityOrder() {
        let tagger = FakeEntityTagger([
            "before": ["B1"], "after": ["A1"], "selection": ["S1"], "screen": ["O1", "O2"],
        ])
        let builder = VocabularyBuilder(tagger: tagger, maxTerms: 4)
        let terms = builder.build(
            Self.sources(
                dictionary: ["D1"], before: "before", after: "after", selection: "selection", screenText: ["screen"]))
        #expect(terms == ["D1", "B1", "A1", "S1"])
    }

    @Test("screen nouns come last and are the first to go")
    func screenNounsAreDroppedFirst() {
        let tagger = FakeEntityTagger(["before": ["B1", "B2"], "screen": ["O1"]])
        let builder = VocabularyBuilder(tagger: tagger, maxTerms: 2)
        #expect(builder.build(Self.sources(before: "before", screenText: ["screen"])) == ["B1", "B2"])
    }

    @Test("terms are deduplicated without regard to case, and the higher priority spelling wins")
    func caseInsensitiveDedupe() {
        let tagger = FakeEntityTagger(["before": ["ACME", "maria", "Maria", "Beta"], "screen": ["beta", "Gamma"]])
        let builder = VocabularyBuilder(tagger: tagger)
        let terms = builder.build(Self.sources(dictionary: ["Acme", "acme"], before: "before", screenText: ["screen"]))
        #expect(terms == ["Acme", "maria", "Beta", "Gamma"])
    }

    @Test("a term of more than 40 characters is dropped, and one of exactly 40 is kept")
    func termLength() {
        let forty = String(repeating: "a", count: 40)
        let long = String(repeating: "b", count: 41)
        let builder = VocabularyBuilder(tagger: FakeEntityTagger(["before": [long, forty]]))
        #expect(builder.build(Self.sources(dictionary: [long], before: "before")) == [forty])
    }

    @Test("empty and blank terms are dropped, and terms are trimmed")
    func blanksAreDropped() {
        let builder = VocabularyBuilder(tagger: FakeEntityTagger(["before": ["  Acme  ", "", "   "]]))
        #expect(builder.build(Self.sources(dictionary: ["", " Zed "], before: "before")) == ["Zed", "Acme"])
    }

    @Test("a secure field gives no context terms and the tagger never sees its text")
    func secureField() {
        let tagger = FakeEntityTagger(["before": ["Secret"], "screen": ["Secret2"]])
        let builder = VocabularyBuilder(tagger: tagger)
        let terms = builder.build(
            Self.sources(
                dictionary: ["Zed"], before: "before", after: "after", selection: "selection",
                screenText: ["screen"], isSecure: true))
        #expect(terms == ["Zed"])
        #expect(tagger.taggedTexts.isEmpty)
    }

    @Test("a dictionary of more than fifty terms keeps the first fifty")
    func hugeDictionary() {
        let dictionary = (0..<80).map { "Term\($0)" }
        let terms = VocabularyBuilder(tagger: FakeEntityTagger()).build(Self.sources(dictionary: dictionary))
        #expect(terms == Array(dictionary.prefix(50)))
    }

    @Test("empty texts are not tagged")
    func emptyTextsAreSkipped() {
        let tagger = FakeEntityTagger()
        _ = VocabularyBuilder(tagger: tagger).build(Self.sources(before: "", after: "  ", screenText: ["", "line"]))
        #expect(tagger.taggedTexts == ["line"])
    }
}
