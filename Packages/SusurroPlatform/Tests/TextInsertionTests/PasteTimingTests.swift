import Pipeline
import Testing

@testable import TextInsertion

@Suite("Paste timing")
struct PasteTimingTests {
    @Test("the worst case is the modifier wait, the wait for a read, and one last quiet period")
    func worstCase() {
        #expect(PasteTiming.worstCase == .milliseconds(8_700))
    }

    @Test("the worst case ends at least a second before the coordinator gives up on the insertion")
    func fitsTheInsertionDeadline() {
        #expect(PasteTiming.worstCase + .seconds(1) <= DictationLimits.insertionTimeout)
    }

    @Test("the minimum dwell overlaps the wait for a read, so it adds nothing to the worst case")
    func dwellOverlapsTheReceiptWait() {
        #expect(PasteTiming.minimumDwell < PasteTiming.receiptTimeout)
    }
}
