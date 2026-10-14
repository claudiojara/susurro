import Testing

@testable import TextShaping

@Suite("Answer detector")
struct AnswerDetectorTests {
    // MARK: What counts as an answer

    @Test(
        "a lost request word and a new content word make an answer",
        arguments: [
            ("qué es la capital de francia", "La capital de Francia es París."),
            ("what is the capital of france", "Paris is the capital of France."),
            ("dime la capital de francia", "La capital de Francia es París."),
            ("cuántos años tiene la torre eiffel", "La torre Eiffel fue inaugurada en 1889."),
            ("explain how photosynthesis works", "Plants turn sunlight into sugar."),
        ])
    func detectsAnswers(raw: String, output: String) {
        #expect(AnswerDetector.isAnswer(raw: raw, output: output))
    }

    @Test(
        "a cleaned question is not an answer",
        arguments: [
            ("qué es la capital de francia", "¿Qué es la capital de Francia?"),
            ("what is the capital of france", "What is the capital of France?"),
            ("cuál es el mejor día para la reunión", "¿Cuál es el mejor día para la reunión?"),
            ("eh dime la capital de francia", "Dime la capital de Francia."),
        ])
    func acceptsCleanedQuestions(raw: String, output: String) {
        #expect(!AnswerDetector.isAnswer(raw: raw, output: output))
    }

    @Test("a request word that is still there keeps the output, whatever else it adds")
    func keptRequestWord() {
        #expect(
            !AnswerDetector.isAnswer(
                raw: "como te decía el informe va mañana", output: "Como te decía, el informe va mañana."))
        #expect(
            !AnswerDetector.isAnswer(
                raw: "what is the capital of france", output: "What is the capital of France? Paris."))
    }

    @Test("a transcript with no request word at its start is never an answer")
    func noRequestWord() {
        #expect(
            !AnswerDetector.isAnswer(
                raw: "hola equipo la reunión es mañana", output: "Hola, equipo: reservamos la sala grande."))
    }

    @Test("a dropped false start that keeps the question word is not an answer")
    func droppedFalseStart() {
        #expect(!AnswerDetector.isAnswer(raw: "eh que que el informe va mañana", output: "Que el informe va mañana."))
    }

    // MARK: Only the first three tokens

    @Test("only the first three words can be the request word")
    func firstThreeTokens() {
        let output = "La reunión ya terminó y París cerró."
        #expect(AnswerDetector.isAnswer(raw: "eh este dime reunión", output: output))
        // The word is the fourth: it is not looked for.
        #expect(!AnswerDetector.isAnswer(raw: "eh este mm dime reunión", output: output))
    }

    // MARK: Folding

    @Test("accents and case do not matter on either side")
    func folding() {
        // "QUÉ" in the transcript is gone, and "PARÍS" is new.
        #expect(AnswerDetector.isAnswer(raw: "QUÉ ES LA CAPITAL DE FRANCIA", output: "Es PARÍS."))
        // "parís" is in the transcript with its accent, and in the output without it.
        #expect(!AnswerDetector.isAnswer(raw: "dime la capital de parís", output: "La capital de Paris."))
    }

    // MARK: New words

    @Test("a word within one edit of a transcript word is a recognizer fix, not a new word")
    func editDistanceTolerance() {
        #expect(!AnswerDetector.isAnswer(raw: "dime hablé con maria gonzales", output: "Hablé con María González."))
        // Two edits is a different word.
        #expect(AnswerDetector.isAnswer(raw: "dime hablé con maria gonzalo", output: "Hablé con María Gonzaga."))
        // A transcript word under four letters does not excuse a near neighbor.
        #expect(AnswerDetector.isAnswer(raw: "dime la sal", output: "La sol."))
    }

    @Test("function words do not count as new words")
    func stopwords() {
        #expect(
            !AnswerDetector.isAnswer(
                raw: "dime la capital de francia", output: "Es la capital de Francia, y el de ella."))
        #expect(
            !AnswerDetector.isAnswer(
                raw: "what is the capital of france", output: "It is the capital of France, and this."))
    }

    @Test("a word that is short, or has digits, does not count")
    func shortAndNumeric() {
        #expect(!AnswerDetector.isAnswer(raw: "dime la capital", output: "La capital: sí, 135."))
        #expect(!AnswerDetector.isAnswer(raw: "dime la capital", output: "La capital xx."))
    }

    @Test("a term of the reference is not a new word")
    func referenceTerms() {
        let raw = "dime donde esta kael thorn"
        let output = "¿Dónde está Kaelthorn?"
        #expect(AnswerDetector.isAnswer(raw: raw, output: output))
        #expect(!AnswerDetector.isAnswer(raw: raw, output: output, reference: ["Kaelthorn"]))
        #expect(!AnswerDetector.isAnswer(raw: raw, output: output, reference: ["Reunión con Kaelthorn\nmañana"]))
    }

    @Test("an empty output or an empty transcript is never an answer")
    func empties() {
        #expect(!AnswerDetector.isAnswer(raw: "", output: "París"))
        #expect(!AnswerDetector.isAnswer(raw: "dime la capital", output: ""))
    }
}
