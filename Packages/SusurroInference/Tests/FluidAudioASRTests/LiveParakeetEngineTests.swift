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

    @Test("the encoder is the int8 re-quantization, not the palettized one that corrupts words")
    func encoderPrecision() {
        // Triangulation skipped: two constants with one possible value each.
        #expect(LiveParakeetEngine.encoderPrecision == .int8V2)
        #expect(LiveParakeetEngine.encoderPrecision.encoderFileName == "Encoder_v2.mlmodelc")
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

    @Test(
        "errors that trying again cannot fix are permanent",
        arguments: [
            DownloadError.modelNotFound(path: "Encoder_v2.mlmodelc"),
            .invalidArtifact(path: "Encoder_v2.mlmodelc", reason: "checksum"),
        ] as [any Error]
            + [ASRError.modelCompilationFailed, ASRError.unsupportedPlatform("needs a newer macOS")] as [any Error]
            + [AsrModelsError.modelCompilationFailed("Encoder")] as [any Error]
    )
    func permanentErrors(error: any Error) {
        #expect(LiveParakeetEngine.isPermanent(error))
    }

    @Test(
        "network and server errors are worth another try",
        arguments: [
            DownloadError.stalled(path: "Encoder_v2.mlmodelc", window: 120),
            .rateLimited(statusCode: 429, message: "slow down"),
            .invalidResponse,
        ] as [any Error]
            + [URLError(.notConnectedToInternet), AsrModelsError.downloadFailed("timeout")] as [any Error]
    )
    func transientErrors(error: any Error) {
        #expect(!LiveParakeetEngine.isPermanent(error))
    }

    @Test("a permanent error reaches the recognizer as one, with FluidAudio's description as the reason")
    func permanentErrorIsMarked() {
        let failure = LiveParakeetEngine.loadFailure(AsrModelsError.modelCompilationFailed("Encoder"))

        #expect(
            failure as? PermanentLoadFailure
                == PermanentLoadFailure(reason: AsrModelsError.modelCompilationFailed("Encoder").localizedDescription)
        )
    }

    @Test("a transient error reaches the recognizer unchanged")
    func transientErrorIsPassedOn() {
        let failure = LiveParakeetEngine.loadFailure(URLError(.notConnectedToInternet))

        #expect((failure as? URLError)?.code == .notConnectedToInternet)
    }
}
