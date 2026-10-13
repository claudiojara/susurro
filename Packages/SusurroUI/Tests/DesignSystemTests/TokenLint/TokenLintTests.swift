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

    /// `Tokens/` is where a theme value becomes a SwiftUI one, so it is the one place that may write `Color(` and
    /// `.system(size:`.
    private let tokens = PackageLayout.sources("DesignSystem").appendingPathComponent("Tokens")

    @Test("the design system and UI sources hold no visual literal outside Tokens")
    func sourcesAreClean() throws {
        for target in ["DesignSystem", "SusurroUI"] {
            let report = try LiteralScanner.scan(PackageLayout.sources(target), allowing: [tokens])
            #expect(!report.files.isEmpty, "No Swift file was found in Sources/\(target).")
            #expect(report.violations.map(\.description) == [], "Sources/\(target) writes a visual literal.")
        }
    }
}
