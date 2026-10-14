import Domain
import Foundation

/// Notices a transcript that is not in the language the user speaks.
///
/// Parakeet detects the language itself, and on a short or hurried clip it can answer in English, or in another script,
/// to Spanish speech. The language it is asked for only filters the script, so it cannot be relied on. A transcript is
/// taken to have drifted when:
///
/// - it holds the engine's `<unk>` token, which a script filter leaves in the text;
/// - most of its letters are not Latin letters (a Cyrillic "Надежда." for a Spanish "ya está"); or
/// - the detector is clearly sure that it is another language and gives the expected one little chance.
///
/// A Spanish sentence with a few English words (a "commit", a "pull request") is still Spanish to the detector, and is
/// left alone.
public struct LanguageGuard: Sendable {
    /// The engine's marker for a token it could not write.
    static let unknownToken = "<unk>"
    /// The share of non-Latin letters above which the transcript is taken to be in another script.
    static let foreignScriptShare = 0.3
    /// How sure the detector must be of another language for the transcript to count as drifted.
    static let clearConfidence = 0.6
    /// The chance of the expected language below which another, clear one counts.
    static let unlikelyConfidence = 0.3

    private let detector: any LanguageDetecting
    private let expected: String

    /// - Parameter expected: The code of the language the user speaks.
    public init(detector: any LanguageDetecting, expected: String = "es") {
        self.detector = detector
        self.expected = expected
    }

    public func hasDrifted(_ text: String) -> Bool {
        if text.contains(Self.unknownToken) { return true }
        if Self.foreignScriptShare < Self.nonLatinShare(of: text) { return true }
        let guesses = detector.hypotheses(for: text, maximum: 3)
        guard let top = guesses.first, top.code != expected else { return false }
        let chanceOfExpected = guesses.first { $0.code == expected }?.confidence ?? 0
        return top.confidence >= Self.clearConfidence && chanceOfExpected < Self.unlikelyConfidence
    }

    /// The text without the engine's unknown-token markers, tidied where they were.
    public static func removingUnknownTokens(from text: String) -> String {
        guard text.contains(unknownToken) else { return text }
        let pieces = text.components(separatedBy: unknownToken).map { $0.trimmingCharacters(in: .whitespaces) }
        return pieces.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The share of the letters of `text` that are not Latin letters. Zero when there are no letters.
    static func nonLatinShare(of text: String) -> Double {
        var letters = 0
        var foreign = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if !isLatin(scalar) { foreign += 1 }
        }
        return letters == 0 ? 0 : Double(foreign) / Double(letters)
    }

    /// Latin letters: Basic Latin through Latin Extended-B, and Latin Extended Additional. Spanish, English, and the
    /// other languages of the Latin alphabet all fall inside.
    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x0250 || (0x1E00...0x1EFF).contains(scalar.value)
    }
}
