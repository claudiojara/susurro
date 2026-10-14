import Domain
import Testing

@testable import TextShaping

@Suite("Insertion shaper")
struct InsertionShaperTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let before: String?
        let after: String
        let text: String
        let vocabulary: [String]
        let expected: String

        var testDescription: String { name }

        init(
            _ name: String, before: String?, after: String = "", text: String, vocabulary: [String] = [],
            expected: String
        ) {
            self.name = name
            self.before = before
            self.after = after
            self.text = text
            self.vocabulary = vocabulary
            self.expected = expected
        }
    }

    static let scenarios: [Case] = [
        // The spec scenarios.
        Case("mid-sentence", before: "Please send me", text: "The report today.", expected: " the report today."),
        Case("sentence start", before: "Done. ", text: "next steps", expected: "Next steps"),
        Case("proper noun kept", before: "Ask", text: "Maria", vocabulary: ["Maria"], expected: " Maria"),
        Case("unknown context", before: nil, text: "The report today.", expected: "The report today."),
        // Leading space.
        Case("empty field", before: "", text: "hello there", expected: "Hello there"),
        Case("before ends in a space", before: "Hi ", text: "there", expected: "there"),
        Case("before ends in a tab", before: "Hi\t", text: "there", expected: "there"),
        Case("text starts with a comma", before: "Hello", text: ", world", expected: ", world"),
        Case("text starts with a period", before: "Hello", text: ".", expected: "."),
        Case(
            "text starts with a closing parenthesis", before: "(see below", text: ") and more", expected: ") and more"),
        // Capitalization.
        Case("after a line break", before: "Title\n", text: "next", expected: "Next"),
        Case("after an indented line break", before: "Title\n   ", text: "next", expected: "Next"),
        Case("after a period with no space", before: "Done.", text: "next", expected: " Next"),
        Case("after an exclamation mark and spaces", before: "Done!  ", text: "next", expected: "Next"),
        Case("after a question mark", before: "Why?", text: "because", expected: " Because"),
        Case("after an ellipsis", before: "Well…", text: "okay", expected: " Okay"),
        Case("after a comma", before: "Yes,", text: "Of course", expected: " of course"),
        Case("pronoun I kept", before: "Then", text: "I think so", expected: " I think so"),
        Case("contraction with I kept", before: "Then", text: "I'm sure", expected: " I'm sure"),
        Case("curly apostrophe contraction kept", before: "Then", text: "I’ll go", expected: " I’ll go"),
        Case("acronym kept", before: "Call", text: "NASA now", expected: " NASA now"),
        Case("mixed case word kept", before: "Use", text: "McDonald today", expected: " McDonald today"),
        Case(
            "vocabulary term kept", before: "Ask", text: "Acme Corp about it", vocabulary: ["Acme"],
            expected: " Acme Corp about it"),
        Case(
            "multi-word vocabulary term kept", before: "Ask", text: "Maria about it", vocabulary: ["Maria Gonzalez"],
            expected: " Maria about it"),
        Case("vocabulary match ignores case", before: "Ask", text: "ACME", vocabulary: ["acme"], expected: " ACME"),
        Case("a lowercase start mid-sentence stays", before: "Ask", text: "maria", expected: " maria"),
        Case("empty field capitalizes", before: "", text: "maria", expected: "Maria"),
        Case("single capital letter word", before: "Is this", text: "A test", expected: " a test"),
        // Trailing period and space.
        Case(
            "trailing period dropped before a period", before: "Send", after: ".", text: "the file.",
            expected: " the file"),
        Case(
            "trailing period dropped before a comma", before: "Send", after: ", then", text: "the file.",
            expected: " the file"),
        Case(
            "trailing period dropped before a question mark", before: "Is", after: "?", text: "it done.",
            expected: " it done"),
        Case(
            "an ellipsis is not a trailing period", before: "Wait", after: ".", text: "for it...",
            expected: " for it..."),
        Case("a question mark is kept", before: "Send", after: ".", text: "the file?", expected: " the file?"),
        Case(
            "trailing period kept before a word", before: "Send", after: "tomorrow", text: "the file.",
            expected: " the file. "),
        Case(
            "trailing space before a word", before: "Send", after: "tomorrow", text: "the file", expected: " the file "),
        Case(
            "no trailing space before a space", before: "Send", after: " tomorrow", text: "the file",
            expected: " the file"),
        Case(
            "no trailing space at the end of the field", before: "Send", after: "", text: "the file",
            expected: " the file"),
        Case(
            "no trailing space before a line break", before: "Send", after: "\nmore", text: "the file",
            expected: " the file"),
        Case(
            "a digit after the cursor counts as a word", before: "Page", after: "2", text: "number",
            expected: " number "),
        // Whitespace around the text.
        Case("model whitespace is trimmed", before: "Please", text: "  The report.\n", expected: " the report."),
        Case("empty text stays empty", before: "Please", text: "", expected: ""),
        Case("whitespace-only text is left alone", before: "Please", text: "  ", expected: "  "),
        // Spanish.
        Case(
            "opening question mark after a word", before: "Dije que", text: "¿Qué hora es?", expected: " ¿qué hora es?"),
        Case("opening exclamation mark after a word", before: "Gritó", text: "¡Hola!", expected: " ¡hola!"),
        Case("opening parenthesis after a word", before: "Ver", text: "(nota)", expected: " (nota)"),
        Case("opening quote after a word", before: "Dijo", text: "“hola”", expected: " “hola”"),
        Case("opening question mark in an empty field", before: "", text: "¿qué hora es?", expected: "¿Qué hora es?"),
        Case("opening question mark after a sentence", before: "Listo. ", text: "¿y ahora?", expected: "¿Y ahora?"),
        Case(
            "accented capital kept as a proper word", before: "Hola", text: "Álvaro llegó", vocabulary: ["Álvaro"],
            expected: " Álvaro llegó"),
        Case("accented capital lowercased", before: "Hola", text: "Árbol grande", expected: " árbol grande"),
    ]

    @Test("scenarios", arguments: scenarios)
    func scenario(_ scenario: Case) {
        let cursor = scenario.before.map { CursorContext(before: $0, after: scenario.after) }
        #expect(
            InsertionShaper.shape(scenario.text, around: cursor, vocabulary: scenario.vocabulary)
                == scenario.expected)
    }

    @Test("a context whose before and after are both empty is a known empty field")
    func emptyFieldIsKnown() {
        let cursor = CursorContext(before: "", after: "")
        #expect(InsertionShaper.shape("hola", around: cursor, vocabulary: []) == "Hola")
    }
}
