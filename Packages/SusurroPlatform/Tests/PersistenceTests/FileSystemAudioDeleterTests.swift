import Foundation
import Testing

@testable import Persistence

@Suite("File system audio deleter", .timeLimit(.minutes(1)))
struct FileSystemAudioDeleterTests {
    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "susurro-deleter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("it removes the file")
    func removesFile() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "a.caf")
        try Data([1, 2, 3]).write(to: file)

        try await FileSystemAudioDeleter().delete(file)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a file that is already gone counts as deleted")
    func missingFileIsDeleted() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await FileSystemAudioDeleter().delete(directory.appending(path: "missing.caf"))
    }

    @Test("a file that cannot be removed is an error, so the caller tries again")
    func failureIsThrown() async throws {
        let directory = try Self.makeDirectory()
        let file = directory.appending(path: "locked.caf")
        try Data([1]).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        await #expect(throws: (any Error).self) { try await FileSystemAudioDeleter().delete(file) }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
