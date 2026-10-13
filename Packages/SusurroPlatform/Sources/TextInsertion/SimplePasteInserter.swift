import AppKit
import Domain

/// How long the walking-skeleton inserter waits at each step.
enum PasteTiming {
    /// The pause between checks for a modifier key that is still down.
    static let modifierPollInterval = Duration.milliseconds(20)
    /// How long a modifier key may stay down before the paste is given up.
    static let modifierTimeout = Duration.milliseconds(500)
    /// How long the text stays on the pasteboard after the chord, before the old contents come back.
    static let restoreDelay = Duration.milliseconds(300)
}

/// Pastes by writing the text to the pasteboard, posting Command+V, and putting the old pasteboard contents back after
/// a fixed delay if nobody else has written to it since. Insertions must not overlap: the caller waits for one to
/// finish before it starts the next.
@MainActor
public final class SimplePasteInserter: TextInserter {
    private let pasteboard: NSPasteboard
    private let keystrokes: any KeystrokePoster
    private let sleep: @MainActor (Duration) async throws -> Void

    /// - Parameter sleep: Paces the waits. Tests pass a fake.
    public init(
        pasteboard: NSPasteboard = .general,
        keystrokes: any KeystrokePoster = CGEventKeystrokePoster(),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.sleep = sleep
    }

    public func insert(_ text: String) async -> InsertionOutcome {
        guard !text.isEmpty else { return .inserted }
        guard await modifiersReleased() else {
            write(text)
            return .copiedToClipboard(.pasteFailed)
        }
        let saved = PasteboardSnapshot(of: pasteboard)
        let written = write(text)
        if let reason = postChord() { return .copiedToClipboard(reason) }
        do {
            try await sleep(PasteTiming.restoreDelay)
        } catch {
            return .copiedToClipboard(.pasteFailed)
        }
        // A newer write by anyone else wins over the old contents.
        if pasteboard.changeCount == written { saved.restore(to: pasteboard) }
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

    /// Waits for the modifier keys to come up. False when they stay down past the timeout or the wait is cancelled.
    private func modifiersReleased() async -> Bool {
        var waited = Duration.zero
        while keystrokes.modifiersHeld() {
            guard waited < PasteTiming.modifierTimeout else { return false }
            do {
                try await sleep(PasteTiming.modifierPollInterval)
            } catch {
                return false
            }
            waited += PasteTiming.modifierPollInterval
        }
        return true
    }

    /// Replaces the pasteboard contents with the text and returns the change count that this write produced.
    @discardableResult
    private func write(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }
}
