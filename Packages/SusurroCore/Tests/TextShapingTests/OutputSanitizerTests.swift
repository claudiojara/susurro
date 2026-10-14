import Testing

@testable import TextShaping

@Suite("Output sanitizer")
struct OutputSanitizerTests {
    @Test("a preamble and a code fence around the text are removed")
    func wrappedOutput() {
        #expect(OutputSanitizer.sanitize("Here is the text: ```Hola, equipo.```") == "Hola, equipo.")
    }

    @Test(
        "table",
        arguments: [
            // think blocks, closed, multiline, orphan close
            ("<think>planning the answer</think>Hola, equipo.", "Hola, equipo."),
            ("<think>\nline one\nline two\n</think>\n\nHola.", "Hola."),
            ("reasoning without an opening tag</think> Hola.", "Hola."),
            ("<think>never closed", ""),
            // code fences
            ("```\nHola, equipo.\n```", "Hola, equipo."),
            ("```text\nHola, equipo.\n```", "Hola, equipo."),
            ("```Hola```", "Hola"),
            // labels
            ("Output: Hola, equipo.", "Hola, equipo."),
            ("Cleaned text: Hola, equipo.", "Hola, equipo."),
            ("Resultado: Hola, equipo.", "Hola, equipo."),
            ("Texto corregido:\nHola, equipo.", "Hola, equipo."),
            // English preambles
            ("Here is the cleaned text:\n\nHello, team.", "Hello, team."),
            ("Here's the corrected version: Hello, team.", "Hello, team."),
            ("Sure, here is the text: Hello, team.", "Hello, team."),
            ("Sure! Here is the cleaned transcript:\nOutput: Hello, team.", "Hello, team."),
            // Spanish preambles
            ("Aqui esta el texto: Hola, equipo.", "Hola, equipo."),
            ("Aquí está el texto limpio:\nHola, equipo.", "Hola, equipo."),
            ("Claro, aquí tienes el texto: Hola, equipo.", "Hola, equipo."),
            // text that needs nothing
            ("Hola, equipo.", "Hola, equipo."),
            ("  Hola, equipo.  \n", "Hola, equipo."),
            ("Here we go again, team.", "Here we go again, team."),
            ("I wrote the output: it worked.", "I wrote the output: it worked."),
        ])
    func table(output: String, expected: String) {
        #expect(OutputSanitizer.sanitize(output) == expected)
    }

    @Test("a preamble that the speaker really said is kept")
    func rawStartingWithTheSamePreambleKeepsIt() {
        let raw = "here is the plan we ship it on friday"
        #expect(
            OutputSanitizer.sanitize("Here is the plan: we ship it on Friday.", raw: raw)
                == "Here is the plan: we ship it on Friday.")
        #expect(
            OutputSanitizer.sanitize("Here is the text: Ship it.", raw: "ship it")
                == "Ship it.")
    }
}
