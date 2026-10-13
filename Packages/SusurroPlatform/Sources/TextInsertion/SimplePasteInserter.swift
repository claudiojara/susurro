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
    /// How long the text stays on the pasteboard after an app has read it, before the old contents come back.
    static let restoreDelay = Duration.milliseconds(300)
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
        switch await waitForModifiers() {
        case .released: break
        case .timedOut: return leaveOnClipboard(text, because: .pasteFailed)
        // Whoever cancelled has stopped listening, so this outcome is never read. Nothing was written.
        case .cancelled: return .copiedToClipboard(.pasteFailed)
        }
        let saved = PasteboardSnapshot(of: pasteboard)
        let promise = PromisedText(text)
        guard let writtenChangeCount = write(promise) else {
            saved.restore(to: pasteboard)
            return .copiedToClipboard(.pasteFailed)
        }
        if let reason = postChord() { return leaveOnClipboard(text, because: reason) }
        let chordPostedAt = now()
        // The chord is out, so the rest runs in a task of its own. A caller that is cancelled from here on cannot cut
        // the wait for the read short, which would restore the old contents before the app has read the text.
        return await Task { @MainActor in
            await finishPaste(
                text,
                promise: promise,
                saved: saved,
                writtenChangeCount: writtenChangeCount,
                chordPostedAt: chordPostedAt
            )
        }.value
    }

    /// Waits for an app to read the text, then restores the old contents after a quiet period. When no app reads the
    /// text in time, the paste has failed and the text stays.
    private func finishPaste(
        _ text: String,
        promise: PromisedText,
        saved: PasteboardSnapshot,
        writtenChangeCount: Int,
        chordPostedAt: Duration
    ) async -> InsertionOutcome {
        while promise.receipts == 0 {
            guard now() - chordPostedAt < PasteTiming.receiptTimeout else {
                return leaveOnClipboard(text, because: .pasteFailed)
            }
            // Nobody cancels this task, so a pause that throws is an injected one and the loop still ends by time.
            try? await sleep(PasteTiming.receiptPollInterval)
        }
        try? await sleep(PasteTiming.restoreDelay)
        // A newer write by anyone else wins over the old contents.
        if pasteboard.changeCount == writtenChangeCount { saved.restore(to: pasteboard) }
        return .inserted
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

    /// Clears the pasteboard and puts `item` on it. Returns the change count that the write produced, or nil when the
    /// item could not be built or the pasteboard refused it.
    private func replaceContents(with item: NSPasteboardItem?) -> Int? {
        pasteboard.clearContents()
        guard let item, writeItem(pasteboard, item) else { return nil }
        return pasteboard.changeCount
    }
}
