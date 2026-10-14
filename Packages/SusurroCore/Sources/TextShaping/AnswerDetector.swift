/// Tells a model that answered the dictated question from one that cleaned it. A short answer is as long as the question
/// and says no assistant words ("La capital de Francia es París." for "qué es la capital de francia"), so neither the
/// markers nor the length ratio catch it. What gives it away is what changed in the content: the word that made the
/// transcript a question or a request is gone, and a word the speaker never said is there.
///
/// Both must hold. A request word that is lost alone is a dropped false start or a rephrasing, and a new word alone is a
/// name the recognizer got wrong, so each is safe by itself. Everything is compared folded (lowercase, no accents).
enum AnswerDetector {
    /// Question and request words, folded. Only the first `leadingWords` words of the transcript can be one: a request
    /// is stated at its start, and a "que" or "como" deep in a sentence is a conjunction.
    private static let requestWords: Set<String> = [
        // Spanish
        "que", "cual", "cuales", "quien", "quienes", "como", "cuando", "donde", "adonde", "cuanto", "cuanta", "cuantos",
        "cuantas", "dime", "dame", "explica", "explicame", "cuentame", "escribe", "escribeme", "redacta", "resume",
        "traduce", "lista", "enumera", "describe", "define", "calcula", "recomienda", "sugiere",
        // English ("describe" and "define" are the Spanish words too)
        "what", "which", "who", "whom", "whose", "how", "when", "where", "why", "tell", "give", "explain", "write",
        "list", "summarize", "translate", "calculate", "recommend", "suggest",
    ]

    /// Words a cleaner may add or change without answering anything: articles, pronouns, prepositions, conjunctions, and
    /// the common forms of the verbs that join a sentence. Only words of three letters or more matter here, since
    /// shorter ones are never looked at.
    private static let stopwords: Set<String> = [
        // Spanish
        "los", "las", "una", "uno", "unos", "unas", "del", "por", "para", "con", "sin", "sobre", "entre", "hacia",
        "desde", "hasta", "como", "pero", "sino", "aunque", "porque", "que", "cual", "cuales", "quien", "quienes",
        "cuando", "donde", "este", "esta", "esto", "estos", "estas", "ese", "esa", "eso", "esos", "esas", "aquel",
        "aquella", "aquello", "mis", "tus", "sus", "nuestro", "nuestra", "nuestros", "nuestras", "mio", "mia", "tuyo",
        "suyo", "ella", "ellos", "ellas", "nosotros", "nosotras", "usted", "ustedes", "les", "nos", "muy", "mas",
        "menos", "tambien", "tampoco", "ademas", "entonces", "pues", "solo", "ser", "soy", "eres", "son", "somos",
        "era", "eran", "fue", "fueron", "sera", "seran", "sido", "siendo", "estar", "estoy", "estan",
        "estamos", "estaba", "estaban", "estuvo", "haber", "han", "hay", "hemos", "habia", "hubo", "tener",
        "tengo", "tiene", "tienen", "tenemos", "tenia", "ahora", "aqui", "alli", "ahi", "ya", "todo", "toda", "todos",
        "todas", "otro", "otra", "otros", "otras", "mismo", "misma", "cada", "algo", "alguien", "nada", "nadie",
        // English
        "the", "and", "but", "for", "nor", "yet", "with", "without", "from", "into", "onto", "over", "under", "about",
        "after", "before", "between", "through", "during", "this", "that", "these", "those", "his", "her", "hers",
        "its", "our", "ours", "their", "theirs", "your", "yours", "him", "them", "she", "they", "you", "are", "was",
        "were", "been", "being", "has", "have", "had", "having", "does", "did", "done", "doing", "will", "would",
        "shall", "should", "can", "could", "may", "might", "must", "not", "all", "any", "some", "each", "every",
        "other", "another", "such", "than", "then", "there", "here", "also", "too", "very", "just", "only", "own",
        "same", "who", "whom", "whose", "which", "what", "how", "when", "where", "why",
    ]

    /// How many words at the start of the transcript can be the request word.
    private static let leadingWords = 3
    /// The shortest word that counts as new content.
    private static let shortestContentWord = 3
    /// A transcript word at least this long excuses a word one edit away from it, as a recognizer fix.
    private static let shortestFixableWord = 4

    /// Whether `output` answers `raw`.
    ///
    /// - Parameter reference: The vocabulary terms and the lines before the cursor the model was given. A word from them
    ///   is not new.
    static func isAnswer(raw: String, output: String, reference: [String] = []) -> Bool {
        let rawWords = words(of: raw)
        let outputWords = words(of: output)
        guard lostRequestWord(rawWords: rawWords, outputWords: outputWords) else { return false }
        let known = Set(rawWords).union(reference.flatMap(words(of:)))
        let fixable = rawWords.filter { $0.count >= shortestFixableWord }
        return outputWords.contains { isNewContentWord($0, known: known, fixable: fixable) }
    }

    /// The words of a text, folded: runs of letters and digits.
    private static func words(of text: String) -> [String] {
        TextCharacters.folded(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Whether one of the first words of the transcript is a request word that the output does not have.
    private static func lostRequestWord(rawWords: [String], outputWords: [String]) -> Bool {
        let kept = Set(outputWords)
        return rawWords.prefix(leadingWords).contains { requestWords.contains($0) && !kept.contains($0) }
    }

    private static func isNewContentWord(_ word: String, known: Set<String>, fixable: [String]) -> Bool {
        guard word.count >= shortestContentWord, word.allSatisfy(\.isLetter), !stopwords.contains(word),
            !known.contains(word)
        else { return false }
        return !fixable.contains { isWithinOneEdit($0, word) }
    }

    /// Whether two words differ by at most one inserted, deleted, or replaced letter.
    static func isWithinOneEdit(_ a: String, _ b: String) -> Bool {
        let a = Array(a)
        let b = Array(b)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0
        while i < a.count, i < b.count, a[i] == b[i] { i += 1 }
        if i == a.count || i == b.count { return true }  // equal, or one is the other with a letter at the end
        let (longer, shorter) = a.count >= b.count ? (a, b) : (b, a)
        if longer.count == shorter.count { return longer[(i + 1)...] == shorter[(i + 1)...] }
        return longer[(i + 1)...] == shorter[i...]
    }
}
