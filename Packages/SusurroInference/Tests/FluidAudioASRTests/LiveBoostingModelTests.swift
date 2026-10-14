import FluidAudio
import Foundation
import Testing

@testable import FluidAudioASR

/// The parts of the live CTC model that need no model. The rest is covered by `RealModelTests`.
@Suite("Live boosting model")
struct LiveBoostingModelTests {
    private static func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "susurro-ctc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("the model is pinned to a full commit, not a branch name")
    func revisionIsACommit() {
        let revision = LiveBoostingModel.revision

        #expect(revision.count == 40)
        #expect(revision.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("pinning sends the download to Hugging Face at the pinned commit, and leaves the speech model's pin alone")
    func pinning() {
        LiveParakeetEngine.pinWeights()
        LiveBoostingModel.pin()

        #expect(ModelRegistry.baseURL == "https://huggingface.co")
        #expect(ModelRegistry.revisionOverrides[LiveBoostingModel.repository] == LiveBoostingModel.revision)
        #expect(
            ModelRegistry.revisionOverrides[LiveParakeetEngine.weightsRepository] == LiveParakeetEngine.weightsRevision
        )
    }

    @Test("the model lives in a folder of the app, named as FluidAudio names its own")
    func folder() {
        let root = URL(filePath: "/tmp/susurro-models", directoryHint: .isDirectory)

        let folder = LiveBoostingModel.directory(in: root)

        #expect(folder.deletingLastPathComponent().path == root.path)
        #expect(folder.lastPathComponent == CtcModels.defaultCacheDirectory(for: .ctc110m).lastPathComponent)
        #expect(LiveBoostingModel.repository == Repo.parakeetCtc110m.remotePath)
    }

    @Test("a folder that holds another commit, or none, is not the pinned model")
    func staleFolders() throws {
        let folder = try Self.scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appending(path: ".fluidaudio-revision")

        #expect(!LiveBoostingModel.holdsPinnedRevision(at: folder))
        try "0000000000000000000000000000000000000000\n".write(to: marker, atomically: true, encoding: .utf8)
        #expect(!LiveBoostingModel.holdsPinnedRevision(at: folder))
        try (LiveBoostingModel.revision + "\n").write(to: marker, atomically: true, encoding: .utf8)
        #expect(LiveBoostingModel.holdsPinnedRevision(at: folder))
    }

    @Test("a folder of another commit is emptied before the download, and one of the pinned commit is kept")
    func clearingStaleFolders() throws {
        let stale = try Self.scratchFolder()
        let current = try Self.scratchFolder()
        defer {
            try? FileManager.default.removeItem(at: stale)
            try? FileManager.default.removeItem(at: current)
        }
        try "old".write(to: stale.appending(path: ".fluidaudio-revision"), atomically: true, encoding: .utf8)
        try "weights".write(to: stale.appending(path: "vocab.json"), atomically: true, encoding: .utf8)
        try LiveBoostingModel.revision.write(
            to: current.appending(path: ".fluidaudio-revision"), atomically: true, encoding: .utf8)
        try "weights".write(to: current.appending(path: "vocab.json"), atomically: true, encoding: .utf8)

        LiveBoostingModel.clearIfNotPinned(stale)
        LiveBoostingModel.clearIfNotPinned(current)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: current.appending(path: "vocab.json").path))
    }
}
