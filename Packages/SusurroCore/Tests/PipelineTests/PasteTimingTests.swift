import Testing

@testable import Pipeline

@Suite("Paste timing")
struct PasteTimingTests {
    @Test("the budget of an insertion covers the wait for an earlier paste, the modifier wait, and the wait for a read")
    func insertBudget() {
        #expect(PasteTiming.insertBudget == .milliseconds(9_550))
    }

    @Test(
        "a queued insertion waits for the minimum dwell of the paste before it, and one poll more for its task to end")
    func overlapWaitCoversTheDwell() {
        #expect(PasteTiming.overlapWait == PasteTiming.minimumDwell + PasteTiming.receiptPollInterval)
    }

    @Test("the whole budget ends before the coordinator gives up on the insertion")
    func fitsTheInsertionDeadline() {
        #expect(PasteTiming.insertBudget < DictationLimits.insertionTimeout)
    }

    @Test("the minimum dwell overlaps the wait for a read, so it adds nothing to the budget")
    func dwellOverlapsTheReceiptWait() {
        #expect(PasteTiming.minimumDwell < PasteTiming.receiptTimeout)
    }
}
