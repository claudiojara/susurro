import Foundation

/// The kinds of visual literal the token lint looks for.
enum LiteralRule: String, Sendable {
    case colorInitializer
    case cornerRadius
}

/// One place where a view source writes a visual value instead of asking the theme for it.
struct LiteralViolation: Equatable, Sendable {
    let file: String
    /// Counted from 1.
    let line: Int
    let rule: LiteralRule
}

enum LiteralScanner {
    static func violations(in source: String, file: String) -> [LiteralViolation] {
        let patterns: [(LiteralRule, String)] = [
            (.colorInitializer, #"\bColor\s*\("#),
            (.cornerRadius, #"\.cornerRadius\s*\(\s*[1-9]"#),
        ]
        var found: [LiteralViolation] = []
        for (index, text) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            for (rule, pattern) in patterns where text.range(of: pattern, options: .regularExpression) != nil {
                found.append(LiteralViolation(file: file, line: index + 1, rule: rule))
            }
        }
        return found
    }
}
