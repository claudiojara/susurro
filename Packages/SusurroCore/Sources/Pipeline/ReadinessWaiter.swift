import Domain

/// Waits for a speech model that is still loading, while the finished recording is safe on disk. The wait ends when the
/// model is ready, when it fails, when its progress has not changed for `readinessStallTimeout`, or at
/// `readinessHardCap`. It reports the progress it sees, so the overlay can show it.
///
/// The count is of polls, paced by `sleep`, so a test that fakes the sleep and drives the readiness of the recognizer
/// sees the same budget a real wait has.
struct ReadinessWaiter: Sendable {
    let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameter report: Called with the progress of the load each time a poll finds the model loading, and with nil
    ///   once it is ready.
    /// - Throws: `recognizerNotInstalled`, `recognizerUnavailable`, or `timedOut(.readiness)`; `CancellationError` when
    ///   the caller was cancelled.
    func wait(
        for recognizer: any SpeechRecognizer, report: @Sendable (Double?) async -> Void
    ) async throws {
        let stallLimit = Int(DictationLimits.readinessStallTimeout / DictationLimits.readinessPollInterval)
        let totalLimit = Int(DictationLimits.readinessHardCap / DictationLimits.readinessPollInterval)
        var stalledPolls = 0
        var totalPolls = 0
        var lastProgress: Double?
        while true {
            let readiness = await recognizer.readiness()
            // Work that the total cap abandoned must not report once it is cancelled.
            try Task.checkCancellation()
            switch readiness {
            case .ready:
                await report(nil)
                return
            case .notInstalled:
                throw PipelineError.recognizerNotInstalled
            case .unavailable(let reason, let retryable):
                throw PipelineError.recognizerUnavailable(reason, retryable: retryable)
            case .loading(let progress):
                if progress != lastProgress {
                    lastProgress = progress
                    stalledPolls = 0
                }
                guard stalledPolls < stallLimit, totalPolls < totalLimit else {
                    throw PipelineError.timedOut(.readiness)
                }
                stalledPolls += 1
                totalPolls += 1
                await report(progress)
                try await sleep(DictationLimits.readinessPollInterval)
            }
        }
    }
}
