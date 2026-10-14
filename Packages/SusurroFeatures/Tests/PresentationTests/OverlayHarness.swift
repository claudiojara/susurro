import CoreTestSupport
import Domain
import SusurroUI

@testable import Presentation

/// A view model wired to a sleeper the test controls and to a record of everything it displays. The harness is not on
/// the main actor, so that it can read its record with a mutating async call; the view model is, and tests await it.
struct OverlayHarness {
    let model: OverlayViewModel
    let sleeper: FakeSleeper
    let timing = OverlayTiming.standard
    private var changes: AsyncStream<OverlayViewState>.Iterator

    init(uptime: @escaping @Sendable () -> Duration = { .zero }) async {
        let (stream, continuation) = AsyncStream.makeStream(of: OverlayViewState.self)
        let sleeper = FakeSleeper()
        self.sleeper = sleeper
        model = await MainActor.run {
            let model = OverlayViewModel(timing: .standard, sleep: { try await sleeper.sleep($0) }, uptime: uptime)
            model.display = { continuation.yield($0) }
            return model
        }
        changes = stream.makeAsyncIterator()
    }

    /// The next thing the view model displays, waiting for it if it has not happened yet. `.hidden` is the overlay going
    /// away. Nil is a finished stream, which the view model never produces.
    mutating func nextDisplay() async -> OverlayViewState? {
        await changes.next()
    }

    /// Lets every task that is ready run, so that "nothing happened" is a statement about the view model and not about
    /// scheduling.
    func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    func message(of state: OverlayViewState?) -> String? {
        state?.text
    }
}
