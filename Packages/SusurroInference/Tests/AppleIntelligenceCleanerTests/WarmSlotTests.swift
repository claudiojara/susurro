import Testing

@testable import AppleIntelligenceCleaner

@Suite("Warm slot")
struct WarmSlotTests {
    @Test("a stored session is given back once, for the same instructions")
    func givenBackOnce() {
        let slot = WarmSlot<Int>()
        slot.store(7, instructions: "clean")
        #expect(slot.take(instructions: "clean") == 7)
        #expect(slot.take(instructions: "clean") == nil)
    }

    @Test("an empty slot gives nothing")
    func empty() {
        #expect(WarmSlot<Int>().take(instructions: "clean") == nil)
    }

    @Test("a session stored for other instructions is not given, and is dropped")
    func otherInstructions() {
        let slot = WarmSlot<Int>()
        slot.store(7, instructions: "clean")
        #expect(slot.take(instructions: "summarize") == nil)
        #expect(slot.take(instructions: "clean") == nil)
    }

    @Test("a newer session replaces the one that was waiting")
    func newerReplaces() {
        let slot = WarmSlot<Int>()
        slot.store(1, instructions: "clean")
        slot.store(2, instructions: "clean")
        #expect(slot.take(instructions: "clean") == 2)
        #expect(slot.take(instructions: "clean") == nil)
    }
}
