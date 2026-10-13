import Domain

/// Turns the readiness of the speech model into progress worth showing on screen. A load from the disk cache takes a
/// fraction of a second and would flash an indicator, so progress is reported only once a load has lasted `showAfter`.
/// The first launch, which downloads and compiles the model for about a minute, is what this is for.
@MainActor
public final class ModelLoadWatcher {
    nonisolated static let standardDelay = Duration.milliseconds(1_500)

    private let showAfter: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let report: @MainActor (Double?) -> Void
    private var delay: Task<Void, Never>?
    private var isShown = false
    private var latest = 0.0

    init(
        showAfter: Duration = ModelLoadWatcher.standardDelay,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        report: @escaping @MainActor (Double?) -> Void
    ) {
        self.showAfter = showAfter
        self.sleep = sleep
        self.report = report
    }

    /// Applies each readiness the recognizer reports, until the stream ends.
    public func run(_ readiness: AsyncStream<RecognizerReadiness>) async {
        for await value in readiness { observe(value) }
    }

    func observe(_ readiness: RecognizerReadiness) {
        switch readiness {
        case .loading(let progress):
            latest = progress
            if isShown {
                report(progress)
            } else if delay == nil {
                startDelay()
            }
        case .ready, .notInstalled, .unavailable:
            delay?.cancel()
            delay = nil
            if isShown {
                isShown = false
                report(nil)
            }
        }
    }

    private func startDelay() {
        delay = Task { [showAfter, sleep] in
            do { try await sleep(showAfter) } catch { return }
            guard !Task.isCancelled else { return }
            delay = nil
            isShown = true
            report(latest)
        }
    }
}
