import AppKit
import Domain

/// How long the walking-skeleton inserter waits at each step.
enum PasteTiming {
    /// The pause between checks for a modifier key that is still down.
    static let modifierPollInterval = Duration.milliseconds(20)
    /// How long a modifier key may stay down before the paste is given up.
    static let modifierTimeout = Duration.milliseconds(500)
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
    private let sleep: @MainActor (Duration) async throws -> Void
    private let sourceBundleID: String
    private let writeItem: (NSPasteboard, NSPasteboardItem) -> Bool

    /// - Parameters:
    ///   - sleep: Paces the waits. Tests pass a fake.
    ///   - sourceBundleID: Written to the pasteboard so that clipboard managers can tell which app wrote the text.
    public convenience init(
        pasteboard: NSPasteboard = .general,
        keystrokes: any KeystrokePoster = CGEventKeystrokePoster(),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        sourceBundleID: String = Bundle.main.bundleIdentifier ?? "dev.claudiojara.susurro"
    ) {
        self.init(
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            sleep: sleep,
            sourceBundleID: sourceBundleID,
            writeItem: { $0.writeObjects([$1]) }
        )
    }

    /// - Parameter writeItem: Puts an item on the pasteboard and says whether it was accepted. Tests pass one that
    ///   refuses.
    init(
        pasteboard: NSPasteboard,
        keystrokes: any KeystrokePoster,
        sleep: @escaping @MainActor (Duration) async throws -> Void,
        sourceBundleID: String,
        writeItem: @escaping (NSPasteboard, NSPasteboardItem) -> Bool
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.sleep = sleep
        self.sourceBundleID = sourceBundleID
        self.writeItem = writeItem
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
        // The chord is out, so the rest runs in a task of its own. A caller that is cancelled from here on cannot cut
        // the wait for the read short, which would restore the old contents before the app has read the text.
        return await Task { @MainActor in
            await finishPaste(text, promise: promise, saved: saved, writtenChangeCount: writtenChangeCount)
        }.value
    }

    /// Waits for an app to read the text, then restores the old contents after a quiet period. When no app reads the
    /// text in time, the paste has failed and the text stays.
    private func finishPaste(
        _ text: String,
        promise: PromisedText,
        saved: PasteboardSnapshot,
        writtenChangeCount: Int
    ) async -> InsertionOutcome {
        var waited = Duration.zero
        while promise.receipts == 0 {
            guard waited < PasteTiming.receiptTimeout else { return leaveOnClipboard(text, because: .pasteFailed) }
            // Nobody cancels this task, so a pause that throws is an injected one and the loop still ends by time.
            try? await sleep(PasteTiming.modifierPollInterval)
            waited += PasteTiming.modifierPollInterval
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
        var waited = Duration.zero
        while keystrokes.modifiersHeld() {
            guard waited < PasteTiming.modifierTimeout else { return .timedOut }
            do {
                try await sleep(PasteTiming.modifierPollInterval)
            } catch {
                return .cancelled
            }
            waited += PasteTiming.modifierPollInterval
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
