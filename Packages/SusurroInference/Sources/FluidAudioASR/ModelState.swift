import Domain

/// What a speech model is doing. FluidAudio reports no state of its own, so each adapter keeps one of these and maps
/// it to the readiness the pipeline sees.
enum ModelState: Sendable, Equatable {
    /// No load has started in this process.
    case notLoaded
    case loading(progress: Double)
    case ready
    /// The last load failed. Another load may be started.
    case failed

    /// A model that failed to load is as unusable as one that was never installed.
    var readiness: RecognizerReadiness {
        switch self {
        case .notLoaded, .failed: .notInstalled
        case .loading(let progress): .loading(progress: progress)
        case .ready: .ready
        }
    }
}

/// Turns the fractions a FluidAudio load reports into progress that only moves forward. FluidAudio reports each model
/// file on its own, so the raw fractions fall back to the start of the next stage. Nothing short of the load returning
/// counts as complete.
struct LoadProgress: Sendable, Equatable {
    static let ceiling = 0.99

    private(set) var value = 0.0

    /// Returns the new progress when `fraction` moves it forward, and nil otherwise.
    mutating func observe(_ fraction: Double) -> Double? {
        guard fraction.isFinite else { return nil }
        let next = min(fraction, Self.ceiling)
        guard next > value else { return nil }
        value = next
        return next
    }
}
