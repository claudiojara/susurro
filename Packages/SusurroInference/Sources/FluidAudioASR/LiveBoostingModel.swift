import FluidAudio
import Foundation
import OSLog

/// The CTC model behind `VocabularyBooster`, through FluidAudio: Parakeet CTC 110M, which listens to the clip again and
/// scores how well each dictionary term fits the sounds. Parakeet v3 has no CTC head of its own, so this is a second,
/// smaller model (about 97 MB on disk, about 130 MB of memory once loaded). It is covered by the opt-in
/// `RealModelTests`: a unit test would have to download it.
///
/// FluidAudio's `VocabularyBoostingSession` is not used, because its initializer reads the tokenizer from FluidAudio's
/// shared folder. The pieces it is made of are public, so the session here builds them over this app's own folder.
struct LiveBoostingModel: BoostingModel {
    /// The Hugging Face repository that holds the CTC model.
    static let repository = "FluidInference/parakeet-ctc-110m-coreml"

    /// The reviewed commit of that repository (2026-10-14, the head of `main` when it was pinned; its files are the
    /// ones from 2026-03-28). It holds `MelSpectrogram.mlmodelc`, `AudioEncoder.mlmodelc`, `vocab.json` and
    /// `tokenizer.json`, which is all FluidAudio reads. Bump it together with the FluidAudio version, after running
    /// `RealModelTests`.
    static let revision = "accdafd8cf8a2ff1cabe3c11e54416b405d409aa"

    private static let logger = Logger(subsystem: "dev.claudiojara.susurro", category: "parakeet-boost")
    private static let revisionMarker = ".fluidaudio-revision"

    private let models: CtcModels
    private let tokenizer: CtcTokenizer
    private let directory: URL

    /// Points FluidAudio at Hugging Face and at the pinned commit of the CTC repository.
    static func pin() {
        ModelPinning.pin(repository: repository, to: revision)
    }

    /// Where the model is kept: a folder of this app next to the speech model's, named as FluidAudio names its own.
    static func directory(in modelsRoot: URL) -> URL {
        modelsRoot.appending(path: Repo.parakeetCtc110m.folderName, directoryHint: .isDirectory)
    }

    /// Whether the folder holds the pinned commit. FluidAudio writes the commit it downloaded in a marker file; its
    /// check for a model that is already on disk looks only for the files, so a folder of an older pin would be kept.
    static func holdsPinnedRevision(at folder: URL) -> Bool {
        let stored = try? String(contentsOf: folder.appending(path: revisionMarker), encoding: .utf8)
        return stored?.trimmingCharacters(in: .whitespacesAndNewlines) == revision
    }

    /// Empties a folder that does not hold the pinned commit, so the next download fills it with the right files.
    static func clearIfNotPinned(_ folder: URL) {
        guard !holdsPinnedRevision(at: folder) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Downloads the model if it is not on disk, then loads it. Throws when the download or the load fails.
    static func load(modelsRoot: URL) async throws -> LiveBoostingModel {
        pin()
        let folder = directory(in: modelsRoot)
        clearIfNotPinned(folder)
        try await CtcModels.download(to: folder, variant: .ctc110m)
        let models = try await CtcModels.load(from: folder, variant: .ctc110m)
        let tokenizer = try await CtcTokenizer.load(from: folder)
        return LiveBoostingModel(models: models, tokenizer: tokenizer, directory: folder)
    }

    func session(for terms: [String]) async throws -> any BoostingSession {
        let vocabulary = CustomVocabularyContext(
            terms: terms.compactMap { text in
                let ids = tokenizer.encode(text)
                return ids.isEmpty ? nil : CustomVocabularyTerm(text: text, ctcTokenIds: ids)
            })
        let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter, vocabulary: vocabulary, config: .default, ctcModelDirectory: directory)
        return LiveBoostingSession(
            spotter: spotter, rescorer: rescorer, vocabulary: vocabulary,
            sizing: ContextBiasingConstants.rescorerConfig(forVocabSize: vocabulary.terms.count))
    }
}

/// The rescoring step of FluidAudio's `VocabularyBoostingSession`, over the CTC model of this app's folder: the spotter
/// scores every term against the audio, and the rescorer replaces a word of the transcript by a term only when the audio
/// fits the term better and the two look alike.
private struct LiveBoostingSession: BoostingSession {
    let spotter: CtcKeywordSpotter
    let rescorer: VocabularyRescorer
    let vocabulary: CustomVocabularyContext
    let sizing: ContextBiasingConstants.VocabSizeConfig

    private static let logger = Logger(subsystem: "dev.claudiojara.susurro", category: "parakeet-boost")

    func rescore(_ text: String, timings: [TokenTiming], samples: [Float]) async -> String? {
        guard !vocabulary.terms.isEmpty else { return nil }
        do {
            let spotted = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: vocabulary, minScore: nil)
            guard !spotted.logProbs.isEmpty else { return nil }
            let output = rescorer.ctcTokenRescore(
                transcript: text, tokenTimings: timings, logProbs: spotted.logProbs,
                frameDuration: spotted.frameDuration, cbw: sizing.cbw, marginSeconds: 0.5,
                minSimilarity: max(sizing.minSimilarity, vocabulary.minSimilarity))
            return output.wasModified ? output.text : nil
        } catch {
            // Boosting never breaks a transcription: the text stays as Parakeet wrote it.
            Self.logger.error(
                "The dictionary terms were not scored: \(String(reflecting: type(of: error)), privacy: .public)")
            return nil
        }
    }
}
