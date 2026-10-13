import Domain
import FluidAudio
import Foundation
import OSLog

/// Runs Parakeet v3 through FluidAudio. FluidAudio downloads the weights on first use and loads them from disk
/// afterward. Both steps are covered by the opt-in `RealModelTests`: a unit test would have to download the model.
actor LiveParakeetEngine: ParakeetEngine {
    /// The Hugging Face repository that holds the Parakeet v3 Core ML weights.
    static let weightsRepository = "FluidInference/parakeet-tdt-0.6b-v3-coreml"

    /// The reviewed commit of that repository (2026-08-19, the head of `main` when it was pinned). FluidAudio itself
    /// follows `main`, a branch whose files can change; pinning a commit means the weights that run on a Mac are the
    /// ones that were tested. Bump it together with the FluidAudio version, after running `RealModelTests`.
    static let weightsRevision = "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"

    private static let logger = Logger(subsystem: "dev.claudiojara.susurro", category: "parakeet")

    nonisolated let minimumSampleCount = ASRConstants.minimumRequiredSamples(forSampleRate: AudioClip.sampleRate)

    /// Where the weights are kept: a folder of this app, named as FluidAudio lays out its own. FluidAudio's shared
    /// folder is not used, because it records which revision it holds, and an app that follows `main` would replace
    /// the pinned files with its own (and the other way round) on every launch.
    nonisolated let modelsDirectory: URL

    private var manager: AsrManager?

    init(
        modelsRoot: URL = URL.applicationSupportDirectory.appending(path: "Susurro/Models", directoryHint: .isDirectory)
    ) {
        modelsDirectory = modelsRoot.appending(
            path: AsrModels.defaultCacheDirectory(for: .v3).lastPathComponent,
            directoryHint: .isDirectory
        )
    }

    /// Points FluidAudio at Hugging Face and at the pinned commit. Setting the host also overrides the registry
    /// variables of the environment, which could send the download somewhere else. FluidAudio reads both settings from
    /// process-wide state, and every call sets the same values.
    static func pinWeights() {
        ModelRegistry.baseURL = "https://huggingface.co"
        ModelRegistry.revisionOverrides[weightsRepository] = weightsRevision
    }

    /// The FluidAudio language for a pinned code such as "es" or "es-CL": lowercased, without region. Nil when
    /// FluidAudio has no such language, and the engine then detects it.
    static func languageHint(for code: String) -> Language? {
        let language = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        return language.flatMap { Language(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
    }

    /// Whether another try would meet the same error. FluidAudio already purges and downloads again when a model does
    /// not compile, and retries each download, so what reaches here as one of these is final. Everything else, such as
    /// a network that is down, a stalled transfer, or a rate limit, may pass.
    static func isPermanent(_ error: any Error) -> Bool {
        switch error {
        case DownloadError.modelNotFound, DownloadError.invalidArtifact: true
        case ASRError.modelCompilationFailed, ASRError.unsupportedPlatform: true
        case AsrModelsError.modelCompilationFailed: true
        default: false
        }
    }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        Self.pinWeights()
        do {
            let models = try await AsrModels.downloadAndLoad(to: modelsDirectory, version: .v3) {
                progress($0.fractionCompleted)
            }
            let manager = AsrManager()
            try await manager.loadModels(models)
            self.manager = manager
        } catch  where Self.isPermanent(error) {
            throw PermanentLoadFailure(reason: error.localizedDescription)
        }
    }

    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        guard let manager else { throw RecognitionError.notReady }
        // Each clip starts from a fresh decoder state, so one dictation never leaks into the next.
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let hint = language.flatMap { Self.languageHint(for: $0) }
        if let language, hint == nil {
            Self.logger.notice("FluidAudio has no language \(language, privacy: .public); detecting it instead")
        }
        return try await manager.transcribe(samples, decoderState: &decoderState, language: hint).text
    }
}
