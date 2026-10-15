/// Phrases that mean a model is talking to the user instead of cleaning the text: refusals, apologies, and the model
/// describing the request. They are data, one list for each language, compared in folded form (lowercase, no accents).
/// A marker counts only when the transcript does not contain it, because a speaker can say "I can't make it" too.
enum AssistantMarkers {
    static let english = [
        "i'm sorry", "i am sorry", "i apologize", "i cannot", "i can't", "i'm unable", "i am unable", "i'm not able",
        "i am not able", "i do not have the ability", "i don't have the ability", "as an ai", "as a language model",
        "as an assistant", "the user is asking", "the user asked", "the user asks", "the user wants",
        "the user is requesting", "the user said", "i'd be happy to", "i hope this helps", "how can i help",
    ]

    static let spanish = [
        "lo siento", "lamento", "no puedo", "no me es posible", "no tengo la capacidad", "no tengo acceso",
        "como modelo de lenguaje", "como una ia", "como ia", "como asistente", "el usuario esta preguntando",
        "el usuario pregunta", "el usuario pide", "el usuario quiere", "el usuario solicita", "el usuario dice",
        "con gusto te ayudo", "espero que esto ayude", "en que puedo ayudar",
    ]

    /// Every marker, folded.
    static let all: [String] = (english + spanish).map(TextCharacters.folded)

    /// The markers of a rewrite (command mode), which is a request by design: a model refusing it, or describing it.
    /// Apologies and a plain "can't" are left out, since a rewritten text may well say them ("lamento informarles", "no
    /// puedo ir"), and measured on the real model a formal rewrite and a summary did.
    static let command: [String] = [
        "i can't help", "i cannot help", "i can't assist", "i cannot assist", "i'm unable to help",
        "i am unable to help", "i can't fulfill", "i cannot fulfill", "i can't do that", "i cannot do that",
        "as an ai", "as a language model", "as an assistant", "the user is asking", "the user asked", "the user asks",
        "the user wants", "the user is requesting", "no puedo ayudar", "no puedo cumplir", "no puedo hacer eso",
        "no me es posible ayudar", "como modelo de lenguaje", "como una ia", "como asistente",
        "el usuario esta preguntando", "el usuario pregunta", "el usuario pide", "el usuario quiere",
        "el usuario solicita",
    ].map(TextCharacters.folded)

    /// The first marker `output` contains and `raw` does not, or nil.
    static func firstMarker(in output: String, notIn raw: String, markers: [String] = all) -> String? {
        let foldedOutput = TextCharacters.folded(output)
        let foldedRaw = TextCharacters.folded(raw)
        return markers.first { foldedOutput.contains($0) && !foldedRaw.contains($0) }
    }
}
