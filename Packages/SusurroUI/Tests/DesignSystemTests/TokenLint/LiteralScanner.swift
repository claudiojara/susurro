import Foundation

/// The kinds of visual literal the token lint looks for. A view asks the theme for each of these instead.
enum LiteralRule: String, Sendable {
    /// `Color(...)`, `NSColor(...)`, `Color.init(...)`.
    case colorInitializer
    /// `Color.red` and the like. `Color.clear` is structural and allowed.
    case namedColor
    /// `0xFF8800` or `"#FF8800"`.
    case hexLiteral
    /// `.system(size:` and `.custom(_, size:`.
    case fontSize
    /// A number other than zero in `padding`, `frame`, `offset`, or a `spacing:` argument.
    case spacing
    /// A number other than zero in `cornerRadius`, or in any `...radius:` argument.
    case cornerRadius
    /// A number other than zero as a `duration:`, `response:`, `delay`, and so on.
    case animationDuration
}

/// One place where a view source writes a visual value instead of asking the theme for it.
struct LiteralViolation: Equatable, Sendable, CustomStringConvertible {
    let file: String
    /// Counted from 1.
    let line: Int
    let rule: LiteralRule
    /// The line as written, without its indentation.
    let text: String

    var description: String { "\(file):\(line): \(rule.rawValue): \(text)" }
}

struct ScanReport: Sendable {
    /// The Swift files that were read, relative to the folder, in order.
    let files: [String]
    let violations: [LiteralViolation]
}

/// Finds visual literals in Swift source text: the token lint. It reads text, not syntax, so it sees what a view writes
/// (`.padding(8)`) and not what it means. Comments and the inside of strings are not code and are skipped, except that
/// a string holding a hex color is a color. The text of a string interpolation counts as part of the string.
///
/// A number is allowed only when it is zero, which is no space, no radius, and no animation, not a design choice.
enum LiteralScanner {
    /// Every violation in `source`, one per line and rule, in line order. `file` only names it in the report.
    static func violations(in source: String, file: String) -> [LiteralViolation] {
        let text = StrippedSource(source)
        var hits = Set<Hit>()
        for (rule, pattern) in patterns {
            for range in matches(pattern, in: text.code) { hits.insert(Hit(rule, at: range.location, in: text.code)) }
        }
        for range in matches(hexColorString, in: text.visible) {
            hits.insert(Hit(.hexLiteral, at: range.location, in: text.visible))
        }
        hits.formUnion(numberHits(in: text.code))
        let lines = source.components(separatedBy: "\n")
        return hits.sorted { ($0.line, $0.rule.rawValue) < ($1.line, $1.rule.rawValue) }
            .map {
                LiteralViolation(
                    file: file, line: $0.line, rule: $0.rule,
                    text: lines[$0.line - 1].trimmingCharacters(in: .whitespaces))
            }
    }

    /// Reads every `.swift` file below `folder`, except those below a folder in `allowing`.
    static func scan(_ folder: URL, allowing: [URL] = []) throws -> ScanReport {
        let base = folder.resolvingSymlinksInPath()
        let skipped = allowing.map { $0.resolvingSymlinksInPath().path + "/" }
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var files: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let path = url.resolvingSymlinksInPath().path
            guard !skipped.contains(where: path.hasPrefix) else { continue }
            files.append(String(path.dropFirst(base.path.count + 1)))
        }
        files.sort()
        let found = try files.flatMap { relative in
            let source = try String(contentsOf: base.appendingPathComponent(relative), encoding: .utf8)
            return violations(in: source, file: relative)
        }
        return ScanReport(files: files, violations: found)
    }

    // MARK: Rules

    private struct Hit: Hashable {
        let rule: LiteralRule
        let line: Int

        init(_ rule: LiteralRule, at offset: Int, in text: String) {
            self.rule = rule
            line = (text as NSString).substring(to: offset).filter { $0 == "\n" }.count + 1
        }
    }

    private static let patterns: [(LiteralRule, String)] = [
        (.colorInitializer, #"\b(?:NS|UI)?Color\s*(?:\.\s*init\s*)?\("#),
        (.namedColor, #"\b(?:NS|UI)?Color\s*\.\s*(?!clear\b|init\b)[a-z]\w*"#),
        (.hexLiteral, #"\b0[xX][0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?\b"#),
        (.fontSize, #"\.\s*system\s*\(\s*size\s*:"#),
        (.fontSize, #"\.\s*custom\s*\([^)]*\bsize\s*:"#),
    ]

    private static let hexColorString = ##""#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?""##

    private static let number = #"(?<![\w.])\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?(?![\w.])"#

    /// The rules about a number: the calls whose arguments may hold none, and the argument labels that may not be
    /// followed by one.
    private static let numeric: [(rule: LiteralRule, calls: String, labels: String)] = [
        (.spacing, "padding|frame|offset", "spacing|lineSpacing|horizontalSpacing|verticalSpacing"),
        (.cornerRadius, "cornerRadius", #"\w*[rR]adius"#),
        (.animationDuration, "delay", "duration|response|dampingFraction|blendDuration|delay|bounce|extraBounce"),
    ]

    private static func numberHits(in code: String) -> Set<Hit> {
        let text = code as NSString
        var hits = Set<Hit>()
        for (rule, calls, labels) in numeric {
            // A call such as `.padding(8)`: any number other than zero between its parentheses.
            for call in matches(#"\.\s*(?:\#(calls))\s*\("#, in: code) {
                let start = NSMaxRange(call)
                let arguments = NSRange(location: start, length: closingParenthesis(from: start, in: text) - start)
                for range in matches(number, in: code, within: arguments) where isNotZero(text.substring(with: range)) {
                    hits.insert(Hit(rule, at: range.location, in: code))
                }
            }
            // An argument such as `spacing: 8`.
            for range in matches(#"\b(?:\#(labels))\s*:\s*-?\s*(\#(number))"#, in: code, group: 1)
            where isNotZero(text.substring(with: range)) {
                hits.insert(Hit(rule, at: range.location, in: code))
            }
        }
        return hits
    }

    private static func isNotZero(_ literal: String) -> Bool {
        Double(literal.replacingOccurrences(of: "_", with: "")).map { $0 != 0 } ?? true
    }

    /// The offset of the parenthesis that closes the one opened just before `start`.
    private static func closingParenthesis(from start: Int, in text: NSString) -> Int {
        var depth = 1
        for offset in start..<text.length {
            switch text.character(at: offset) {
            case UInt16(UInt8(ascii: "(")): depth += 1
            case UInt16(UInt8(ascii: ")")):
                depth -= 1
                if depth == 0 { return offset }
            default: break
            }
        }
        return text.length
    }

    private static func matches(_ pattern: String, in text: String, within range: NSRange? = nil, group: Int = 0)
        -> [NSRange]
    {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("The lint pattern is not a regular expression: \(pattern)")
        }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return expression.matches(in: text, range: range ?? whole).map { $0.range(at: group) }
    }
}

/// Source text with the parts that are not code blanked out. Every byte but a newline is replaced by a space, so the
/// offsets and the line numbers stay those of the original.
private struct StrippedSource {
    /// Comments and the inside of strings blanked.
    let code: String
    /// Comments blanked; strings intact.
    let visible: String

    init(_ source: String) {
        let input = Array(source.utf8)
        var code = input
        var visible = input
        var index = 0
        while index < input.count {
            if input.hasPrefix("//", at: index) {
                let end = input[index...].firstIndex(of: Self.newline) ?? input.count
                Self.blank(&code, index..<end)
                Self.blank(&visible, index..<end)
                index = end
            } else if input.hasPrefix("/*", at: index) {
                let end = Self.endOfBlockComment(in: input, from: index)
                Self.blank(&code, index..<end)
                Self.blank(&visible, index..<end)
                index = end
            } else if let string = Self.string(in: input, at: index) {
                Self.blank(&code, string.content)
                index = string.end
            } else {
                index += 1
            }
        }
        self.code = String(decoding: code, as: UTF8.self)
        self.visible = String(decoding: visible, as: UTF8.self)
    }

    private static let newline = UInt8(ascii: "\n")

    private static func blank(_ bytes: inout [UInt8], _ range: Range<Int>) {
        for index in range where bytes[index] != newline { bytes[index] = UInt8(ascii: " ") }
    }

    /// Block comments nest in Swift.
    private static func endOfBlockComment(in input: [UInt8], from start: Int) -> Int {
        var depth = 0
        var index = start
        while index < input.count {
            if input.hasPrefix("/*", at: index) {
                depth += 1
                index += 2
            } else if input.hasPrefix("*/", at: index) {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else {
                index += 1
            }
        }
        return input.count
    }

    /// The string literal that starts at `start`, if one does: plain, raw (`#"..."#`), or multi-line (`"""`). A plain
    /// string that is not closed on its line ends at the line.
    private static func string(in input: [UInt8], at start: Int) -> (content: Range<Int>, end: Int)? {
        var quote = start
        while quote < input.count, input[quote] == UInt8(ascii: "#") { quote += 1 }
        guard quote < input.count, input[quote] == UInt8(ascii: "\"") else { return nil }
        let hashes = String(repeating: "#", count: quote - start)
        let multiline = input.hasPrefix("\"\"\"", at: quote)
        let quotes = multiline ? "\"\"\"" : "\""
        let closing = quotes + hashes
        let contentStart = quote + quotes.utf8.count
        var index = contentStart
        while index < input.count {
            if input[index] == UInt8(ascii: "\\"), input.hasPrefix(hashes, at: index + 1) {
                index += 2 + hashes.utf8.count
            } else if input.hasPrefix(closing, at: index) {
                return (contentStart..<index, index + closing.utf8.count)
            } else if !multiline, input[index] == newline {
                break
            } else {
                index += 1
            }
        }
        let end = min(index, input.count)
        return (contentStart..<end, end)
    }
}

extension Array where Element == UInt8 {
    fileprivate func hasPrefix(_ prefix: String, at index: Int) -> Bool {
        let bytes = Array(prefix.utf8)
        return index >= 0 && index + bytes.count <= count && self[index..<index + bytes.count].elementsEqual(bytes)
    }
}
