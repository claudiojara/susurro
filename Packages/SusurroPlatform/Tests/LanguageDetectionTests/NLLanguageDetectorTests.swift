import Domain
import Testing

@testable import LanguageDetection

@Suite("NL language detector")
struct NLLanguageDetectorTests {
    private let detector = NLLanguageDetector()

    @Test("a Spanish sentence is Spanish, and so is one with a few English words in it")
    func spanish() {
        let plain = detector.hypotheses(for: "Hola, esto es una prueba de dictado en español para mañana.", maximum: 3)
        let mixed = detector.hypotheses(
            for: "Abre el pull request y haz el deploy después del commit, por favor.", maximum: 3)

        #expect(plain.first?.code == "es")
        #expect(mixed.first?.code == "es")
        #expect((mixed.first?.confidence ?? 0) > 0.6)
    }

    @Test("an English sentence is English, with little chance of Spanish")
    func english() {
        let guesses = detector.hypotheses(
            for: "Are you going to be able to finish the report before the meeting?", maximum: 3)

        #expect(guesses.first?.code == "en")
        #expect((guesses.first?.confidence ?? 0) > 0.6)
        #expect((guesses.first { $0.code == "es" }?.confidence ?? 0) < 0.3)
    }

    @Test("Cyrillic is Russian, whatever Spanish was spoken")
    func cyrillic() {
        #expect(detector.hypotheses(for: "Надежда пришла вовремя.", maximum: 1).first?.code == "ru")
    }

    @Test("the guesses come likeliest first and no more than asked for")
    func ordering() {
        let guesses = detector.hypotheses(for: "Ola, como estas? Hello there.", maximum: 2)

        #expect(guesses.count <= 2)
        #expect(guesses == guesses.sorted { $0.confidence > $1.confidence })
    }

    @Test("blank text and a limit of zero have no guesses")
    func nothing() {
        #expect(detector.hypotheses(for: "   ", maximum: 3).isEmpty)
        #expect(detector.hypotheses(for: "hola", maximum: 0).isEmpty)
    }
}
