import Foundation
import Testing

/// The shape of the public API of the atoms, read from their sources: what a caller passes to color an atom, and how
/// it names the text VoiceOver says. A convention that is only in a review is gone by the next atom.
@Suite("Atom conventions")
struct AtomConventionsTests {
    private let atoms = PackageLayout.sources("DesignSystem").appendingPathComponent("Atoms")

    /// The `public init(...)` signatures of an atom, one text each.
    private func initializers(of file: URL) throws -> [String] {
        let source = try String(contentsOf: file, encoding: .utf8)
        let signature = /public init\([^{]*\{/
        return source.matches(of: signature).map { String($0.output) }
    }

    private func atomFiles() throws -> [URL] {
        let all = try FileManager.default.contentsOfDirectory(at: atoms, includingPropertiesForKeys: nil)
        return all.filter { file in
            let source = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            return source.contains("public struct") && source.contains(": View")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("the atoms are found, each with a public initializer")
    func atomsAreFound() throws {
        let files = try atomFiles()
        #expect(
            files.map(\.lastPathComponent) == [
                "ActionButton.swift", "Icon.swift", "LevelBar.swift", "Pill.swift", "StatusDot.swift",
                "TextLabel.swift",
            ])
        for file in files {
            #expect(try !initializers(of: file).isEmpty, "\(file.lastPathComponent) has no public init")
        }
    }

    @Test("no atom is colored with a color token: a color is a Tint")
    func atomsTakeATint() throws {
        for file in try atomFiles() {
            for signature in try initializers(of: file) {
                #expect(!signature.contains("ColorToken"), "\(file.lastPathComponent) takes a ColorToken: \(signature)")
            }
        }
    }

    @Test("the text VoiceOver says is always the argument labeled label")
    func voiceOverTextIsLabeled() throws {
        for file in try atomFiles() {
            for signature in try initializers(of: file) {
                #expect(
                    !signature.contains("_ label"), "\(file.lastPathComponent) takes an unlabeled label: \(signature)")
            }
        }
        let withLabel = try atomFiles().filter { file in
            try initializers(of: file).contains { $0.contains("label:") }
        }
        #expect(withLabel.map(\.lastPathComponent) == ["Icon.swift", "LevelBar.swift", "StatusDot.swift"])
    }

    @Test("the gallery of an atom that takes a Tint shows every Tint")
    func galleriesShowEveryTint() throws {
        let galleries = try String(contentsOf: atoms.appendingPathComponent("AtomGalleries.swift"), encoding: .utf8)
        for atom in ["TextLabel", "Icon", "Pill", "StatusDot", "LevelBar"] {
            let start = try #require(galleries.range(of: "extension \(atom) {"), "no gallery for \(atom)")
            let rest = galleries[start.upperBound...]
            let end = rest.range(of: "\n    extension ")?.lowerBound ?? rest.endIndex
            #expect(rest[..<end].contains("Tint.allCases"), "the \(atom) gallery does not use Tint.allCases")
        }
    }
}
