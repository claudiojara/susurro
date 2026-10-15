/// "a las 2, no, a las 3" said as "a las 3": the part the speaker took back goes, with the marker. See `FillerRemover`
/// for the rule and why it is narrow.
enum SelfCorrection {
    /// The words that take back what came before, between commas, as folded keys.
    private static let markers: [[String]] = [
        ["no"], ["digo"], ["perdon"], ["mejor", "dicho"], ["i", "mean"], ["sorry"],
    ]
    /// Words a correction never starts with: after them the commas are an answer, not a correction ("Sí, no, no sé").
    private static let answers: Set<String> = ["no", "si", "yes", "not"]
    private static let wordRange = 2...6

    /// Applies every correction in the text, left to right. Returns whether it changed anything.
    static func apply(_ pieces: inout [TextPiece]) -> Bool {
        var changed = false
        var index = 0
        while index < pieces.count {
            if pieces[index].text == ",", let removal = correction(at: index, in: pieces) {
                let wasCapitalized = pieces[removal.lowerBound].text.first?.isUppercase == true
                pieces.removeSubrange(removal)
                if wasCapitalized { FillerRemover.capitalizeWord(from: removal.lowerBound, in: &pieces) }
                changed = true
                index = removal.lowerBound
            } else {
                index += 1
            }
        }
        return changed
    }

    /// The pieces to remove when the comma at `comma` opens a correction: from the first word taken back to the first
    /// word of the correction.
    private static func correction(at comma: Int, in pieces: [TextPiece]) -> Range<Int>? {
        guard let replacementStart = afterMarker(from: comma + 1, in: pieces) else { return nil }
        let replacement = words(from: replacementStart, in: pieces)
        guard replacement.count >= wordRange.lowerBound, let first = replacement.first,
            !answers.contains(pieces[first].key)
        else { return nil }
        let clause = clauseWords(before: comma, in: pieces)
        // The latest word of the clause that the correction starts with, leaving two to six words to take back.
        for (offset, position) in clause.enumerated().reversed() {
            let taken = clause.count - offset
            guard wordRange.contains(taken), pieces[position].key == pieces[first].key else { continue }
            return position..<replacementStart
        }
        return nil
    }

    /// The index of the first word after ", marker, ", or nil when the comma does not open one.
    private static func afterMarker(from start: Int, in pieces: [TextPiece]) -> Int? {
        var index = start
        guard index < pieces.count, pieces[index].isSpace else { return nil }
        index += 1
        var marker: [String] = []
        while index < pieces.count, pieces[index].isWord || pieces[index].isSpace {
            if pieces[index].isWord { marker.append(pieces[index].key) }
            index += 1
            if marker.count > 2 { return nil }
        }
        guard markers.contains(marker), index < pieces.count, pieces[index].text == "," else { return nil }
        index += 1
        guard index < pieces.count, pieces[index].isSpace, !pieces[index].text.contains(where: \.isNewline) else {
            return nil
        }
        index += 1
        return index < pieces.count && pieces[index].isWord ? index : nil
    }

    /// The positions of the words from `start` up to the next punctuation.
    private static func words(from start: Int, in pieces: [TextPiece]) -> [Int] {
        var result: [Int] = []
        var index = start
        while index < pieces.count, !pieces[index].isPunctuation {
            if pieces[index].isWord { result.append(index) }
            index += 1
        }
        return result
    }

    /// The positions of the words of the clause that ends at `end`: back to the previous punctuation or line break.
    private static func clauseWords(before end: Int, in pieces: [TextPiece]) -> [Int] {
        var result: [Int] = []
        var index = end - 1
        while index >= 0, !pieces[index].isPunctuation, !pieces[index].text.contains(where: \.isNewline) {
            if pieces[index].isWord { result.insert(index, at: 0) }
            index -= 1
        }
        return result
    }
}
