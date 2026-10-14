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
            // the model repeats the tags of the request
            ("<TRANSCRIPT>what is the capital of france</TRANSCRIPT>", "what is the capital of france"),
            (
                "<STYLE category=\"email\" tone=\"formal\"/>\n<VOCABULARY>\nAcme\n</VOCABULARY>\n<TRANSCRIPT>Hello, team.</TRANSCRIPT>",
                "Hello, team."
            ),
            ("<CONTEXT><BEFORE_CURSOR>Dear team,</BEFORE_CURSOR></CONTEXT>\nHello.", "Hello."),
            ("Hello <TRANSCRIPT>there", "Hello there"),
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

    @Test("lines the model copied from the reference are dropped from the start of the reply")
    func copiedReferenceLines() {
        let reference = ["Acme", "Asunto: reunión\nDe: Ana"]
        #expect(OutputSanitizer.sanitize("Asunto: reunión\nHola equipo.", reference: reference) == "Hola equipo.")
        #expect(OutputSanitizer.sanitize("Acme\n\nHola equipo.", reference: reference) == "Hola equipo.")
        #expect(
            OutputSanitizer.sanitize("asunto: REUNION\nDe: Ana\nHola equipo.", reference: reference) == "Hola equipo.")
        // A line in the middle, or the whole reply, is the speaker's.
        #expect(OutputSanitizer.sanitize("Hola Acme\nAcme", reference: reference) == "Hola Acme\nAcme")
        #expect(OutputSanitizer.sanitize("Acme", reference: reference) == "Acme")
        #expect(OutputSanitizer.sanitize("Hola equipo.", reference: []) == "Hola equipo.")
    }
}
