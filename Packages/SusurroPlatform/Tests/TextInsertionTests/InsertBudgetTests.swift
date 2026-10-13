import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@Suite("Insert budget")
struct InsertBudgetTests {
    @Test("a wait ends at its own limit while the budget has room")
    func ownLimit() {
        let budget = InsertBudget(startingAt: .seconds(10), length: .seconds(9))

        #expect(budget.deadline(for: .milliseconds(500), from: .seconds(12)) == .milliseconds(12_500))
        #expect(budget.deadline(for: .seconds(1), from: .seconds(10)) == .seconds(11))
    }

    @Test("a wait never ends after the budget does")
    func budgetEnd() {
        let budget = InsertBudget(startingAt: .seconds(10), length: .seconds(9))

        #expect(budget.deadline(for: .seconds(8), from: .seconds(15)) == .seconds(19))
        #expect(budget.deadline(for: .seconds(8), from: .seconds(25)) == .seconds(19))
    }

    @Test("what is left of the budget is never negative")
    func remaining() {
        let budget = InsertBudget(startingAt: .seconds(10), length: .seconds(9))

        #expect(budget.remaining(at: .seconds(12)) == .seconds(7))
        #expect(budget.remaining(at: .seconds(19)) == .zero)
        #expect(budget.remaining(at: .seconds(30)) == .zero)
    }

    @MainActor
    @Suite("Insert budget in an insertion", .timeLimit(.minutes(1)))
    struct InAnInsertion: PasteTestCase {
        let fixture = PasteFixture()

        @Test("a modifier wait that overshoots leaves the wait for a read only what is left of the budget")
        func overshootShortensTheReceiptWait() async {
            putRichContent()
            let keys = FakeKeystrokePoster(modifiersHeldFor: 1)
            var pauses = 0
            onSleep = { [clock] _ in
                pauses += 1
                // The first pause takes 3 s instead of 20 ms, as when the main thread is busy.
                if pauses == 1 { clock.advance(by: .seconds(3)) }
            }

            let outcome = await makeInserter(keys).insert("hello world")

            #expect(outcome == .copiedToClipboard(.pasteFailed))
            #expect(keys.postCount == 1)
            #expect(clock.elapsed <= Self.insertBudget + Self.receiptPollInterval)
            #expect(clock.elapsed >= Self.insertBudget)
        }

        @Test("without an overshoot the wait for a read keeps its full 8 s")
        func noOvershootKeepsTheFullWait() async {
            putRichContent()
            let keys = FakeKeystrokePoster()

            let outcome = await makeInserter(keys).insert("hello world")

            #expect(outcome == .copiedToClipboard(.pasteFailed))
            #expect(clock.elapsed >= Self.receiptTimeout)
            #expect(clock.elapsed <= Self.receiptTimeout + Self.receiptPollInterval)
        }
    }
}
