import Domain

/// Decides whether the model's reply to a command may replace the selection. The reply is sanitized first
/// (`OutputSanitizer`). Nothing is replaced when the reply is empty, reads like an assistant talking, gives the selection
/// back unchanged, or is out of proportion with it. `AnswerDetector` is not applied: the instruction is a request by
/// design, and following it is the point.
public enum CommandOutputGuard {
    public enum Verdict: Sendable, Equatable {
        /// The sanitized reply, which may replace the selection.
        case accepted(String)
        /// The selection is left as it is, for this reason.
        case rejected(Reason)
    }

    /// Why the reply was not used. The raw value is a fixed name that may be logged and kept on the record.
    public enum Reason: String, Sendable, Equatable {
        case emptyOutput
        case assistantMarker
        case unchanged
        case contraction
        case expansion
    }

    /// A reply under 15 % of the selection lost it; a summary in a few words still fits.
    private static let lowerPercent = 15
    /// A reply over five times the selection ran on; an expansion fits.
    private static let upperMultiple = 5
    /// A short selection may grow to this many characters whatever its length, which is about what the token limit of
    /// the reply allows for it (`CommandPromptBuilder.responseTokenLimit`).
    private static let upperFloor = 300
    /// A selection shorter than this has no lower bound: a word may become a letter.
    private static let lowerBoundFromSelection = 20

    public static func evaluate(selection: String, instruction: String, output: String) -> Verdict {
        let text = OutputSanitizer.sanitize(output, raw: selection)
        guard !text.isEmpty else { return .rejected(.emptyOutput) }
        let request = selection + "\n" + instruction
        guard AssistantMarkers.firstMarker(in: text, notIn: request, markers: AssistantMarkers.command) == nil else {
            return .rejected(.assistantMarker)
        }
        guard !SelectionReader.isSame(text, selection) else { return .rejected(.unchanged) }
        let selectionCount = selection.count
        let outputCount = text.count
        if outputCount > max(selectionCount * upperMultiple, upperFloor) { return .rejected(.expansion) }
        if selectionCount >= lowerBoundFromSelection, outputCount * 100 < selectionCount * lowerPercent {
            return .rejected(.contraction)
        }
        return .accepted(text)
    }
}
