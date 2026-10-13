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
}
