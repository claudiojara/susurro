import Domain
import Testing

@Suite("Command limits")
struct CommandLimitsTests {
    @Test(
        "a rewrite gets 5 s and 40 ms for each character of instruction and selection, up to 20 s",
        arguments: [
            (0, 0, Duration.seconds(5)), (14, 199, .milliseconds(13_520)), (30, 345, .seconds(20)),
            (300, 1_500, .seconds(20)),
        ])
    func timeout(instruction: Int, selection: Int, expected: Duration) {
        #expect(CommandLimits.timeout(instruction: instruction, selection: selection) == expected)
    }

    @Test("the selection cap is 1,500 characters and the instruction cap 300")
    func caps() {
        #expect(CommandLimits.maxSelection == 1_500)
        #expect(CommandLimits.maxInstruction == 300)
    }
}
