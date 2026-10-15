import Domain
import Testing
import TextShaping

@Suite("Command output guard")
struct CommandOutputGuardTests {
    private static let selection =
        "hola equipo, mañana no voy a poder ir a la reunión porque tengo que ir al médico, lo siento"

    private func verdict(_ output: String, selection: String = selection, instruction: String = "hazlo más formal")
        -> CommandOutputGuard.Verdict
    {
        CommandOutputGuard.evaluate(selection: selection, instruction: instruction, output: output)
    }

    @Test(
        "a reply that is empty, talks to the user, or gives the selection back unchanged replaces nothing",
        arguments: [
            ("", CommandOutputGuard.Reason.emptyOutput),
            ("   \n", .emptyOutput),
            ("Lo siento, no puedo ayudar con eso.", .assistantMarker),
            ("Sorry, I cannot help with rewriting this.", .assistantMarker),
            ("As an AI, I cannot rewrite this.", .assistantMarker),
            (
                "hola equipo,  mañana no voy a poder ir a la reunión porque tengo que ir al médico, lo siento",
                .unchanged
            ),
        ])
    func rejected(output: String, reason: CommandOutputGuard.Reason) {
        #expect(verdict(output) == .rejected(reason))
    }

    @Test("an apology or a 'can't' that belongs to the rewritten text is kept: a rewrite may say them")
    func ordinaryWordsAreKept() {
        let formal = "Estimado equipo: lamento informarles que no podré asistir a la reunión de mañana."
        let bullets = "* mañana no puedo ir a la reunión\n* voy al médico"

        #expect(verdict(formal) == .accepted(formal))
        #expect(verdict(bullets, instruction: "resume en viñetas") == .accepted(bullets))
    }

    @Test(
        "a refusal or the model talking about the request is rejected",
        arguments: [
            "I'm sorry, but I can't help with that request.", "No puedo ayudar con esa solicitud.",
            "El usuario quiere que reescriba el texto de forma formal.", "As an AI language model, I rewrote it.",
        ])
    func refusals(output: String) {
        #expect(verdict(output) == .rejected(.assistantMarker))
    }

    @Test("a marker the selection itself contains does not count")
    func markerInSelection() {
        let output = "Estimado equipo: mañana no podré asistir a la reunión por una cita médica. Lo siento."

        #expect(verdict(output) == .accepted(output))
    }

    @Test("a translation and a summary are accepted, since a rewrite may change the language and the length")
    func translatedAndSummarized() {
        let translated =
            "Hi team, I won't be able to make it to the meeting tomorrow because I have a doctor's appointment."
        let summary = "No iré mañana: médico."

        #expect(verdict(translated, instruction: "tradúcelo al inglés") == .accepted(translated))
        #expect(verdict(summary, instruction: "resúmelo") == .accepted(summary))
    }

    @Test("a reply under 15 % of the selection, or over five times it, is out of proportion")
    func ratios() {
        let selection = String(repeating: "palabra ", count: 100)  // 800 characters
        let tooShort = String(repeating: "a", count: 119)
        let shortEnough = String(repeating: "a", count: 120)
        let tooLong = String(repeating: "b", count: 4_001)

        #expect(verdict(tooShort, selection: selection) == .rejected(.contraction))
        #expect(verdict(shortEnough, selection: selection) == .accepted(shortEnough))
        #expect(verdict(tooLong, selection: selection) == .rejected(.expansion))
    }

    @Test("a short selection may grow past five times, up to the floor the token limit allows")
    func shortSelectionGrows() {
        let expanded = "Hello there, and thank you very much for your message."

        #expect(verdict(expanded, selection: "hi", instruction: "make it longer") == .accepted(expanded))
    }

    @Test("the reply is sanitized first: a label and the request's tags are stripped")
    func sanitized() {
        #expect(
            verdict("Output: <SELECTION>Estimado equipo, mañana no podré asistir.</SELECTION>")
                == .accepted("Estimado equipo, mañana no podré asistir."))
    }
}
