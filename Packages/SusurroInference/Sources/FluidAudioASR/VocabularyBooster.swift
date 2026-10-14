import Domain
import FluidAudio
import Foundation
import OSLog

/// A CTC model that is loaded and can build the rescoring session for a list of terms. The live one wraps FluidAudio;
/// tests substitute a fake, so no unit test downloads a model or runs one.
protocol BoostingModel: Sendable {
    /// Prepares the rescoring of a transcript against `terms`. Throws when the terms cannot be set up.
    func session(for terms: [String]) async throws -> any BoostingSession
}

/// The rescoring of transcripts against one list of terms.
protocol BoostingSession: Sendable {
    /// The transcript with the terms written over the words that sound like them, or nil when nothing changed or the
    /// rescoring could not run. `timings` and `samples` are on the same clock: time zero is the first sample.
    func rescore(_ text: String, timings: [TokenTiming], samples: [Float]) async -> String?
}

/// Rescores the transcript that Parakeet wrote against the user's dictionary terms, with a separate CTC model that
/// listens to the same audio (FluidAudio's CTC keyword spotting). It never gets in the way of a dictation: it returns
/// the transcript it was given unchanged when there is nothing to do, while the model loads or after a failure, and it
/// never throws.
///
/// The model (about 97 MB) is downloaded and loaded on the first dictation that has terms to boost, in the background:
/// that dictation and the ones before the model is ready are not boosted. A user without a dictionary never pays for it.
actor VocabularyBooster {
    /// The shortest term that is boosted. A shorter one collides with common words, and the rescoring then writes it over
    /// a different word that sounds like it.
    static let minimumTermLength = 5
    /// The longest clip that is rescored. The CTC model reads 15 s windows, about 0.4 s each on an M1 Max, so this bounds
    /// the time it adds to about 4 s; that time comes out of the transcription timeout, which a clip must not lose to it.
    static let maximumSamples = 120 * AudioClip.sampleRate

    private enum Readiness {
        case notLoaded
        case loading(Task<Void, Never>)
        case ready(any BoostingModel)
        case failed(at: ContinuousClock.Instant)
    }

    private static let logger = Logger(subsystem: "dev.claudiojara.susurro", category: "parakeet-boost")

    private let load: @Sendable () async throws -> any BoostingModel
    private let retryDelay: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private var readiness = Readiness.notLoaded
    private var cached: (key: [String], session: any BoostingSession)?

    /// - Parameters:
    ///   - load: Downloads the model if it is not on disk, then loads it.
    ///   - retryDelay: How long after a failed load the next dictation with terms tries again.
    init(
        load: @escaping @Sendable () async throws -> any BoostingModel,
        retryDelay: Duration = .seconds(300),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.load = load
        self.retryDelay = retryDelay
        self.now = now
    }

    /// Starts loading the model when it is not loaded, and returns once the load has ended, well or not. A dictation
    /// does not call it, because it never waits for the model.
    func prepare() async {
        startLoadingIfDue()
        if case .loading(let task) = readiness { await task.value }
    }

    /// `text` with the dictionary terms written over what the audio says they replace, or `text` itself.
    ///
    /// - Parameters:
    ///   - timings: The token timings of `text`, on the clock of `samples`. Nil or empty leaves the text alone.
    ///   - terms: The dictionary. The terms below `minimumTermLength` characters are dropped.
    func boost(_ text: String, timings: [TokenTiming]?, samples: [Float], terms: [String]) async -> String {
        let usable = Self.usable(terms)
        guard !usable.isEmpty, let timings, !timings.isEmpty, !samples.isEmpty,
            samples.count <= Self.maximumSamples
        else { return text }
        startLoadingIfDue()
        guard case .ready(let model) = readiness else { return text }
        do {
            let session = try await session(for: usable, from: model)
            return await session.rescore(text, timings: timings, samples: samples) ?? text
        } catch {
            Self.logger.error(
                "The dictionary terms were not set up: \(String(reflecting: type(of: error)), privacy: .public)")
            return text
        }
    }

    // MARK: Terms

    /// The terms worth boosting: trimmed, long enough, and without repeats (case aside), in the order they came.
    static func usable(_ terms: [String]) -> [String] {
        var seen: Set<String> = []
        return terms.compactMap { term in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= minimumTermLength, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }

    // MARK: Sessions

    /// The session for `terms`, kept for the next dictation when its terms are the same ones, in any order.
    private func session(for terms: [String], from model: any BoostingModel) async throws -> any BoostingSession {
        let key = terms.map { $0.lowercased() }.sorted()
        if let cached, cached.key == key { return cached.session }
        let session = try await model.session(for: terms)
        cached = (key, session)
        return session
    }

    // MARK: Loading

    private func startLoadingIfDue() {
        switch readiness {
        case .loading, .ready: return
        case .failed(let failedAt): guard now() >= failedAt + retryDelay else { return }
        case .notLoaded: break
        }
        readiness = .loading(
            Task {
                do {
                    finishLoading(with: .success(try await load()))
                } catch {
                    finishLoading(with: .failure(error))
                }
            })
    }

    private func finishLoading(with result: Result<any BoostingModel, any Error>) {
        switch result {
        case .success(let model):
            readiness = .ready(model)
            Self.logger.notice("The model that boosts the dictionary terms is ready")
        case .failure(let error):
            readiness = .failed(at: now())
            // Only the error's type is public; its description can name paths and hosts.
            Self.logger.error(
                "The model that boosts the dictionary terms did not load: \(String(reflecting: type(of: error)), privacy: .public)"
            )
        }
    }
}
