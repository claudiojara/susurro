import Domain
import Synchronization

/// An entity tagger with scripted answers: the nouns of a text it knows, and none for any other. It records every text
/// it was given.
public final class FakeEntityTagger: EntityTagger {
    private let answers: [String: [String]]
    private let texts = Mutex<[String]>([])

    public init(_ answers: [String: [String]] = [:]) {
        self.answers = answers
    }

    /// The texts `properNouns(in:)` received, in order.
    public var taggedTexts: [String] { texts.withLock { $0 } }

    public func properNouns(in text: String) -> [String] {
        texts.withLock { $0.append(text) }
        return answers[text] ?? []
    }
}
