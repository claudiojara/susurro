import Testing

@testable import Pipeline

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

}
