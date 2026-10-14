import Foundation
import Testing

/// Every atom is shown, snapshotted, and checked for its colors. The atoms are found by reading the folder, so a new one
/// that skips a step fails here, and the message says which step. The steps are in "Adding an atom" in
/// `docs/snapshots.md`.
@Suite("Atom coverage")
struct AtomCoverageTests {
    @Test("every atom has a gallery, a preview, a canvas, a snapshot test, and a color test")
    func everyAtomIsCovered() throws {
        let atoms = try AtomSources.atoms()
        #expect(atoms.count >= 6, "Only \(atoms.count) atoms were found: the search for them is broken.")
        let galleries = try AtomSources.text(of: "AtomGalleries.swift")
        let canvases = try AtomSources.text(of: "AtomCanvas.swift", in: AtomSources.tests)
        let snapshots = try AtomSources.text(of: "AtomSnapshotTests.swift", in: AtomSources.tests)
        let colors = try AtomSources.text(of: "AtomColorTests.swift", in: AtomSources.tests)
        for atom in atoms {
            let name = atom.name
            #expect(galleries.contains("extension \(name) {"), "\(name) has no gallery in AtomGalleries.swift")
            #expect(atom.source.contains("#Preview(\"\(name)\")"), "\(name) has no #Preview")
            #expect(atom.source.contains("\(name).Gallery()"), "The preview of \(name) does not show its gallery")
            #expect(canvases.contains("\(name).Gallery()"), "\(name) has no canvas in AtomCanvas.swift")
            #expect(snapshots.contains("\(name).Gallery()"), "\(name) has no snapshot test in AtomSnapshotTests.swift")
            #expect(colors.contains("\(name)("), "\(name) has no test of its colors in AtomColorTests.swift")
        }
    }

    @Test("the gallery, the canvas, and the snapshot of an atom are the same view")
    func theCanvasesAndSnapshotsMatch() throws {
        let canvases = try AtomSources.text(of: "AtomCanvas.swift", in: AtomSources.tests)
        let snapshots = try AtomSources.text(of: "AtomSnapshotTests.swift", in: AtomSources.tests)
        let inCanvases = Set(canvases.matches(of: /(\w+)\.Gallery\(\)/).map { String($0.output.1) })
        let inSnapshots = Set(snapshots.matches(of: /(\w+)\.Gallery\(\)/).map { String($0.output.1) })
        #expect(!inCanvases.isEmpty)
        #expect(inCanvases == inSnapshots)
        #expect(inCanvases == Set(try AtomSources.atoms().map(\.name)))
    }
}
