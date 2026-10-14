import CoreTestSupport
import Domain
import Testing

@MainActor
@Suite("Paste budget", .timeLimit(.minutes(1)))
struct PasteBudgetTests {
    // The whole of an insertion: the wait for an earlier paste, the modifier wait, and the wait for a read.
    private static let insertBudget = Duration.milliseconds(9_550)

    @Test("a modifier wait that overshoots leaves the wait for a read only what is left of the budget")
    func overshootShortensTheReceiptWait() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(modifiersHeldFor: 1))
        var pauses = 0
        h.onSleep { [clock = h.clock] _ in
            pauses += 1
            // The first pause takes 3 s instead of 20 ms, as when the main thread is busy.
            if pauses == 1 { clock.advance(by: .seconds(3)) }
        }

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.keys.postCount == 1)
        #expect(h.clock.elapsed <= Self.insertBudget + PasteHarness.receiptPollInterval)
        #expect(h.clock.elapsed >= Self.insertBudget)
    }

    @Test("without an overshoot the wait for a read keeps its full 8 s")
    func noOvershootKeepsTheFullWait() async {
        let h = PasteHarness()

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.clock.elapsed >= PasteHarness.receiptTimeout)
        #expect(h.clock.elapsed <= PasteHarness.receiptTimeout + PasteHarness.receiptPollInterval)
    }
}
