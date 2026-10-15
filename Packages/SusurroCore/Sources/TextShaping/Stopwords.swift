/// Words a cleaner may add or change without answering anything, and that are never worth a dictionary term: articles,
/// pronouns, prepositions, conjunctions, and the common forms of the verbs that join a sentence, in Spanish and English,
/// folded (lowercase, no accents). Only words of three letters or more are here, since shorter ones are never looked at.
enum Stopwords {
    static func contains(_ folded: String) -> Bool {
        all.contains(folded)
    }

    static let all: Set<String> = [
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
}
