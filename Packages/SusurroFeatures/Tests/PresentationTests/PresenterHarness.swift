import CoreTestSupport
import Domain

@testable import Presentation

/// A presenter wired to a sleeper the test controls and to a record of everything it displays. The harness is not on
/// the main actor, so that it can read its record with a mutating async call; the presenter is, and tests await it.
struct PresenterHarness {
    let presenter: SkeletonOverlayPresenter
    let sleeper: FakeSleeper
    let timing = OverlayTiming.standard
    private var changes: AsyncStream<OverlayIndicator?>.Iterator

    init() async {
        let (stream, continuation) = AsyncStream.makeStream(of: OverlayIndicator?.self)
        let sleeper = FakeSleeper()
        self.sleeper = sleeper
        presenter = await MainActor.run {
            SkeletonOverlayPresenter(
                timing: .standard,
                sleep: { try await sleeper.sleep($0) },
                display: { continuation.yield($0) }
            )
        }
        changes = stream.makeAsyncIterator()
    }

    /// The next thing the presenter displays, waiting for it if it has not happened yet. `nil` outer is a finished
    /// stream, which the presenter never produces.
    mutating func nextDisplay() async -> OverlayIndicator?? {
        await changes.next()
    }

    /// Lets every task that is ready run, so that "nothing happened" is a statement about the presenter and not about
    /// scheduling.
    func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    func message(of indicator: OverlayIndicator??) -> String? {
        indicator?.flatMap { $0 }?.message
    }
}
