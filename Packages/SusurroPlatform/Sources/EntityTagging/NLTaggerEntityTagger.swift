import Domain
import NaturalLanguage

/// Finds names, organizations, and places in a text with the system's language model, on this Mac and offline. The
/// model reads English and Spanish, among other languages, and picks the language of the text itself.
///
/// A name is only reported when it is written with a capital letter, so a lowercase text gives none: dictated or typed
/// lowercase text is too ambiguous for the tagger to be right, and a wrong term in the vocabulary costs more than a
/// missing one.
public struct NLTaggerEntityTagger: EntityTagger {
    private static let wanted: Set<NLTag> = [.personalName, .placeName, .organizationName]

    public init() {}

    public func properNouns(in text: String) -> [String] {
        guard !text.allSatisfy(\.isWhitespace) else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther, .joinNames]
        var nouns: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) {
            tag, range in
            if let tag, Self.wanted.contains(tag) {
                let noun = String(text[range])
                if noun.first?.isUppercase == true { nouns.append(noun) }
            }
            return true
        }
        return nouns
    }
}
