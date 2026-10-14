/// Decides, from successive counts of the reads of the promised text, when a paste is over. Only reads after the chord
/// count, and the old pasteboard comes back only when the app seems to be done with the text.
struct ReceiptWatch {
    enum Verdict: Equatable {
        /// Check again later.
        case wait
        /// The paste landed and the pasteboard is quiet: put the old contents back.
        case restore
        /// No app read the text in time.
        case failed
    }

    private let chordPostedAt: Duration
    private let receiptTimeout: Duration
    private var knownReads: Int
    private var lastReadAt: Duration?

    /// Whether an app has read the text since the chord. The paste has landed then, even though the old pasteboard
    /// stays out for a while longer.
    var hasRead: Bool { lastReadAt != nil }

    /// - Parameters:
    ///   - baseline: The number of reads before the chord, which do not count.
    ///   - receiptTimeout: How long after the chord an app may take to read the text. It is the full wait, or less when
    ///     the budget of the insertion has less left.
    init(baseline: Int, chordPostedAt: Duration, receiptTimeout: Duration = PasteTiming.receiptTimeout) {
        self.chordPostedAt = chordPostedAt
        self.receiptTimeout = receiptTimeout
        knownReads = baseline
    }

    /// - Parameters:
    ///   - reads: The total number of reads so far. A read is a request for the promised text, which the pasteboard
    ///     passes on only once (see `PromisedText`), so a second read by the same app is not seen.
    ///   - now: The time of this check, on the same clock as `chordPostedAt`.
    mutating func observe(reads: Int, at now: Duration) -> Verdict {
        if reads > knownReads {
            knownReads = reads
            lastReadAt = now
        }
        let sinceChord = now - chordPostedAt
        guard let lastReadAt else { return sinceChord >= receiptTimeout ? .failed : .wait }
        // Reads that keep coming cannot hold the old contents back for ever.
        if sinceChord >= receiptTimeout + PasteTiming.restoreDelay { return .restore }
        let isQuiet = now - lastReadAt >= PasteTiming.restoreDelay
        return isQuiet && sinceChord >= PasteTiming.minimumDwell ? .restore : .wait
    }
}
