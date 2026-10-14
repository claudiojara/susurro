import Foundation
import Testing

@Suite("Token lint")
struct TokenLintTests {
    @Test("the scanner reports the literal color and the literal corner radius of a fixture view")
    func scannerDetectsViolations() throws {
        let source = try String(contentsOf: PackageLayout.fixture("ViolatingView.swift.txt"), encoding: .utf8)
        let found = LiteralScanner.violations(in: source, file: "ViolatingView.swift")
        #expect(found.map(\.rule) == [.colorInitializer, .cornerRadius])
        #expect(found.map(\.line) == [6, 7])
    }

    /// Where a theme value becomes a SwiftUI one, so it is the one file that may write `Color(` and `.system(size:`.
    private let tokens = PackageLayout.sources("DesignSystem").appendingPathComponent("Tokens")
    private var bridge: URL { tokens.appendingPathComponent("ResolvedTheme+SwiftUI.swift") }

    @Test("the design system and UI sources hold no visual literal outside the bridge")
    func sourcesAreClean() throws {
        for target in ["DesignSystem", "SusurroUI"] {
            let report = try LiteralScanner.scan(PackageLayout.sources(target), allowing: [bridge])
            #expect(!report.files.isEmpty, "No Swift file was found in Sources/\(target).")
            #expect(report.violations.map(\.description) == [], "Sources/\(target) writes a visual literal.")
        }
    }

    @Test("the bridge is the only file of Tokens that holds literals, so it is the only one the lint allows")
    func theBridgeHoldsTheLiterals() throws {
        let report = try LiteralScanner.scan(tokens)
        #expect(report.files.contains("ResolvedTheme+SwiftUI.swift"))
        #expect(report.files.count > 1, "Tokens holds other files, which the lint must read")
        #expect(Set(report.violations.map(\.file)) == ["ResolvedTheme+SwiftUI.swift"])
        #expect(Set(report.violations.map(\.rule)).isSuperset(of: [.colorInitializer, .fontSize]))
    }

    @Test("the theming guide explains every rule and the remedy for it")
    func guideExplainsEveryRule() throws {
        let guide = try String(contentsOf: PackageLayout.repositoryFile("docs/theming.md"), encoding: .utf8)
        for rule in LiteralRule.allCases {
            #expect(guide.contains("| `\(rule.rawValue)` |"), "docs/theming.md has no row for \(rule.rawValue)")
        }
    }
}
