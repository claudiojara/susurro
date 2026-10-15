/// A phrase of the user's (a spoken form, a trigger) as rules match it: its words compared without case or accents, its
/// punctuation as written, and any white space between them matching any white space. Punctuation at either end of the
/// phrase is not part of it.
struct Phrase: Sendable {
    let pieces: [TextPiece]

    init(_ text: String) {
        var pieces = WordLexer.pieces(of: text)
        while let first = pieces.first, !first.isWord { pieces.removeFirst() }
        while let last = pieces.last, !last.isWord { pieces.removeLast() }
        self.pieces = pieces
    }

    var isEmpty: Bool { pieces.isEmpty }
    /// The key of its first word, by which a pass finds the phrases that can start at a word.
    var firstKey: String { pieces.first?.key ?? "" }
    var wordCount: Int { pieces.count(where: \.isWord) }
    /// The keys of its words, in order.
    var keys: [String] { pieces.filter(\.isWord).map(\.key) }

    /// How many pieces of `text` the phrase covers when it starts at `index`, or nil when it does not start there. A
    /// match ends on a word, and the word after it must not continue it: the pieces already split there.
    func matchLength(in text: [TextPiece], at index: Int) -> Int? {
        guard !pieces.isEmpty, index + pieces.count <= text.count else { return nil }
        for (offset, piece) in pieces.enumerated() {
            let candidate = text[index + offset]
            guard candidate.kind == piece.kind else { return nil }
            switch piece.kind {
            case .word: guard candidate.key == piece.key else { return nil }
            case .space: continue
            case .punctuation: guard candidate.text == piece.text else { return nil }
            }
        }
        return pieces.count
    }
}
