import Domain
import FluidAudio

/// Runs Parakeet v3 through FluidAudio. FluidAudio downloads the model on first use into its own cache, under
/// `~/Library/Application Support/FluidAudio/Models`, and loads it from there afterward.
///
/// It is covered by the opt-in `RealModelTests`: a unit test would have to download the model.
actor LiveParakeetEngine: ParakeetEngine {
    nonisolated let minimumSampleCount = ASRConstants.minimumRequiredSamples(forSampleRate: AudioClip.sampleRate)

    private var manager: AsrManager?

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3) { progress($0.fractionCompleted) }
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
    }

    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        guard let manager else { throw RecognitionError.notReady }
        // Each clip starts from a fresh decoder state, so one dictation never leaks into the next.
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let hint = language.flatMap { Language(rawValue: $0) }
        return try await manager.transcribe(samples, decoderState: &decoderState, language: hint).text
    }
}
