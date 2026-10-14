import Domain

/// Pastes the dictated text into the app the dictation started in, and puts the user's clipboard back. The policy
/// follows the design's nine steps; each has a method of its own:
///
/// 1. Empty text does nothing.
/// 2. `verifyTarget`: the app in front is still the one the dictation started in.
/// 3. `waitForModifiers`: no hotkey modifier is still down.
/// 4. `takeSnapshot`: every item and type on the pasteboard.
/// 5. `publish`: the text as a marked promise, and the change count right after it.
/// 6. `postChord`: Command+V.
/// 7. `awaitFirstRead`: a request for the promised text after the chord means the paste landed.
/// 8. `restoreWhenQuiet`: the snapshot comes back after a quiet period, if nobody else has written meanwhile.
/// 9. `leaveOnClipboard`: when the paste did not land, the text itself stays on the pasteboard.
///
/// `insert` returns as soon as an app has read the text; the old contents come back later, in a task of its own, so
/// the caller is not held up. A new insertion waits for that task before it takes its snapshot. Insertions run one at a
/// time, in the order they were submitted.
@MainActor
public final class PasteTransaction: TextInserter {
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokePoster
    private let frontmost: any FrontmostAppProvider
    private let diagnostics: any DiagnosticsLog
    /// The time on the injected clock that has passed since the transaction was created.
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let queue = InsertionQueue()
    /// How many pastes have posted their chord and are still waiting to finish. A new insertion waits for them.
    private var inFlight = 0
    /// The task of the most recent paste that posted its chord.
    private var finishing: Task<Void, Never>?

    /// What the paste under way has to put back: the user's old contents, and the change count right after our own
    /// write, which tells whether anyone else has written since. Only one paste holds a snapshot at a time, because a
    /// new insertion waits for the paste before it.
    private struct PendingRestore {
        let saved: PasteboardSnapshot
        let baseline: Int
    }
    private var pendingRestore: PendingRestore?

    /// Why a paste did not land. The name goes to the log.
    private enum Cause: String {
        case earlierPasteStuck
        case targetChanged
        case modifiersHeld
        case accessibilityMissing
        case chordNotPosted
        case noRead
    }

    private struct Failure {
        let reason: ClipboardReason
        let cause: Cause
    }

    /// - Parameters:
    ///   - frontmost: Tells which app is in front, to compare with the one a dictation started in.
    ///   - clock: Measures and paces every wait. Tests pass a clock they control.
    ///   - diagnostics: Where a paste that did not land, or a pasteboard that refused a write, is reported.
    public init(
        pasteboard: any Pasteboard,
        keystrokes: any KeystrokePoster,
        frontmost: any FrontmostAppProvider,
        clock: any Clock<Duration> = ContinuousClock(),
        diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.frontmost = frontmost
        self.diagnostics = diagnostics
        (now, sleep) = Self.timeline(of: clock)
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
        await insert(text, into: nil)
    }

    public func insert(_ text: String, into target: AppIdentity?) async -> InsertionOutcome {
        guard !text.isEmpty else { return .inserted }
        return await queue.run { await self.transact(text, target: target) }
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

    // MARK: The transaction

    private func transact(_ text: String, target: AppIdentity?) async -> InsertionOutcome {
        let budget = InsertBudget(startingAt: now())
        guard !Task.isCancelled else { return Self.cancelled }
        guard await waitForPastesInFlight(within: budget) else {
            // The pasteboard still holds the text of the paste before this one, so a snapshot of it would bring that
            // text back as the user's. Nothing is snapshotted, no chord is posted, and the text stays for the user.
            guard !Task.isCancelled else { return Self.cancelled }
            return leaveOnClipboard(text, Failure(reason: .pasteFailed, cause: .earlierPasteStuck))
        }
        guard verifyTarget(target) else {
            return leaveOnClipboard(text, Failure(reason: .pasteFailed, cause: .targetChanged))
        }
        switch await waitForModifiers(within: budget) {
        case .released: break
        case .timedOut: return leaveOnClipboard(text, Failure(reason: .pasteFailed, cause: .modifiersHeld))
        case .cancelled: return Self.cancelled
        }
        guard !Task.isCancelled else { return Self.cancelled }
        let saved = await takeSnapshot()
        guard !Task.isCancelled else { return Self.cancelled }
        guard let published = publish(text) else {
            restore(saved)
            return .notInserted(.clipboardWriteFailed)
        }
        pendingRestore = PendingRestore(saved: saved, baseline: published.baseline)
        guard !Task.isCancelled else {
            restoreIfStillOurs()
            return Self.cancelled
        }
        let readsBeforeTheChord = published.receipts.count
        let chordFailure = postChord()
        let chordPostedAt = now()
        // No app may take longer than what is left of the budget, up to the usual limit.
        let limit = chordFailure == nil ? PasteTiming.receiptTimeout : PasteTiming.chordFailureTimeout
        let receiptTimeout = min(limit, budget.remaining(at: chordPostedAt))
        // The chord is out, so the rest runs in a task of its own. A caller that is cancelled from here on cannot cut
        // the wait for the read short, which would restore the old contents before the app has read the text. The
        // caller gets its outcome at the first read; the task then goes on to put the old contents back.
        inFlight += 1
        return await withCheckedContinuation { continuation in
            finishing = Task { @MainActor in
                defer { inFlight -= 1 }
                var watch = ReceiptWatch(
                    baseline: readsBeforeTheChord, chordPostedAt: chordPostedAt, receiptTimeout: receiptTimeout)
                let outcome = await awaitFirstRead(
                    of: text, receipts: published.receipts, baseline: published.baseline, failure: chordFailure,
                    watch: &watch)
                continuation.resume(returning: outcome)
                guard outcome == .inserted else { return }
                await restoreWhenQuiet(receipts: published.receipts, watch: &watch)
            }
        }
    }

    /// Step 2. Without a target there is nothing to compare, and the paste goes ahead.
    private func verifyTarget(_ target: AppIdentity?) -> Bool {
        guard let target else { return true }
        return frontmost.current()?.processID == target.processID
    }

    private enum ModifierWait {
        case released
        case timedOut
        case cancelled
    }

    /// Step 3. Waits for the modifier keys to come up, for as long as the timeout allows.
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

    /// Step 4. The old contents, read away from the main actor.
    private func takeSnapshot() async -> PasteboardSnapshot {
        await pasteboard.snapshot()
    }

    /// Step 5. Replaces the pasteboard contents with the promised text and returns the reads counter and the change
    /// count that this write produced. Nil when the pasteboard refused the write.
    private func publish(_ text: String) -> (receipts: ReadReceipts, baseline: Int)? {
        do {
            let receipts = try pasteboard.publishPromise(text)
            return (receipts, pasteboard.changeCount)
        } catch {
            diagnostics.record(.pasteboardWriteRefused)
            return nil
        }
    }

    /// Step 6. Posts the paste chord. Returns why it could not be posted, or nil when it was.
    private func postChord() -> Failure? {
        do {
            try keystrokes.postPaste()
            return nil
        } catch KeystrokeError.accessibilityNotGranted {
            return Failure(reason: .accessibilityMissing, cause: .accessibilityMissing)
        } catch {
            return Failure(reason: .pasteFailed, cause: .chordNotPosted)
        }
    }

    /// Step 7. Waits for an app to read the text. When none does in time, the paste has failed and the text stays. A
    /// chord that could not be posted gets the short wait only, in case the paste reached the app anyway.
    private func awaitFirstRead(
        of text: String,
        receipts: ReadReceipts,
        baseline: Int,
        failure chordFailure: Failure?,
        watch: inout ReceiptWatch
    ) async -> InsertionOutcome {
        let failure = chordFailure ?? Failure(reason: .pasteFailed, cause: .noRead)
        while true {
            let verdict = watch.observe(reads: receipts.count, at: now())
            if watch.hasRead { return .inserted }
            if verdict == .failed { return giveUp(on: text, baseline: baseline, failure) }
            do {
                try await sleep(PasteTiming.receiptPollInterval)
            } catch {
                // Nobody cancels this task, so this is a clock that cannot pause. Without a pause the loop could spin.
                return giveUp(on: text, baseline: baseline, failure)
            }
        }
    }

    /// Step 8. Waits for the minimum dwell and for the pasteboard to go quiet, then restores the old contents.
    private func restoreWhenQuiet(receipts: ReadReceipts, watch: inout ReceiptWatch) async {
        while watch.observe(reads: receipts.count, at: now()) != .restore {
            do {
                try await sleep(PasteTiming.receiptPollInterval)
            } catch {
                // A clock that cannot pause cannot be waited on. The paste has landed, so the old contents come back now.
                break
            }
        }
        restoreIfStillOurs()
    }

    /// Step 9. Replaces the pasteboard contents with the text itself, as plain marked text with nothing promised. The
    /// old contents are not coming back.
    private func leaveOnClipboard(_ text: String, _ failure: Failure) -> InsertionOutcome {
        diagnostics.record(.pasteNotCompleted(cause: failure.cause.rawValue))
        // The old contents were taken for the paste, if there was one, and the text stays instead of them.
        let saved = pendingRestore?.saved
        pendingRestore = nil
        do {
            try pasteboard.writeConcrete(text)
        } catch {
            diagnostics.record(.pasteboardWriteRefused)
            // If even this write is refused there is nothing left to try, and the text is nowhere. The write cleared the
            // pasteboard, so the old contents, if the paste had taken them, go back.
            if let saved { restore(saved) }
            return .notInserted(.clipboardWriteFailed)
        }
        return .copiedToClipboard(failure.reason)
    }

    // MARK: Helpers

    /// Ends a paste that did not land: the text stays on the pasteboard unless the user copied something meanwhile.
    private func giveUp(on text: String, baseline: Int, _ failure: Failure) -> InsertionOutcome {
        // A copy that the user made while the paste waited wins over the text, which is then nowhere.
        guard pasteboard.changeCount == baseline else {
            pendingRestore = nil
            diagnostics.record(.pasteNotCompleted(cause: failure.cause.rawValue))
            return .notInserted(.clipboardChanged)
        }
        return leaveOnClipboard(text, failure)
    }

    /// Puts the old contents back, unless anyone else has written to the pasteboard since our write: a newer write wins.
    /// It takes the old contents out of the transaction first, so that they are put back once, by whoever comes first.
    /// A snapshot with a gap is not put back: it would replace the dictation with a clipboard that lacks part of what
    /// the user had. Returns whether the old contents are back.
    @discardableResult
    private func restoreIfStillOurs() -> Bool {
        guard let pending = pendingRestore else { return false }
        pendingRestore = nil
        guard pasteboard.changeCount == pending.baseline else { return false }
        if let gap = pending.saved.gap {
            diagnostics.record(.clipboardNotRestored(reason: gap.rawValue))
            return false
        }
        return restore(pending.saved)
    }

    @discardableResult
    private func restore(_ saved: PasteboardSnapshot) -> Bool {
        do {
            try pasteboard.restore(saved)
            return true
        } catch {
            diagnostics.record(.clipboardRestoreFailed)
            return false
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
}
