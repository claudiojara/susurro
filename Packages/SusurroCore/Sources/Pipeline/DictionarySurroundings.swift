import Domain
import TextShaping

/// The surroundings of a dictation when the only thing known about it is the user's dictionary: the neutral style of an
/// unknown app, the dictionary as the vocabulary, and no text around the cursor. It is what the app uses until the
/// context capture supplies the rest, and what it falls back to when that has nothing.
public struct DictionarySurroundings: SurroundingsSource {
    private let dictionary: any UserDictionary
    private let builder: VocabularyBuilder

    public init(dictionary: any UserDictionary, builder: VocabularyBuilder) {
        self.dictionary = dictionary
        self.builder = builder
    }

    public func surroundings() async -> DictationSurroundings {
        let vocabulary = builder.build(VocabularySources(dictionary: dictionary.terms()))
        return DictationSurroundings(style: DictationSurroundings.unknown.style, vocabulary: vocabulary)
    }
}
