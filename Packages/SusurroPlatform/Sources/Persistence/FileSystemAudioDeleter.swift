import Domain
import Foundation

/// Deletes stored audio from the disk. A file that is already gone counts as deleted, since the goal is that it is not
/// there; any other failure (a permission, a locked volume) is thrown, so the caller keeps the record and tries again.
public struct FileSystemAudioDeleter: AudioFileDeleting {
    public init() {}

    public func delete(_ url: URL) async throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }
    }
}
