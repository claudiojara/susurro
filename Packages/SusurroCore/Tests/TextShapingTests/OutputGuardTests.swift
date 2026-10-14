import Domain
import Testing

@testable import TextShaping

@Suite("Output guard")
struct OutputGuardTests {
    private static func letters(_ count: Int, _ letter: Character = "a") -> String {
        String(repeating: letter, count: count)
    }

    @Test("clean output is accepted and returned sanitized")
    func acceptsCleanOutput() {
        #expect(OutputGuard.evaluate(raw: "hola equipo", output: "Hola, equipo.") == .accepted("Hola, equipo."))
        #expect(
            OutputGuard.evaluate(raw: "hello team", output: "Here is the text: Hello, team.")
                == .accepted("Hello, team."))
    }

    @Test("empty output gives the raw transcript")
    func emptyOutput() {
        for output in ["", "   \n", "```\n```", "<think>only thoughts</think>"] {
            #expect(OutputGuard.evaluate(raw: "hola equipo", output: output) == .fallback(.emptyOutput))
        }
    }

    @Test(
        "assistant markers give the raw transcript",
        arguments: [
            "I'm sorry, but I can't help with that.",
            "I cannot assist with this request.",
            "As an AI language model, I do not have opinions.",
            "The user is asking about the capital of France.",
            "The user wants me to write a poem.",
            "Lo siento, no puedo ayudar con eso.",
            "Como modelo de lenguaje, no tengo opiniones.",
            "El usuario está preguntando por la capital de Francia.",
            "El usuario quiere que escriba un poema.",
            "I’m sorry, that is not something I can do.",
        ])
    func assistantMarkers(output: String) {
        #expect(OutputGuard.evaluate(raw: "dime una cosa", output: output) == .fallback(.assistantMarker))
    }

    @Test("a marker the speaker said is not a marker")
    func markerInTheRawTranscriptIsKept() {
        #expect(
            OutputGuard.evaluate(raw: "i cannot make it tomorrow", output: "I cannot make it tomorrow.")
                == .accepted("I cannot make it tomorrow."))
        #expect(
            OutputGuard.evaluate(raw: "lo siento mucho llego tarde", output: "Lo siento mucho, llego tarde.")
                == .accepted("Lo siento mucho, llego tarde."))
    }

    /// (raw length, output length, expected). Each limit is accepted exactly at the ratio and refused one character past.
    @Test(
        "length ratio limits",
        arguments: [
            // raw under 50: above 4.0
            (10, 40, nil), (10, 41, FallbackReason.expansion), (49, 196, nil), (49, 197, FallbackReason.expansion),
            // raw under 150: above 2.5
            (50, 125, nil), (50, 126, FallbackReason.expansion), (149, 372, nil), (149, 373, FallbackReason.expansion),
            // otherwise: above 2.0
            (150, 300, nil), (150, 301, FallbackReason.expansion), (400, 800, nil),
            (400, 801, FallbackReason.expansion),
            // raw of 20 or more: below 0.4
            (20, 8, nil), (20, 7, FallbackReason.contraction), (100, 40, nil), (100, 39, FallbackReason.contraction),
            // raw under 20 has no lower limit
            (19, 1, nil), (10, 1, nil),
        ] as [(Int, Int, FallbackReason?)])
    func ratioLimits(rawLength: Int, outputLength: Int, expected: FallbackReason?) {
        let raw = Self.letters(rawLength, "a")
        let output = Self.letters(outputLength, "b")
        let verdict = OutputGuard.evaluate(raw: raw, output: output)
        if let expected {
            #expect(verdict == .fallback(expected))
        } else {
            #expect(verdict == .accepted(output))
        }
    }

    @Test("a model that writes on past the text is refused as an expansion")
    func modelWritesOn() {
        let continuation = String(
            repeating: "El informe de ventas incluye todas las regiones del país, ", count: 9
        ).prefix(400)
        #expect(continuation.count == 400)
        #expect(
            OutputGuard.evaluate(raw: "el informe de ventas", output: String(continuation))
                == .fallback(.expansion))
    }

    // MARK: Answers

    @Test("a long answer to a dictated question is refused as an answer, before its length is looked at")
    func longAnswerIsAnswered() {
        let answer = String(repeating: "Paris is the capital and largest city of France, ", count: 9).prefix(400)
        #expect(answer.count == 400)
        #expect(
            OutputGuard.evaluate(raw: "what is the capital of france", output: String(answer))
                == .fallback(.answered))
    }

    @Test(
        "an answer to the dictated question gives the raw transcript",
        arguments: [
            ("qué es la capital de francia", "La capital de Francia es París."),
            ("what is the capital of france", "Paris is the capital of France."),
            ("dime la capital de francia", "La capital de Francia es París."),
        ])
    func answerIsRefused(raw: String, output: String) {
        #expect(OutputGuard.evaluate(raw: raw, output: output) == .fallback(.answered))
    }

    @Test(
        "a cleaned question, a kept request word, and a known term are accepted",
        arguments: [
            ("qué es la capital de francia", "¿Qué es la capital de Francia?", [String]()),
            ("what is the capital of france", "What is the capital of France?", [String]()),
            ("como te decía el informe va mañana", "Como te decía, el informe va mañana.", [String]()),
            ("eh que que el informe va mañana", "Que el informe va mañana.", [String]()),
            ("hablé con maría gonzales", "Hablé con María González.", ["María González"]),
            ("dime donde esta kael thorn", "¿Dónde está Kaelthorn?", ["Kaelthorn"]),
        ])
    func cleanedQuestionIsAccepted(raw: String, output: String, reference: [String]) {
        #expect(OutputGuard.evaluate(raw: raw, output: output, reference: reference) == .accepted(output))
    }

    @Test("the same new word is an answer when the reference does not have it")
    func referenceDecides() {
        #expect(
            OutputGuard.evaluate(raw: "dime donde esta kael thorn", output: "¿Dónde está Kaelthorn?")
                == .fallback(.answered))
    }
}
