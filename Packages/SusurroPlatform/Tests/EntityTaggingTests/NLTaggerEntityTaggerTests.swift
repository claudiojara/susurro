import EntityTagging
import Testing

@Suite("NLTagger entity tagger")
struct NLTaggerEntityTaggerTests {
    private let tagger = NLTaggerEntityTagger()

    @Test("an English sentence gives its people, organizations, and places")
    func english() {
        let nouns = tagger.properNouns(in: "I work at Microsoft in Seattle with Satya Nadella.")
        #expect(nouns.contains("Microsoft"))
        #expect(nouns.contains("Seattle"))
        #expect(nouns.contains("Satya Nadella"))
    }

    @Test("an English sentence with a person and a company")
    func englishMeeting() {
        let nouns = tagger.properNouns(in: "Meeting with Maria Gonzalez about Acme tomorrow")
        #expect(nouns.contains("Maria Gonzalez"))
        #expect(nouns.contains("Acme"))
    }

    @Test("a Spanish sentence gives its people, organizations, and places")
    func spanish() {
        let nouns = tagger.properNouns(in: "Ayer hablé con Juan Pérez en Barcelona sobre Google.")
        #expect(nouns.contains("Juan Pérez"))
        #expect(nouns.contains("Barcelona"))
        #expect(nouns.contains("Google"))
    }

    @Test("empty and blank text give none")
    func empty() {
        #expect(tagger.properNouns(in: "").isEmpty)
        #expect(tagger.properNouns(in: "  \n ").isEmpty)
    }

    @Test("lowercase text gives none")
    func lowercase() {
        #expect(tagger.properNouns(in: "ayer maría gonzález visitó madrid con pedro sánchez").isEmpty)
        #expect(tagger.properNouns(in: "yesterday tim cook met sundar pichai in cupertino").isEmpty)
    }

    @Test("text with no names gives none")
    func noNames() {
        #expect(tagger.properNouns(in: "Please send the report today.").isEmpty)
    }
}
