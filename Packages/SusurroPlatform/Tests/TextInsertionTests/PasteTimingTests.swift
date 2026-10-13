import Pipeline
import Testing

@testable import TextInsertion

@Suite("Paste timing")
struct PasteTimingTests {
    @Test("a paste that waits at every step still ends before the coordinator gives up on the insertion")
    func fitsTheInsertionDeadline() {
        let worstCase = PasteTiming.modifierTimeout + PasteTiming.receiptTimeout + PasteTiming.restoreDelay

        #expect(worstCase < DictationLimits.insertionTimeout)
    }
}
