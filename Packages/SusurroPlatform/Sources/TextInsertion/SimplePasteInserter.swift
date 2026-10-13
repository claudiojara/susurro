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
    /// The longest a paste can take: the wait for modifiers, the wait for a read, and one last quiet period. The
    /// minimum dwell runs inside the wait for a read, so it adds nothing.
    static let worstCase = modifierTimeout + receiptTimeout + restoreDelay
}

/// Pastes by promising the text on the pasteboard, posting Command+V, and putting the old pasteboard contents back
/// once an app has read the text and a short quiet period has passed, if nobody else has written to the pasteboard
/// since. Insertions must not overlap: the caller waits for one to finish before it starts the next.
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
    /// How many pastes have posted their chord and are still waiting to finish. A new insertion waits for them.
    private var inFlight = 0

    /// - Parameters:
    ///   - clock: Measures and paces every wait. Tests pass a clock they control.
    ///   - sourceBundleID: Written to the pasteboard so that clipboard managers can tell which app wrote the text.
    public convenience init(
        pasteboard: NSPasteboard = .general,
        keystrokes: any KeystrokePoster = CGEventKeystrokePoster(),
        clock: any Clock<Duration> = ContinuousClock(),
        sourceBundleID: String = Bundle.main.bundleIdentifier ?? "dev.claudiojara.susurro"
    ) {
        self.init(
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            clock: clock,
            sourceBundleID: sourceBundleID,
            writeItem: { $0.writeObjects([$1]) }
        )
    }

    /// - Parameter writeItem: Puts an item on the pasteboard and says whether it was accepted. Tests pass one that
    ///   refuses.
    init(
        pasteboard: NSPasteboard,
        keystrokes: any KeystrokePoster,
        clock: any Clock<Duration>,
        sourceBundleID: String,
        writeItem: @escaping (NSPasteboard, NSPasteboardItem) -> Bool
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        (now, sleep) = Self.timeline(of: clock)
        self.sourceBundleID = sourceBundleID
        self.writeItem = writeItem
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
        await waitForPastesInFlight()
        switch await waitForModifiers() {
        case .released: break
        case .timedOut: return leaveOnClipboard(text, because: .pasteFailed)
        case .cancelled: return Self.cancelled
        }
        guard !Task.isCancelled else { return Self.cancelled }
        let saved = PasteboardSnapshot(of: pasteboard)
        let promise = PromisedText(text)
        guard let writtenChangeCount = write(promise) else {
            saved.restore(to: pasteboard)
            return .copiedToClipboard(.pasteFailed)
        }
        guard !Task.isCancelled else {
            if pasteboard.changeCount == writtenChangeCount { saved.restore(to: pasteboard) }
            return Self.cancelled
        }
        let readsBeforeTheChord = promise.receipts
        if let reason = postChord() { return leaveOnClipboard(text, because: reason) }
        let chordPostedAt = now()
        // The chord is out, so the rest runs in a task of its own. A caller that is cancelled from here on cannot cut
        // the wait for the read short, which would restore the old contents before the app has read the text.
        inFlight += 1
        return await Task { @MainActor in
            defer { inFlight -= 1 }
            return await finishPaste(
                text,
                promise: promise,
                saved: saved,
                writtenChangeCount: writtenChangeCount,
                readsBeforeTheChord: readsBeforeTheChord,
                chordPostedAt: chordPostedAt
            )
        }.value
    }

    /// Waits for an app to read the text and for the pasteboard to go quiet, then restores the old contents. When no
    /// app reads the text in time, the paste has failed and the text stays.
    private func finishPaste(
        _ text: String,
        promise: PromisedText,
        saved: PasteboardSnapshot,
        writtenChangeCount: Int,
        readsBeforeTheChord: Int,
        chordPostedAt: Duration
    ) async -> InsertionOutcome {
        // `writtenChangeCount` is the change count after our write. Providing the promised text to an app does not change
        // it (see `PromisedTextTests`), so a different count means that someone else has written to the pasteboard.
        var watch = ReceiptWatch(baseline: readsBeforeTheChord, chordPostedAt: chordPostedAt)
        while true {
            switch watch.observe(reads: promise.receipts, at: now()) {
            case .wait:
                break
            case .failed:
                return giveUp(on: text, writtenChangeCount: writtenChangeCount)
            case .restore:
                // A newer write by anyone else wins over the old contents.
                if pasteboard.changeCount == writtenChangeCount { saved.restore(to: pasteboard) }
                return .inserted
            }
            do {
                try await sleep(PasteTiming.receiptPollInterval)
            } catch {
                // Nobody cancels this task, so this is a clock that cannot pause. Without a pause the loop could spin.
                return giveUp(on: text, writtenChangeCount: writtenChangeCount)
            }
        }
    }

    /// Ends a paste that did not land: the text stays on the pasteboard unless the user copied something meanwhile.
    private func giveUp(on text: String, writtenChangeCount: Int) -> InsertionOutcome {
        // A copy that the user made while the paste waited wins over the text.
        guard pasteboard.changeCount == writtenChangeCount else { return .copiedToClipboard(.pasteFailed) }
        return leaveOnClipboard(text, because: .pasteFailed)
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
    /// not take that text for the user's pasteboard. The wait is bounded by the longest a paste can take.
    private func waitForPastesInFlight() async {
        let deadline = now() + PasteTiming.worstCase
        while inFlight > 0, now() < deadline {
            do {
                try await sleep(PasteTiming.receiptPollInterval)
            } catch {
                return
            }
        }
    }

    private enum ModifierWait {
        case released
        case timedOut
        case cancelled
    }

    /// Waits for the modifier keys to come up, for as long as the timeout allows.
    private func waitForModifiers() async -> ModifierWait {
        let deadline = now() + PasteTiming.modifierTimeout
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
    private func leaveOnClipboard(_ text: String, because reason: ClipboardReason) -> InsertionOutcome {
        // If even this write is refused there is nothing left to try, and the outcome stays the same.
        _ = replaceContents(with: .marked(source: sourceBundleID) { $0.setString(text, forType: .string) })
        return .copiedToClipboard(reason)
    }

    /// Replaces the pasteboard contents with `item`. Returns the change count that the write produced, or nil when the
    /// item could not be built or the pasteboard refused it.
    private func replaceContents(with item: NSPasteboardItem?) -> Int? {
        // Current host only: Universal Clipboard would otherwise carry the dictation to the user's other devices, and
        // the sync's own read of the text could look like an app reading it.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard let item, writeItem(pasteboard, item) else { return nil }
        return pasteboard.changeCount
    }
}
