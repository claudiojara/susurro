import Testing

@testable import TextShaping

@Suite("Filler remover")
struct FillerRemoverTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: String
        var testDescription: String { input }

        init(_ input: String, _ expected: String) {
            self.input = input
            self.expected = expected
        }
    }

    static let removals: [Case] = [
        // Spanish hesitations.
        Case("Eh, quería decirte que mañana no puedo.", "Quería decirte que mañana no puedo."),
        Case("Quería, eh, decirte que llego tarde.", "Quería, decirte que llego tarde."),
        Case("Quería eh decirte que llego tarde.", "Quería decirte que llego tarde."),
        Case("Compré pan, eh, leche y huevos.", "Compré pan, leche y huevos."),
        Case("Te lo mando mañana, eh.", "Te lo mando mañana."),
        Case("Te lo mando mañana, eh", "Te lo mando mañana"),
        Case("Pues ehh no sé si puedo.", "Pues no sé si puedo."),
        Case("Em, ¿puedes revisar el informe?", "¿Puedes revisar el informe?"),
        Case("Necesito, emm, el informe del martes.", "Necesito, el informe del martes."),
        Case("Mmm, déjame pensarlo.", "Déjame pensarlo."),
        Case("Y eh... quería preguntarte algo.", "Y quería preguntarte algo."),
        Case("Este... quería pedirte un favor.", "Quería pedirte un favor."),
        Case("Hola. Eh, quería saber si vienes.", "Hola. Quería saber si vienes."),
        Case("Eh. Quería saber si vienes.", "Quería saber si vienes."),
        Case("Quería eh, eh, decirte algo.", "Quería decirte algo."),
        // English hesitations.
        Case("Erm, can you send me the report?", "Can you send me the report?"),
        Case("I think, hmm, we should wait.", "I think, we should wait."),
        Case("So umm we need to talk.", "So we need to talk."),
        Case("The deadline is uhh Friday.", "The deadline is Friday."),
        Case("Uhm, let me check.", "Let me check."),
        // Self-corrections.
        Case("Nos vemos a las 2, no, a las 3.", "Nos vemos a las 3."),
        Case("Quedamos a las 2, no, a las 3 en la oficina.", "Quedamos a las 3 en la oficina."),
        Case("Let's meet at 2, no, at 3.", "Let's meet at 3."),
        Case("Es verdad, no, es mentira.", "Es mentira."),
        Case("Envíalo el martes por la tarde, no, el miércoles por la mañana.", "Envíalo el miércoles por la mañana."),
        Case("Envíalo el martes, digo, el miércoles.", "Envíalo el miércoles."),
        Case("Llámame el lunes, mejor dicho, el martes.", "Llámame el martes."),
        Case("Llego a las 2, eh, no, a las 3.", "Llego a las 3."),
        Case("The meeting is at 10, no, at 11.", "The meeting is at 11."),
    ]

    @Test("a filler or a self-correction is removed", arguments: removals)
    func removes(_ testCase: Case) {
        #expect(FillerRemover.clean(testCase.input) == testCase.expected)
    }

    static let untouched: [String] = [
        // Words that look like fillers and are not.
        "Este coche es el mío.",
        "Este es el informe que pediste.",
        "Me gusta este...",
        "Vale, ¿eh?",
        "Está bien, ¿eh? Nos vemos.",
        "Bring 'em here.",
        "Um, I think so.",
        "Uh, okay.",
        "It was, like, huge.",
        "I like this one.",
        "O sea, no lo sé.",
        "Bueno, pues nada.",
        "Them and us.",
        "The ehm-test is fine.",
        "Ehrlich ist er nicht.",
        "Emma vino ayer.",
        "Hemos terminado.",
        "Eh.",
        "Mmm.",
        // Commas around "no" that are not corrections.
        "Sí, no, no sé.",
        "No, no, no.",
        "Está bien, no, en serio.",
        "Llámame mañana, no, el lunes.",
        "Juan, no, Pedro.",
        "Is it ready, no?",
        "I said no, no way.",
        "Fine, no problem.",
        "We need milk, eggs, no sugar.",
        "No lo sé, no, no lo sé.",
        // Apologies and asides are not markers, and a clause that starts with a pronoun is not a correction.
        "I can't come, sorry, I have a meeting.",
        "I was wrong, I mean, I admit it.",
        "I went to the park, I mean, to the beach.",
        "The meeting is at 10, sorry, at 11.",
        "I can't come, no, I have a meeting.",
        "We tried hard, no, we really did.",
        "It works fine, no, it really does.",
        "They called me, no, they wrote to me.",
        "No puedo ir, perdón, tengo una reunión.",
        "Envíalo el martes, perdón, el miércoles.",
        "Yo no fui, no, yo estaba en casa.",
        "Ella no viene, digo, ella está enferma.",
        "Nosotros lo sabíamos, no, nosotros lo dijimos.",
        // Uppercase acronyms are not hesitations.
        "The ERM framework is ready.",
        "HM Treasury published it.",
        "EM radiation is invisible.",
        "We use the EHM model.",
        "",
        "   ",
        "Línea uno\nlínea dos",
    ]

    @Test("a text without fillers is left exactly as it is", arguments: untouched)
    func leavesAlone(_ text: String) {
        #expect(FillerRemover.clean(text) == text)
    }
}
