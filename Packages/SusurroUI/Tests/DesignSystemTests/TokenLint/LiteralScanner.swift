import Foundation

/// The kinds of visual literal the token lint looks for. A view asks the theme for each of these instead, and `remedy`
/// says how. `docs/theming.md` has a row for each rule, which a test checks.
enum LiteralRule: String, Sendable, CaseIterable {
    /// `Color(...)`, `NSColor(...)`, `CGColor(...)`, `Color.init(...)`, `#colorLiteral(...)`.
    case colorInitializer
    /// `Color.red`, and a system color or style written as `.red` or `.secondary` in a color position
    /// (`.foregroundStyle(.red)`, `.background(.white)`, `color: .black`). `Color.clear` is structural and allowed.
    case namedColor
    /// `0xFF8800` or `"#FF8800"`.
    case hexLiteral
    /// `.system(size:`, `.custom(_, size:`, `NSFont.systemFont(ofSize:`, `NSFont(name:size:)`.
    case fontSize
    /// A number other than zero in `padding`, `frame`, `offset`, `lineSpacing`, `Spacer`, `CGSize`, and the like, or in
    /// the expression after a `spacing:` or `minLength:` label.
    case spacing
    /// A number other than zero in `cornerRadius`, or in the expression after a corner radius label.
    case cornerRadius
    /// A number other than zero as the radius of a shadow, a blur, or a gradient (`radius:`, `endRadius:`).
    case effectRadius
    /// A number other than zero as a `lineWidth:`, or in `border`.
    case strokeWidth
    /// A number other than zero as a `duration:`, a `delay`, or a `blendDuration:`.
    case animationDuration
    /// A number other than zero as `response:`, `dampingFraction:`, `bounce:`, and the other numbers of a spring.
    case animationSpring
    /// A number other than zero assigned to a `CGFloat`, or to a constant named for a length (`let cornerRadius = 16`).
    case visualConstant

    /// What to write instead.
    var remedy: String {
        switch self {
        case .colorInitializer, .namedColor:
            "Ask the theme for a color role, such as theme.swiftUIColor(.textPrimary). System colors and styles ignore the theme."
        case .hexLiteral:
            "Write the color as a palette entry in DefaultTheme.json and use the token that points at it."
        case .fontSize:
            "Ask the theme for a type role, such as theme.font(.body). Only the bridge builds a font from a size."
        case .spacing:
            "Use a spacing token, such as theme.spacing(.md), or a size token for a component, such as theme.size(.statusDot)."
        case .cornerRadius:
            "Use a radius token, such as theme.radius(.md)."
        case .effectRadius:
            "A shadow, a blur, or a gradient radius has no token yet. Add a group for them before using one."
        case .strokeWidth:
            "Line widths have no tokens yet. Use the default hairline, or add a token for the width."
        case .animationDuration:
            "Use a duration token, such as theme.easing(.fast, motionEnabled:)."
        case .animationSpring:
            "Use the spring of the theme, theme.spring(motionEnabled:), which is built from springResponse and springDamping."
        case .visualConstant:
            "Do not keep a visual value in a constant. Ask the theme for it where it is used."
        }
    }
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
        hits.formUnion(implicitColorHits(in: text.code))
        hits.formUnion(constantHits(in: text.code))
        let lines = source.components(separatedBy: "\n")
        return hits.sorted { ($0.line, $0.rule.rawValue) < ($1.line, $1.rule.rawValue) }
            .map {
                LiteralViolation(
                    file: file, line: $0.line, rule: $0.rule,
                    text: lines[$0.line - 1].trimmingCharacters(in: .whitespaces))
            }
    }

    /// Reads every `.swift` file below `folder`, except the files in `allowing` and those below a folder in it.
    static func scan(_ folder: URL, allowing: [URL] = []) throws -> ScanReport {
        let base = folder.resolvingSymlinksInPath()
        let skipped = allowing.map { $0.resolvingSymlinksInPath().path }
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var files: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let path = url.resolvingSymlinksInPath().path
            guard !skipped.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
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
        (.colorInitializer, #"\b(?:NS|UI|CG)?Color\s*(?:\.\s*init\s*)?\("#),
        (.colorInitializer, #"#colorLiteral\s*\("#),
        (.namedColor, #"\b(?:NS|UI|CG)?Color\s*\.\s*(?!clear\b|init\b)[a-z]\w*"#),
        (.hexLiteral, #"\b0[xX][0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?\b"#),
        (.fontSize, #"\.\s*system\s*\(\s*size\s*:"#),
        (.fontSize, #"\.\s*custom\s*\([^)]*\b(?:fixedSize|size)\s*:"#),
        (.fontSize, #"\bofSize\s*:"#),
        (.fontSize, #"\b(?:NS|UI)Font\s*\(\s*name\s*:"#),
    ]

    private static let hexColorString = ##""#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?""##

    private static let number = #"(?<![\w.])\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?(?![\w.])"#

    /// A rule about numbers, and where it looks for them: in the arguments of calls written `.name(`, in the arguments of
    /// types written `Name(`, and in the expression after an argument label.
    private struct NumericRule {
        let rule: LiteralRule
        let calls: String
        let constructors: String
        let labels: String
    }

    private static let numeric: [NumericRule] = [
        NumericRule(
            rule: .spacing,
            calls:
                "padding|frame|offset|lineSpacing|tracking|kerning|baselineOffset|position|safeAreaPadding|contentMargins",
            constructors: "Spacer|CGSize|CGPoint|CGRect|EdgeInsets|NSEdgeInsets|NSSize|NSPoint|NSRect",
            labels: "spacing|lineSpacing|horizontalSpacing|verticalSpacing"),
        NumericRule(
            rule: .cornerRadius, calls: "cornerRadius", constructors: "",
            labels: #"\w*[cC]ornerRadius|cornerSize|(?:top|bottom)(?:Leading|Trailing)Radius"#),
        NumericRule(
            rule: .effectRadius, calls: "", constructors: "",
            labels: #"(?!\w*[cC]ornerRadius\b|(?:top|bottom)(?:Leading|Trailing)Radius\b)\w*[rR]adius"#),
        NumericRule(rule: .strokeWidth, calls: "border", constructors: "", labels: "lineWidth"),
        NumericRule(
            rule: .animationDuration, calls: "delay", constructors: "", labels: "duration|blendDuration|delay"),
        NumericRule(
            rule: .animationSpring, calls: "", constructors: "",
            labels: "response|dampingFraction|bounce|extraBounce|stiffness|damping|mass"),
    ]

    /// A label is not the name of a declaration: in `let radius: CGFloat = 4` the colon belongs to the type.
    private static let declaration = #"(?<!let\s)(?<!var\s)"#

    private static func numberHits(in code: String) -> Set<Hit> {
        let text = code as NSString
        var hits = Set<Hit>()
        for rule in numeric {
            var regions: [NSRange] = []
            // A call such as `.padding(8)` or a type such as `CGSize(width: 1, height: 2)`: between its parentheses.
            for (names, prefix) in [(rule.calls, #"\."#), (rule.constructors, #"\b"#)] where !names.isEmpty {
                for call in matches(#"\#(prefix)\s*(?:\#(names))\s*\("#, in: code) {
                    let start = NSMaxRange(call)
                    regions.append(
                        NSRange(
                            location: start, length: closingBracket(from: start, in: text, commaEnds: false) - start))
                }
            }
            // An argument such as `spacing: base * 2`: the expression after the label, up to the comma that ends it.
            for label in matches(#"\#(declaration)\b(?:\#(rule.labels))\s*:"#, in: code) {
                let start = NSMaxRange(label)
                regions.append(NSRange(location: start, length: closingBracket(from: start, in: text) - start))
            }
            for region in regions {
                for range in matches(number, in: code, within: region) where isNotZero(text.substring(with: range)) {
                    hits.insert(Hit(rule.rule, at: range.location, in: code))
                }
            }
        }
        return hits
    }

    /// The calls and labels that take a color, and the system colors and styles that `.name` can stand for in them.
    private static let colorCalls =
        "foregroundStyle|foregroundColor|background|tint|fill|stroke|strokeBorder|border|accentColor|overlay|shadow"
    private static let colorLabels =
        "color|colors|foregroundColor|backgroundColor|tintColor|fillColor|strokeColor|shadowColor"
    private static let systemColors =
        "red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|gray|black|primary|secondary|tertiary"
        + "|quaternary|quinary|tint|separator|accentColor"

    /// `.red` in a place that takes a color. A leading dot that follows a name or a bracket is a member access, and one
    /// that follows `==` or `!=` is a comparison, not a color.
    private static let implicitColor = #"(?<![\w)\]}])(?<!==\s)(?<!!=\s)\.(?:\#(systemColors))\b"#

    private static func implicitColorHits(in code: String) -> Set<Hit> {
        let text = code as NSString
        var regions: [NSRange] = []
        for call in matches(#"\.\s*(?:\#(colorCalls))\s*\("#, in: code) {
            let start = NSMaxRange(call)
            regions.append(
                NSRange(location: start, length: closingBracket(from: start, in: text, commaEnds: false) - start))
        }
        for label in matches(#"\#(declaration)\b(?:\#(colorLabels))\s*:"#, in: code) {
            let start = NSMaxRange(label)
            regions.append(NSRange(location: start, length: closingBracket(from: start, in: text) - start))
        }
        var hits = Set<Hit>()
        for region in regions {
            for range in matches(implicitColor, in: code, within: region) {
                hits.insert(Hit(.namedColor, at: range.location, in: code))
            }
        }
        return hits
    }

    /// Names that say a constant is a length or a time on screen.
    private static let visualName =
        #"(?i)radius|spacing|padding|inset|margin|thickness|linewidth|size|width|height|duration|offset|gap|delay|corner"#

    /// `let name: Type = 16`: a number other than zero that is the whole value of a `CGFloat`, or of a constant whose name
    /// is a length.
    private static func constantHits(in code: String) -> Set<Hit> {
        let text = code as NSString
        let pattern = #"\b(?:let|var)\s+(\w+)\s*(?::\s*([A-Za-z_][\w.]*))?\s*=\s*-?\s*(\#(number))\s*(?:$|;)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            preconditionFailure("The lint pattern is not a regular expression: \(pattern)")
        }
        var hits = Set<Hit>()
        for match in expression.matches(in: code, range: NSRange(location: 0, length: text.length)) {
            let name = text.substring(with: match.range(at: 1))
            let type = match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2))
            let literal = text.substring(with: match.range(at: 3))
            guard isNotZero(literal) else { continue }
            if type == "CGFloat" || name.range(of: visualName, options: .regularExpression) != nil {
                hits.insert(Hit(.visualConstant, at: match.range(at: 3).location, in: code))
            }
        }
        return hits
    }

    private static func isNotZero(_ literal: String) -> Bool {
        Double(literal.replacingOccurrences(of: "_", with: "")).map { $0 != 0 } ?? true
    }

    /// Where the text that starts at `start` ends: at the bracket that closes what was open before `start`, or, for an
    /// argument, at the comma that ends it. Brackets opened after `start` are skipped over. Calls pass `commaEnds: false`.
    private static func closingBracket(from start: Int, in text: NSString, commaEnds: Bool = true) -> Int {
        var depth = 0
        for offset in start..<text.length {
            switch text.character(at: offset) {
            case UInt16(UInt8(ascii: "(")), UInt16(UInt8(ascii: "[")), UInt16(UInt8(ascii: "{")): depth += 1
            case UInt16(UInt8(ascii: ")")), UInt16(UInt8(ascii: "]")), UInt16(UInt8(ascii: "}")):
                if depth == 0 { return offset }
                depth -= 1
            case UInt16(UInt8(ascii: ",")) where commaEnds && depth == 0: return offset
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
