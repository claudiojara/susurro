import FluidAudio
import Foundation
import Testing

@testable import FluidAudioASR

/// The parts of the live engine that need no model. The rest is covered by `RealModelTests`.
@Suite("Live Parakeet engine")
struct LiveParakeetEngineTests {
    @Test("the engine's minimum is the 300 ms that FluidAudio rejects clips below")
    func minimumSampleCount() {
        // Triangulation skipped: one constant, which the fake in the other suites repeats on purpose.
        #expect(LiveParakeetEngine().minimumSampleCount == 4_800)
    }

    @Test(
        "a pinned language is lowercased and loses its region before it reaches FluidAudio",
        arguments: [
            ("es", Language.spanish), ("ES", .spanish), ("es-CL", .spanish), ("es_MX", .spanish),
            ("pt-BR", .portuguese), (" en ", .english),
        ]
    )
    func languageHint(code: String, expected: Language) {
        #expect(LiveParakeetEngine.languageHint(for: code) == expected)
    }

    @Test("a language FluidAudio does not know gives no hint", arguments: ["xx", "tlh-Latn", "", "-"])
    func unsupportedLanguageHint(code: String) {
        #expect(LiveParakeetEngine.languageHint(for: code) == nil)
    }

    @Test("the weights are pinned to a full commit, not a branch name")
    func weightsRevisionIsACommit() {
        let revision = LiveParakeetEngine.weightsRevision

        #expect(revision.count == 40)
        #expect(revision.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("pinning sends the download to Hugging Face at the pinned commit")
    func pinWeights() {
        LiveParakeetEngine.pinWeights()

        #expect(ModelRegistry.baseURL == "https://huggingface.co")
        #expect(
            ModelRegistry.revisionOverrides[LiveParakeetEngine.weightsRepository] == LiveParakeetEngine.weightsRevision
        )
    }

    @Test("the models live in a folder of the app, laid out as FluidAudio expects")
    func modelsDirectory() {
        let target = LiveParakeetEngine().modelsDirectory
        let theirs = AsrModels.defaultCacheDirectory(for: .v3)

        #expect(target.lastPathComponent == theirs.lastPathComponent)
        #expect(target.deletingLastPathComponent() != theirs.deletingLastPathComponent())
        #expect(target.path.contains("/Susurro/Models/"))
    }
}
