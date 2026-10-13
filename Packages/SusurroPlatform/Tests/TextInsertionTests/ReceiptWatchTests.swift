import Testing

@testable import TextInsertion

@Suite("Receipt watch")
struct ReceiptWatchTests {
    /// When the chord was posted. Offsets below are measured from it.
    private static let chord = Duration.seconds(5)

    private func verdict(_ watch: inout ReceiptWatch, reads: Int, after offset: Duration) -> ReceiptWatch.Verdict {
        watch.observe(reads: reads, at: Self.chord + offset)
    }

    private func newWatch(baseline: Int = 0) -> ReceiptWatch {
        ReceiptWatch(baseline: baseline, chordPostedAt: Self.chord)
    }

    @Test("with no read the watch waits until 8 s after the chord and then fails")
    func noRead() {
        var watch = newWatch()

        #expect(verdict(&watch, reads: 0, after: .zero) == .wait)
        #expect(verdict(&watch, reads: 0, after: .milliseconds(7_950)) == .wait)
        #expect(verdict(&watch, reads: 0, after: .seconds(8)) == .failed)
    }

    @Test("reads that were there before the chord are not reads")
    func baseline() {
        var watch = newWatch(baseline: 2)

        #expect(verdict(&watch, reads: 2, after: .milliseconds(500)) == .wait)
        #expect(verdict(&watch, reads: 2, after: .seconds(8)) == .failed)
    }

    @Test("a read at once still waits for the minimum dwell of 1 s")
    func dwell() {
        var watch = newWatch()

        #expect(verdict(&watch, reads: 1, after: .zero) == .wait)
        #expect(verdict(&watch, reads: 1, after: .milliseconds(950)) == .wait)
        #expect(verdict(&watch, reads: 1, after: .seconds(1)) == .restore)
    }

    @Test("a late read waits for 200 ms of quiet")
    func quiet() {
        var watch = newWatch()

        #expect(verdict(&watch, reads: 1, after: .seconds(2)) == .wait)
        #expect(verdict(&watch, reads: 1, after: .milliseconds(2_150)) == .wait)
        #expect(verdict(&watch, reads: 1, after: .milliseconds(2_200)) == .restore)
    }

    @Test("a new read during the quiet window restarts it")
    func newReadRestartsTheQuiet() {
        var watch = newWatch()

        #expect(verdict(&watch, reads: 1, after: .seconds(2)) == .wait)
        #expect(verdict(&watch, reads: 2, after: .milliseconds(2_150)) == .wait)
        #expect(verdict(&watch, reads: 2, after: .milliseconds(2_300)) == .wait)  // 150 ms after the second read
        #expect(verdict(&watch, reads: 2, after: .milliseconds(2_350)) == .restore)
    }

    @Test("a read at the 8 s mark still counts")
    func readAtTheDeadline() {
        var watch = newWatch()

        #expect(verdict(&watch, reads: 1, after: .seconds(8)) == .wait)
        #expect(verdict(&watch, reads: 1, after: .milliseconds(8_200)) == .restore)
    }

    @Test("reads that never stop cannot hold the restore past 8.2 s after the chord")
    func readsThatNeverStop() {
        var watch = newWatch()
        var reads = 0
        var verdicts: [ReceiptWatch.Verdict] = []

        for milliseconds in stride(from: 0, through: 8_200, by: 50) {
            reads += 1
            verdicts.append(verdict(&watch, reads: reads, after: .milliseconds(milliseconds)))
        }

        #expect(verdicts.dropLast().allSatisfy { $0 == .wait })
        #expect(verdicts.last == .restore)
    }
}
