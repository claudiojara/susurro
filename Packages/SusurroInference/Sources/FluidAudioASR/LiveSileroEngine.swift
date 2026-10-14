import FluidAudio
import Foundation

/// Runs Silero through FluidAudio. It loads the model on first use and keeps it. Covered by the manual check (run it on a
/// recorded file and look at the segments), since a unit test would have to download the model.
actor LiveSileroEngine: SileroEngine {
    /// The Hugging Face repository that holds the Silero VAD Core ML model.
    static let weightsRepository = "FluidInference/silero-vad-coreml"

    /// The reviewed commit of that repository (2026-10-14, the head of `main` when it was pinned; it holds the 6.2.1
    /// model FluidAudio 0.17.7 loads). Pinning it means that the model that runs on a Mac is the one that was tested.
    static let weightsRevision = "b419383c55c110e2c9271fa6ee0ea83d03c70d96"

    /// A quiet voice must not be lost, because a recording judged to hold no speech is not transcribed: the threshold is
    /// Silero's own default (0.5), below the 0.85 of FluidAudio, and a false alarm costs only a blank transcript.
    static let speechThreshold: Float = 0.5

    /// Only the first and the last segment matter to the pipeline, which keeps everything between them. The padding is
    /// left to the pre-roll and hangover of `SpeechSpan`, and a speech stretch is never split at a maximum length.
    static let segmentation = VadSegmentationConfig(
        minSpeechDuration: 0.15, minSilenceDuration: 0.75, maxSpeechDuration: 3_600, speechPadding: 0)

    /// Where the models live: `Models` in this folder, next to the speech model.
    nonisolated let folder: URL

    private var manager: VadManager?

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "Susurro", directoryHint: .isDirectory)) {
        self.folder = folder
    }

    func speechSegments(in samples: [Float]) async throws -> [SileroSegment] {
        let manager = try await loadedManager()
        let segments = try await manager.segmentSpeech(samples, config: Self.segmentation)
        return segments.map { SileroSegment(start: $0.startTime, end: $0.endTime) }
    }

    private func loadedManager() async throws -> VadManager {
        if let manager { return manager }
        ModelPinning.pin(repository: Self.weightsRepository, to: Self.weightsRevision)
        let loaded = try await VadManager(
            config: VadConfig(defaultThreshold: Self.speechThreshold), modelDirectory: folder)
        manager = loaded
        return loaded
    }
}
