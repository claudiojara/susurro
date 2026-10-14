import Foundation

/// Strips what a model wraps around the text it was asked to clean: think blocks, code fences, and a leading label or
/// preamble ("Output:", "Here is the text:", "Aquí está el texto:"). It runs before the guard's checks.
public enum OutputSanitizer {
    /// A label such as "Output:" or "Texto corregido:".
    private static var label: Regex<Substring> {
        #/^\s*(?:output|cleaned(?: up)?(?: text| transcript| version)?|corrected(?: text| version)?|result|final(?: text)?|transcript|text|salida|resultado|texto(?: limpio| corregido| final)?|transcripci[oó]n(?: limpia)?)\s*:\s*/#
            .ignoresCase()
    }

    /// A sentence that introduces the text: "Sure, here is the cleaned text:", "Claro, aquí tienes el texto:".
    private static var preamble: Regex<Substring> {
        #/^\s*(?:(?:sure|certainly|of course|okay|ok|claro|por supuesto|vale|listo)\s*[,.!]*\s*)?(?:here is|here's|here are|this is|aqu[ií] (?:est[aá]|tienes|tiene|va)|ah[ií] (?:est[aá]|va)|este es|esta es)\b[^:\n]{0,60}:\s*/#
            .ignoresCase()
    }

    private static var thinkBlock: Regex<Substring> { #/<think(?:ing)?>.*?</think(?:ing)?>/#.dotMatchesNewlines() }
    private static var thinkClose: Regex<Substring> { #/</think(?:ing)?>/# }
    private static var thinkOpen: Regex<Substring> { #/<think(?:ing)?>/# }
    /// The tags of the request, which a model sometimes repeats around its reply or copies in whole.
    private static var styleTag: Regex<Substring> { #/<STYLE\b[^>]*>/# }
    private static var referenceBlock: Regex<(Substring, Substring)> {
        #/<(VOCABULARY|CONTEXT)>.*?</\1>/#.dotMatchesNewlines()
    }
    private static var transcriptBlock: Regex<(Substring, Substring)> {
        #/<TRANSCRIPT>(.*?)</TRANSCRIPT>/#.dotMatchesNewlines()
    }
    private static var strayTag: Regex<Substring> {
        #/</?(?:TRANSCRIPT|VOCABULARY|CONTEXT|BEFORE_CURSOR)>/#
    }

    /// A fence that opens a block: three backticks, an optional language, and the end of the line.
    private static var fenceMarker: Regex<Substring> { #/```[A-Za-z0-9_+\-]*[ \t]*\n/# }

    /// - Parameters:
    ///   - output: What the model returned.
    ///   - raw: The transcript it was given, when known. A preamble that the transcript itself starts with was dictated,
    ///     not added by the model, and is kept.
    ///   - reference: Text the model was given only as reference (the vocabulary terms and the lines before the cursor). A
    ///     reply that starts with whole lines of it copied them, and those lines are dropped.
    public static func sanitize(_ output: String, raw: String? = nil, reference: [String] = []) -> String {
        var text = removeRequestTags(from: removeThinking(from: output))
        text = text.replacing(fenceMarker, with: "")
        text = text.replacing("```", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A preamble can be followed by a label ("Here is the text:\nOutput: …"), so the strip is tried twice.
        for _ in 0..<2 {
            let stripped = removeLeadingLabel(from: text, raw: raw)
            if stripped == text { break }
            text = stripped
        }
        return removeCopiedReference(from: text.trimmingCharacters(in: .whitespacesAndNewlines), reference: reference)
    }

    /// Drops the leading lines of the reply that are, whole, a line of the reference text. A reply that is only such a line
    /// is kept, because the speaker may have said it.
    private static func removeCopiedReference(from text: String, reference: [String]) -> String {
        let known = Set(
            reference.flatMap { $0.split(whereSeparator: \.isNewline) }
                .map { TextCharacters.folded(String($0)).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        guard !known.isEmpty else { return text }
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        while lines.count > 1,
            let first = lines.first,
            first.allSatisfy(\.isWhitespace)
                || known.contains(TextCharacters.folded(String(first)).trimmingCharacters(in: .whitespaces))
        {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps what is inside `<TRANSCRIPT>` when the model repeated the request around its reply, and drops the style line
    /// and the vocabulary and context blocks it copied. Tags left over are removed.
    private static func removeRequestTags(from text: String) -> String {
        var result = text.replacing(styleTag, with: "").replacing(referenceBlock, with: "")
        if let match = result.firstMatch(of: transcriptBlock) { result = String(match.output.1) }
        return result.replacing(strayTag, with: "")
    }

    private static func removeThinking(from text: String) -> String {
        var result = text.replacing(thinkBlock, with: "")
        // A closing tag with no opening one: everything before it was thinking.
        if let last = result.matches(of: thinkClose).last {
            result = String(result[last.range.upperBound...])
        }
        // An opening tag that never closed: the answer was cut off inside the thinking.
        if let open = result.firstMatch(of: thinkOpen) {
            result = String(result[..<open.range.lowerBound])
        }
        return result
    }

    private static func removeLeadingLabel(from text: String, raw: String?) -> String {
        for pattern in [preamble, label] {
            guard let match = text.firstMatch(of: pattern) else { continue }
            if let raw, startsTheSameWay(raw, as: String(match.output)) { return text }
            return String(text[match.range.upperBound...])
        }
        return text
    }

    /// Whether the transcript begins with the words of the label, so that the speaker said them.
    private static func startsTheSameWay(_ raw: String, as label: String) -> Bool {
        let words = TextCharacters.folded(label)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
        guard !words.isEmpty else { return false }
        return TextCharacters.folded(raw).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(words)
    }
}
