import Foundation
import Testing

/// A folder in the temporary directory, standing in for `Application Support/Susurro/Themes`, with helpers to put theme
/// files and odd kinds of entries in it. It is created at once unless `create` is false.
struct ScratchFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("scratch-\(UUID().uuidString)")

    init(create: Bool = true) throws {
        if create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    /// Creates the folder first if it is not there, as the app does when it saves its first theme, and the folders
    /// above the file.
    func write(_ name: String, _ text: String) throws {
        try FileManager.default.createDirectory(
            at: file(name).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file(name))
    }

    func writeTheme(_ id: String, spacingMD: Int) throws {
        try write("\(id).json", #"{"schemaVersion": 1, "spacing": {"md": \#(spacingMD)}}"#)
    }

    func remove(_ name: String) throws {
        try FileManager.default.removeItem(at: file(name))
    }

    func makeFIFO(_ name: String) throws {
        try #require(mkfifo(file(name).path, 0o600) == 0, "mkfifo failed: errno \(errno)")
    }

    func makeFolder(_ name: String) throws {
        try FileManager.default.createDirectory(at: file(name), withIntermediateDirectories: false)
    }

    func makeSymlink(_ name: String, to target: URL) throws {
        try FileManager.default.createSymbolicLink(at: file(name), withDestinationURL: target)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// `{"schemaVersion": 1}` followed by spaces up to `size` bytes, so it is valid and exactly that big.
func themeText(ofSize size: Int) -> String {
    let base = #"{"schemaVersion": 1}"#
    return base + String(repeating: " ", count: size - base.utf8.count)
}
