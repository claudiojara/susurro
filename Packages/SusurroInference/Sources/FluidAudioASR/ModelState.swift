import Domain

/// What a speech model is doing. FluidAudio reports no state of its own, so each adapter keeps one of these and maps
/// it to the readiness the pipeline sees.
enum ModelState: Sendable, Equatable {
    /// No load has started in this process. FluidAudio fetches what is missing, so this reads as a load about to begin,
    /// never as a missing model; the app starts the load at launch with `prepare()`.
    case notLoaded
    case loading(progress: Double)
    case ready
    /// The last load failed, for this reason. `retryable` is false when another load cannot help.
    case failed(String, retryable: Bool)

    var readiness: RecognizerReadiness {
        switch self {
        case .notLoaded: .loading(progress: 0)
        case .loading(let progress): .loading(progress: progress)
        case .ready: .ready
        case .failed(let reason, let retryable): .unavailable(reason, retryable: retryable)
        }
    }
}

/// When a failed load may be tried again: the wait doubles with every failure in a row, up to a ceiling, and after
/// the last attempt there are no more. FluidAudio already retries each download a few times inside one load, so these
/// attempts are for failures that last longer than that.
struct LoadRetryPolicy: Sendable, Equatable {
    var firstDelay = Duration.seconds(10)
    var longestDelay = Duration.seconds(300)
    /// Attempts in a row, the first included, before the recognizer stops trying until the app restarts.
    var maxAttempts = 6

    /// How long to wait after the `failures`-th failure in a row, or nil when that was the last attempt.
    func delay(afterFailures failures: Int) -> Duration? {
        guard failures < maxAttempts else { return nil }
        return min(firstDelay * (1 << (failures - 1)), longestDelay)
    }
}

/// Turns the fractions a FluidAudio load reports into progress that only moves forward, in steps worth showing.
/// FluidAudio reports each model file on its own, so the raw fractions fall back to the start of the next stage, and
/// a download alone makes thousands of calls. Nothing short of the load returning counts as complete.
struct LoadProgress: Sendable, Equatable {
    static let ceiling = 0.99
    static let step = 0.01

    private(set) var value = 0.0

    /// Returns the new progress when `fraction` moves it forward by a step, and nil otherwise.
    mutating func observe(_ fraction: Double) -> Double? {
        guard fraction.isFinite else { return nil }
        let next = min(fraction, Self.ceiling)
        guard next >= value + Self.step else { return nil }
        value = next
        return next
    }
}
