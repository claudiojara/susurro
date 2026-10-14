import Domain

/// Decides whether a cleaner's output may replace the raw transcript. The output is sanitized first. The raw transcript
/// is used, with a reason, when the output is empty, reads like an assistant talking, answers the transcript instead of
/// cleaning it (see `AnswerDetector`), or is out of proportion with it.
public enum OutputGuard {
    public enum Verdict: Sendable, Equatable {
        /// The sanitized output, which may be used.
        case accepted(String)
        /// The raw transcript is used instead, for this reason.
        case fallback(FallbackReason)
    }

    /// A limit on the length of the output as a multiple of the raw length, written as a fraction so that a ratio exactly
    /// at the limit is decided without rounding.
    private struct Ratio {
        let numerator: Int
        let denominator: Int

        /// Whether `output` is longer than this many times `raw`.
        func isExceeded(by output: Int, raw: Int) -> Bool { output * denominator > raw * numerator }
        /// Whether `output` is shorter than this many times `raw`.
        func isUndercut(by output: Int, raw: Int) -> Bool { output * denominator < raw * numerator }
    }

    private static let shortRaw = 50
    private static let mediumRaw = 150
    private static let lowerBoundFromRaw = 20
    private static let upperLimitShort = Ratio(numerator: 4, denominator: 1)
    private static let upperLimitMedium = Ratio(numerator: 5, denominator: 2)
    private static let upperLimitLong = Ratio(numerator: 2, denominator: 1)
    private static let lowerLimit = Ratio(numerator: 2, denominator: 5)

    /// - Parameter reference: The vocabulary terms and the lines before the cursor the model was given as reference. A
    ///   reply that starts by repeating them is stripped of them.
    public static func evaluate(raw: String, output: String, reference: [String] = []) -> Verdict {
        let text = OutputSanitizer.sanitize(output, raw: raw, reference: reference)
        guard !text.isEmpty else { return .fallback(.emptyOutput) }
        guard AssistantMarkers.firstMarker(in: text, notIn: raw) == nil else { return .fallback(.assistantMarker) }
        guard !AnswerDetector.isAnswer(raw: raw, output: text, reference: reference) else {
            return .fallback(.answered)
        }
        let rawCount = raw.count
        let outputCount = text.count
        let upper =
            rawCount < shortRaw ? upperLimitShort : rawCount < mediumRaw ? upperLimitMedium : upperLimitLong
        if upper.isExceeded(by: outputCount, raw: rawCount) { return .fallback(.expansion) }
        if rawCount >= lowerBoundFromRaw, lowerLimit.isUndercut(by: outputCount, raw: rawCount) {
            return .fallback(.contraction)
        }
        return .accepted(text)
    }
}
