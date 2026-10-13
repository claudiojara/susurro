import Pipeline
import Testing

@testable import TextInsertion

@Suite("Paste timing")
struct PasteTimingTests {
    @Test("the worst case of an insertion is the modifier wait and the wait for a read")
    func worstCase() {
        #expect(PasteTiming.worstCase == .milliseconds(8_500))
    }

    @Test("a queued insertion waits for the minimum dwell of the paste before it, which is all that is left of it")
    func overlapWaitCoversTheDwell() {
        #expect(PasteTiming.overlapWait >= PasteTiming.minimumDwell)
    }

    @Test("a queued insertion and its own worst case end before the coordinator gives up on the insertion")
    func fitsTheInsertionDeadline() {
        #expect(PasteTiming.overlapWait + PasteTiming.worstCase <= DictationLimits.insertionTimeout)
    }

    @Test("the minimum dwell overlaps the wait for a read, so it adds nothing to the worst case")
    func dwellOverlapsTheReceiptWait() {
        #expect(PasteTiming.minimumDwell < PasteTiming.receiptTimeout)
    }
}
