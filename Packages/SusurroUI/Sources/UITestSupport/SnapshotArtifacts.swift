import AppKit
import Foundation
import SnapshotTesting

/// What a failed snapshot leaves for a person to look at. The library writes the picture that failed to
/// `$SNAPSHOT_ARTIFACTS` and nothing else outside Xcode, so the reference and the difference are written beside it, and
/// the workflow uploads the folder.
public enum SnapshotArtifacts {
    /// Where the library puts the pictures that failed: `$SNAPSHOT_ARTIFACTS`, or the temporary folder.
    public static var folder: URL {
        URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] ?? NSTemporaryDirectory(),
            isDirectory: true)
    }

    /// Writes `<name>-reference.png` and `<name>-difference.png` next to the `failed` picture, and returns them. It
    /// writes nothing when either picture is missing or the two match within the tolerance of a snapshot.
    @discardableResult
    public static func saveComparison(reference: URL, failed: URL) throws -> [URL] {
        guard let referenceData = try? Data(contentsOf: reference), let failedData = try? Data(contentsOf: failed),
            let old = NSImage(data: referenceData), let new = NSImage(data: failedData)
        else { return [] }
        let diffing = Diffing<NSImage>.image(
            precision: SnapshotSupport.precision, perceptualPrecision: SnapshotSupport.perceptualPrecision)
        guard let (_, attachments) = diffing.diffV2(old, new) else { return [] }
        let stem = failed.deletingPathExtension().lastPathComponent
        var saved: [URL] = []
        for case .data(let data, let name) in attachments where name != "failure.png" {
            let url = failed.deletingLastPathComponent().appendingPathComponent("\(stem)-\(name)")
            try data.write(to: url)
            saved.append(url)
        }
        return saved
    }
}
