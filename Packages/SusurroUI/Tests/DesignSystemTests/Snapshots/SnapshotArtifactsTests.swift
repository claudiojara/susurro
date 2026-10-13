import AppKit
import Foundation
import SwiftUI
import Testing
import UITestSupport

@MainActor
@Suite("Snapshot artifacts")
struct SnapshotArtifactsTests {
    private func png(_ color: Color, in folder: ScratchFolder, as name: String) throws -> URL {
        let data = SnapshotSupport.pngData(
            of: color.frame(width: 40, height: 20), size: CGSize(width: 80, height: 40), scheme: .light)
        try folder.write(name, "")
        try data.write(to: folder.file(name))
        return folder.file(name)
    }

    @Test("a failed picture gets the reference and the difference next to it")
    func savesTheComparison() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        let reference = try png(.red, in: folder, as: "references/labels.png")
        let failed = try png(.blue, in: folder, as: "failures/labels.png")
        let failedBytes = try Data(contentsOf: failed)

        let saved = try SnapshotArtifacts.saveComparison(reference: reference, failed: failed)

        #expect(saved.map(\.lastPathComponent).sorted() == ["labels-difference.png", "labels-reference.png"])
        for url in saved {
            #expect(url.deletingLastPathComponent().lastPathComponent == "failures")
            let image = try #require(NSImage(contentsOf: url), "\(url.lastPathComponent) is not a picture")
            #expect(image.representations.first?.pixelsWide == 160)
            #expect(image.representations.first?.pixelsHigh == 80)
        }
        // The picture that failed is left as it was.
        #expect(try Data(contentsOf: failed) == failedBytes)
    }

    @Test("the reference of a picture that is missing is not an error, and saves nothing")
    func missingReferenceSavesNothing() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        let failed = try png(.blue, in: folder, as: "failures/labels.png")

        let saved = try SnapshotArtifacts.saveComparison(reference: folder.file("references/none.png"), failed: failed)

        #expect(saved.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.file("failures/labels-difference.png").path))
    }
}
