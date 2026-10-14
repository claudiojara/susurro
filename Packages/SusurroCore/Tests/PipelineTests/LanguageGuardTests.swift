import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Language guard", .timeLimit(.minutes(1)))
struct LanguageGuardTests {
    private static func guess(_ code: String, _ confidence: Double) -> LanguageGuess {
        LanguageGuess(code: code, confidence: confidence)
    }

    private static func guardian(_ answers: [String: [LanguageGuess]] = [:]) -> LanguageGuard {
        LanguageGuard(detector: FakeLanguageDetector(answers))
    }

    @Test("a transcript the detector is clearly sure is English has drifted")
    func english() {
        let sut = Self.guardian(["We big.": [Self.guess("en", 0.9), Self.guess("es", 0.02)]])

        #expect(sut.hasDrifted("We big."))
    }

    @Test("a Spanish sentence with a few English words is left alone")
    func spanishWithEnglishWords() {
        let text = "Abre el pull request y haz el deploy después del commit."
        let sut = Self.guardian([text: [Self.guess("es", 0.93), Self.guess("en", 0.05)]])

        #expect(!sut.hasDrifted(text))
    }

    @Test("a detector that is unsure, or that cannot tell, does not make a transcript drift")
    func unsure() {
        let unsure = Self.guardian(["Ole": [Self.guess("pt", 0.4), Self.guess("es", 0.3)]])

        #expect(!unsure.hasDrifted("Ole"))
        #expect(!Self.guardian().hasDrifted("Ole"))
        #expect(!Self.guardian().hasDrifted(""))
    }

    @Test("English that still gives Spanish a real chance is not drift")
    func englishWithSpanishChance() {
        let sut = Self.guardian(["ok": [Self.guess("en", 0.7), Self.guess("es", 0.35)]])

        #expect(!sut.hasDrifted("ok"))
    }

    @Test("a transcript in another script has drifted, whatever the detector says")
    func foreignScript() {
        let sut = Self.guardian()

        #expect(sut.hasDrifted("Надежда."))
        #expect(sut.hasDrifted("привет amigo"))
        #expect(sut.hasDrifted("你好"))
        #expect(!sut.hasDrifted("¿Cómo estás? Ñandú, ¡vamos!"))
    }

    @Test("the engine's unknown-token marker means drift, and it is taken out of the text")
    func unknownToken() {
        let sut = Self.guardian()

        #expect(sut.hasDrifted("<unk>Ghazda.<unk>"))
        #expect(LanguageGuard.removingUnknownTokens(from: "<unk>Ghazda.<unk>") == "Ghazda.")
        #expect(LanguageGuard.removingUnknownTokens(from: "hola <unk> mundo") == "hola mundo")
        #expect(LanguageGuard.removingUnknownTokens(from: "hola mundo") == "hola mundo")
        #expect(LanguageGuard.removingUnknownTokens(from: "<unk>") == "")
    }

    @Test("digits and punctuation have no language")
    func noLetters() {
        #expect(!Self.guardian().hasDrifted("10:30 - 12,5 %"))
    }
}
