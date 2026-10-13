import AppKit
import Domain

/// How long the inserter waits at each step.
enum PasteTiming {
    /// The pause between checks for a modifier key that is still down.
    static let modifierPollInterval = Duration.milliseconds(20)
    /// How long a modifier key may stay down before the paste is given up.
    static let modifierTimeout = Duration.milliseconds(500)
    /// The pause between checks for a read of the text.
    static let receiptPollInterval = Duration.milliseconds(50)
    /// How long an app may take to read the text after the chord before the paste counts as failed.
    static let receiptTimeout = Duration.seconds(8)
    /// The quiet period: how long the pasteboard must go without a new read before the old contents come back.
    static let restoreDelay = Duration.milliseconds(200)
    /// The old contents never come back sooner than this after the chord, however early the first read. An app that
    /// reads the pasteboard a second time would otherwise find the old contents.
    static let minimumDwell = Duration.seconds(1)
    /// The longest an insertion waits for the paste before it. That paste has returned already, or it is stuck, and what
    /// is left of a paste that returned is its minimum dwell, which its task finds out about on its next poll, so one
    /// poll more.
    static let overlapWait = minimumDwell + receiptPollInterval
    /// The most one `insert` takes in all: the wait for the paste before it, the wait for modifiers, and the wait for a
    /// read. It returns at the first read, so the minimum dwell and the last quiet period come after it, and the minimum
    /// dwell runs inside the wait for a read anyway. It must end before the coordinator's deadline for an insertion, or
    /// an insertion that was queued would be given up on while it still waits. `InsertBudget` enforces it as one
    /// wall-clock limit over the three waits.
    static let insertBudget = overlapWait + modifierTimeout + receiptTimeout
}

/// Pastes by promising the text on the pasteboard, posting Command+V, and putting the old pasteboard contents back
/// once an app has read the text and a short quiet period has passed, if nobody else has written to the pasteboard
/// since. `insert` returns as soon as an app has read the text; the old contents come back later, in a task of its
/// own, so the caller is not held up. A new insertion waits for that task before it takes its snapshot.
///
/// When the paste cannot be completed, the text is left on the pasteboard on purpose, as plain marked text, so that the
/// user can paste it by hand, and nothing is restored.
@MainActor
public final class SimplePasteInserter: TextInserter {
    private let pasteboard: NSPasteboard
    private let keystrokes: any KeystrokePoster
    /// The time on the injected clock that has passed since the inserter was created.
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let sourceBundleID: String
    private let writeItem: (NSPasteboard, NSPasteboardItem) -> Bool
    private let restoreItems: (NSPasteboard, [NSPasteboardItem]) -> Bool
    private let diagnostics: any DiagnosticsLog
    /// How many pastes have posted their chord and are still waiting to finish. A new insertion waits for them.
    private var inFlight = 0
    /// The task of the most recent paste that posted its chord.
    private var finishing: Task<Void, Never>?

    /// What the paste under way has to put back: the user's old contents, and the change count that our own write
    /// produced, which tells whether anyone else has written since. Only one paste holds a snapshot at a time, because
    /// a new insertion waits for the paste before it.
    private struct PendingRestore {
        let saved: PasteboardSnapshot
        let writtenChangeCount: Int
    }
    private var pendingRestore: PendingRestore?

    /// Why a paste did not land. The name goes to the log.
    private enum Cause: String {
        case earlierPasteStuck
        case modifiersHeld
        case accessibilityMissing
        case chordNotPosted
        case noRead
    }

    /// - Parameters:
    ///   - clock: Measures and paces every wait. Tests pass a clock they control.
    ///   - sourceBundleID: Written to the pasteboard so that clipboard managers can tell which app wrote the text.
    ///   - diagnostics: Where a paste that did not land, or a pasteboard that refused a write, is reported.
    public convenience init(
        pasteboard: NSPasteboard = .general,
        keystrokes: any KeystrokePoster = CGEventKeystrokePoster(),
        clock: any Clock<Duration> = ContinuousClock(),
        sourceBundleID: String = Bundle.main.bundleIdentifier ?? "dev.claudiojara.susurro",
        diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        self.init(
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            clock: clock,
            sourceBundleID: sourceBundleID,
            diagnostics: diagnostics,
            writeItem: { $0.writeObjects([$1]) },
            restoreItems: { $0.writeObjects($1) }
        )
    }

    /// - Parameters:
    ///   - writeItem: Puts an item on the pasteboard and says whether it was accepted. Tests pass one that refuses.
    ///   - restoreItems: Puts the user's old items back and says whether they were accepted. Tests pass one that refuses.
    init(
        pasteboard: NSPasteboard,
        keystrokes: any KeystrokePoster,
        clock: any Clock<Duration>,
        sourceBundleID: String,
        diagnostics: any DiagnosticsLog,
        writeItem: @escaping (NSPasteboard, NSPasteboardItem) -> Bool,
        restoreItems: @escaping (NSPasteboard, [NSPasteboardItem]) -> Bool
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        (now, sleep) = Self.timeline(of: clock)
        self.sourceBundleID = sourceBundleID
        self.diagnostics = diagnostics
        self.writeItem = writeItem
        self.restoreItems = restoreItems
    }

    /// Reads a clock as the time since now, and sleeps on it. This is generic so that the clock's own instant type is
    /// known while the origin is held.
    private nonisolated static func timeline<C: Clock<Duration>>(
        of clock: C
    ) -> (now: @Sendable () -> Duration, sleep: @Sendable (Duration) async throws -> Void) {
        let origin = clock.now
        return ({ origin.duration(to: clock.now) }, { try await clock.sleep(for: $0) })
    }

    public func insert(_ text: String) async -> InsertionOutcome {
        guard !text.isEmpty else { return .inserted }
        let budget = InsertBudget(startingAt: now())
        guard await waitForPastesInFlight(within: budget) else {
            // The pasteboard still holds the text of the paste before this one, so a snapshot of it would bring that
            // text back as the user's. Nothing is snapshotted, no chord is posted, and the text stays for the user.
            guard !Task.isCancelled else { return Self.cancelled }
            return leaveOnClipboard(text, because: .pasteFailed, cause: .earlierPasteStuck)
        }
        switch await waitForModifiers(within: budget) {
        case .released: break
        case .timedOut: return leaveOnClipboard(text, because: .pasteFailed, cause: .modifiersHeld)
        case .cancelled: return Self.cancelled
        }
        guard !Task.isCancelled else { return Self.cancelled }
        let saved = PasteboardSnapshot(of: pasteboard)
        let promise = PromisedText(text)
        guard let writtenChangeCount = write(promise) else {
            restore(saved)
            return .notInserted(.clipboardWriteFailed)
        }
        pendingRestore = PendingRestore(saved: saved, writtenChangeCount: writtenChangeCount)
        guard !Task.isCancelled else {
            restoreIfStillOurs()
            return Self.cancelled
        }
        let readsBeforeTheChord = promise.receipts
        if let reason = postChord() {
            let cause: Cause = reason == .accessibilityMissing ? .accessibilityMissing : .chordNotPosted
            return leaveOnClipboard(text, because: reason, cause: cause)
        }
        let chordPostedAt = now()
        // No app may take longer than what is left of the budget, up to the usual limit.
        let receiptTimeout = min(PasteTiming.receiptTimeout, budget.remaining(at: chordPostedAt))
        // The chord is out, so the rest runs in a task of its own. A caller that is cancelled from here on cannot cut
        // the wait for the read short, which would restore the old contents before the app has read the text. The
        // caller gets its outcome at the first read; the task then goes on to put the old contents back.
        inFlight += 1
        return await withCheckedContinuation { continuation in
            finishing = Task { @MainActor in
                defer { inFlight -= 1 }
                // `writtenChangeCount` is the change count after our write. Providing the promised text to an app does
                // not change it (see `PromisedTextTests`), so a different count means that someone else has written to
                // the pasteboard.
                var watch = ReceiptWatch(
                    baseline: readsBeforeTheChord, chordPostedAt: chordPostedAt, receiptTimeout: receiptTimeout)
                let outcome = await awaitFirstRead(
                    of: text, promise: promise, writtenChangeCount: writtenChangeCount, watch: &watch)
                continuation.resume(returning: outcome)
                guard outcome == .inserted else { return }
                await restoreWhenQuiet(promise: promise, watch: &watch)
            }
        }
    }

    /// Puts the user's old pasteboard contents back at once, without waiting for an app to read the text or for the
    /// quiet period. The app calls it as it terminates, when a paste may still be waiting to finish and the task that
    /// would restore the pasteboard will not run. It does nothing when no paste is waiting, and nothing when someone
    /// else has written to the pasteboard since our write. Either way it logs what it did.
    public func restoreForTermination() {
        diagnostics.record(.clipboardRestoreAtTermination(restored: restoreIfStillOurs()))
    }

    /// Waits for every paste that has posted its chord to finish. `insert` returns at the first read of the text,
    /// before the old pasteboard is back, so a caller that needs the final pasteboard waits here.
    public func drain() async {
        await finishing?.value
    }

    /// Waits for an app to read the text. When none does in time, the paste has failed and the text stays.
    private func awaitFirstRead(
        of text: String,
        promise: PromisedText,
        writtenChangeCount: Int,
        watch: inout ReceiptWatch
    ) async -> InsertionOutcome {
        while true {
            let verdict = watch.observe(reads: promise.receipts, at: now())
            if watch.hasRead { return .inserted }
            if verdict == .failed { return giveUp(on: text, writtenChangeCount: writtenChangeCount) }
            do {
                try await sleep(PasteTiming.receiptPollInterval)
            } catch {
                // Nobody cancels this task, so this is a clock that cannot pause. Without a pause the loop could spin.
                return giveUp(on: text, writtenChangeCount: writtenChangeCount)
            }
        }
    }

    /// Waits for the minimum dwell and for the pasteboard to go quiet, then restores the old contents.
    private func restoreWhenQuiet(promise: PromisedText, watch: inout ReceiptWatch) async {
        while watch.observe(reads: promise.receipts, at: now()) != .restore {
            do {
                try await sleep(PasteTiming.receiptPollInterval)
            } catch {
                // A clock that cannot pause cannot be waited on. The paste has landed, so the old contents come back now.
                break
            }
        }
        restoreIfStillOurs()
    }

    /// Puts the old contents back, unless anyone else has written to the pasteboard since our write: a newer write wins.
    /// It takes the old contents out of the inserter first, so that they are put back once, by whoever comes first.
    /// Returns whether the old contents are back.
    @discardableResult
    private func restoreIfStillOurs() -> Bool {
        guard let pending = pendingRestore else { return false }
        pendingRestore = nil
        return pasteboard.changeCount == pending.writtenChangeCount && restore(pending.saved)
    }

    @discardableResult
    private func restore(_ saved: PasteboardSnapshot) -> Bool {
        let restored = saved.restore(to: pasteboard, writing: restoreItems)
        if !restored { diagnostics.record(.clipboardRestoreFailed) }
        return restored
    }

    /// Ends a paste that did not land: the text stays on the pasteboard unless the user copied something meanwhile.
    private func giveUp(on text: String, writtenChangeCount: Int) -> InsertionOutcome {
        // A copy that the user made while the paste waited wins over the text, which is then nowhere.
        guard pasteboard.changeCount == writtenChangeCount else {
            pendingRestore = nil
            diagnostics.record(.pasteNotCompleted(cause: Cause.noRead.rawValue))
            return .notInserted(.clipboardChanged)
        }
        return leaveOnClipboard(text, because: .pasteFailed, cause: .noRead)
    }

    /// Posts the paste chord. Returns why it could not be posted, or nil when it was.
    private func postChord() -> ClipboardReason? {
        do {
            try keystrokes.postPaste()
            return nil
        } catch KeystrokeError.accessibilityNotGranted {
            return .accessibilityMissing
        } catch {
            return .pasteFailed
        }
    }

    /// What `insert` returns when its caller was cancelled before the chord. The caller has stopped listening, so the
    /// outcome is never read, and nothing was left on the pasteboard.
    private static let cancelled = InsertionOutcome.copiedToClipboard(.pasteFailed)

    /// Waits for a paste that is still finishing, such as one whose caller gave up on it, so that this insertion does
    /// not take that text for the user's pasteboard. Returns whether none is left. It is false when the wait ran out or
    /// a pause failed, and the pasteboard cannot be trusted then.
    private func waitForPastesInFlight(within budget: InsertBudget) async -> Bool {
        let deadline = budget.deadline(for: PasteTiming.overlapWait, from: now())
        while inFlight > 0 {
            guard now() < deadline else { return false }
            do {
                try await sleep(PasteTiming.receiptPollInterval)
            } catch {
                return false
            }
        }
        return true
    }

    private enum ModifierWait {
        case released
        case timedOut
        case cancelled
    }

    /// Waits for the modifier keys to come up, for as long as the timeout allows.
    private func waitForModifiers(within budget: InsertBudget) async -> ModifierWait {
        let deadline = budget.deadline(for: PasteTiming.modifierTimeout, from: now())
        while keystrokes.modifiersHeld() {
            guard now() < deadline else { return .timedOut }
            do {
                try await sleep(PasteTiming.modifierPollInterval)
            } catch {
                return .cancelled
            }
        }
        return .released
    }

    /// Replaces the pasteboard contents with the promised text and returns the change count that this write produced.
    /// Nil when the pasteboard refused the write.
    private func write(_ promise: PromisedText) -> Int? {
        replaceContents(with: .marked(source: sourceBundleID) { $0.setDataProvider(promise, forTypes: [.string]) })
    }

    /// Replaces the pasteboard contents with the text itself, as plain marked text with nothing promised.
    private func leaveOnClipboard(_ text: String, because reason: ClipboardReason, cause: Cause) -> InsertionOutcome {
        diagnostics.record(.pasteNotCompleted(cause: cause.rawValue))
        let item = NSPasteboardItem.marked(source: sourceBundleID) { $0.setString(text, forType: .string) }
        // The old contents were taken for the paste, if there was one, and the text stays instead of them.
        let saved = pendingRestore?.saved
        pendingRestore = nil
        guard replaceContents(with: item) != nil else {
            // If even this write is refused there is nothing left to try, and the text is nowhere. The write cleared the
            // pasteboard, so the old contents, if the paste had taken them, go back.
            if let saved { restore(saved) }
            return .notInserted(.clipboardWriteFailed)
        }
        return .copiedToClipboard(reason)
    }

    /// Replaces the pasteboard contents with `item`. Returns the change count that the write produced, or nil when the
    /// item could not be built or the pasteboard refused it.
    private func replaceContents(with item: NSPasteboardItem?) -> Int? {
        // Current host only: Universal Clipboard would otherwise carry the dictation to the user's other devices, and
        // the sync's own read of the text could look like an app reading it.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard let item, writeItem(pasteboard, item) else {
            diagnostics.record(.pasteboardWriteRefused)
            return nil
        }
        return pasteboard.changeCount
    }
}
