import Foundation
import Testing

/// The shape of the public API of the atoms, read from their sources: what a caller passes to color an atom, and how
/// it names the text VoiceOver says. A convention that is only in a review is gone by the next atom.
@Suite("Atom conventions")
struct AtomConventionsTests {
    @Test("the atoms are found, each with a public initializer")
    func atomsAreFound() throws {
        let atoms = try AtomSources.atoms()
        #expect(atoms.map(\.name) == ["ActionButton", "Icon", "LevelBar", "Pill", "StatusDot", "TextLabel"])
        for atom in atoms { #expect(!atom.initializers.isEmpty, "\(atom.name) has no public init") }
    }

    @Test("no atom is colored with a color token: a color is a Tint")
    func atomsTakeATint() throws {
        for atom in try AtomSources.atoms() {
            for signature in atom.initializers {
                #expect(!signature.contains("ColorToken"), "\(atom.name) takes a ColorToken: \(signature)")
            }
        }
    }

    @Test("the text VoiceOver says is always the argument labeled label")
    func voiceOverTextIsLabeled() throws {
        let atoms = try AtomSources.atoms()
        for atom in atoms {
            for signature in atom.initializers {
                #expect(!signature.contains("_ label"), "\(atom.name) takes an unlabeled label: \(signature)")
            }
        }
        let withLabel = atoms.filter { atom in atom.initializers.contains { $0.contains("label:") } }
        #expect(withLabel.map(\.name) == ["Icon", "LevelBar", "StatusDot"])
    }

    @Test("the gallery of an atom that takes a Tint shows every Tint")
    func galleriesShowEveryTint() throws {
        let galleries = try AtomSources.text(of: "AtomGalleries.swift")
        for atom in ["TextLabel", "Icon", "Pill", "StatusDot", "LevelBar"] {
            let start = try #require(galleries.range(of: "extension \(atom) {"), "no gallery for \(atom)")
            let rest = galleries[start.upperBound...]
            let end = rest.range(of: "\n    extension ")?.lowerBound ?? rest.endIndex
            #expect(rest[..<end].contains("Tint.allCases"), "the \(atom) gallery does not use Tint.allCases")
        }
    }
}
