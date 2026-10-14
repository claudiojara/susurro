/// How long the paste waits at each step.
enum PasteTiming {
    /// The pause between checks for a modifier key that is still down.
    static let modifierPollInterval = Duration.milliseconds(20)
    /// How long a modifier key may stay down before the paste is given up.
    static let modifierTimeout = Duration.milliseconds(500)
    /// The pause between checks for a read of the text.
    static let receiptPollInterval = Duration.milliseconds(50)
    /// How long an app may take to read the text after the chord before the paste counts as failed.
    static let receiptTimeout = Duration.seconds(8)
    /// How long the wait for a read lasts when the chord could not be posted.
    static let chordFailureTimeout = Duration.milliseconds(500)
    /// The quiet period: how long the pasteboard must go without a new read before the old contents come back.
    static let restoreDelay = Duration.milliseconds(200)
    /// The old contents never come back sooner than this after the chord, however early the first read. An app that
    /// reads the pasteboard a second time would otherwise find the old contents.
    static let minimumDwell = Duration.seconds(1)
    /// The longest an insertion waits for the paste before it. That paste has returned already, or it is stuck, and what
    /// is left of a paste that returned is its minimum dwell, which its task finds out about on its next poll, so one
    /// poll more.
    static let overlapWait = minimumDwell + receiptPollInterval
    /// The most one insertion takes in all: the wait for the paste before it, the snapshot and the wait for modifiers,
    /// and the wait for a read. It returns at the first read, so the minimum dwell and the last quiet period come after
    /// it, and the minimum dwell runs inside the wait for a read anyway. It must end before the coordinator's deadline
    /// for an insertion, or an insertion that was queued would be given up on while it still waits. `InsertBudget`
    /// enforces it as one wall-clock limit over the waits.
    static let insertBudget = overlapWait + modifierTimeout + receiptTimeout
}
