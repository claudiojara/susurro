import CoreTestSupport
import Domain
import Foundation
import Pipeline

/// A paste transaction wired to fakes, with a clock that runs through its sleeps. The suites of the paste share it.
@MainActor
struct PasteHarness {
    let pasteboard: FakePasteboard
    let keys: FakeKeystrokePoster
    let frontmost: FakeFrontmostAppProvider
    let clock = SteppedClock()
    let diagnostics = RecordingDiagnostics()
    let sut: PasteTransaction

    // The timings, spelled out once. The quiet period (200 ms) and the receipt timeout (8 s) are the spec's; the
    // others come from the tasks and the reviews. They are not read from `PasteTiming`, so changing a constant there
    // fails these tests.
    static let restoreDelay = Duration.milliseconds(200)
    static let minimumDwell = Duration.seconds(1)
    static let modifierTimeout = Duration.milliseconds(500)
    static let receiptTimeout = Duration.seconds(8)
    static let chordFailureTimeout = Duration.milliseconds(500)
    static let receiptPollInterval = Duration.milliseconds(50)
    static let modifierPollInterval = Duration.milliseconds(20)

    static let rtf = Data("{\\rtf1 rich}".utf8)
    static let png = Data([0x89, 0x50, 0x4E, 0x47])

    /// Two items, as a copied rich selection leaves them: text with RTF and an image, and a second text.
    static var richItems: [[PasteboardEntry]] {
        [
            [
                PasteboardEntry(type: FakePasteboard.textType, data: Data("alpha".utf8)),
                PasteboardEntry(type: "public.rtf", data: rtf),
                PasteboardEntry(type: "public.png", data: png),
            ],
            [PasteboardEntry(type: FakePasteboard.textType, data: Data("beta".utf8))],
        ]
    }

    init(
        items: [[PasteboardEntry]] = richItems,
        keys: FakeKeystrokePoster = FakeKeystrokePoster(),
        frontmost: AppIdentity? = .mail
    ) {
        pasteboard = FakePasteboard(items: items)
        self.keys = keys
        self.frontmost = FakeFrontmostAppProvider(frontmost)
        sut = PasteTransaction(
            pasteboard: pasteboard, keystrokes: keys, frontmost: self.frontmost, clock: clock, diagnostics: diagnostics)
    }

    /// A target app that reads the text as soon as it receives the chord.
    func appReadsOnPaste() {
        keys.onPost = { [pasteboard] in _ = pasteboard.readAsApp() }
    }

    /// Runs when the transaction pauses, standing in for whatever happens meanwhile.
    func onSleep(_ hook: @escaping SteppedClock.SleepHook) {
        clock.setHook(hook)
    }

    /// Inserts, then waits for the paste to finish. `insert` returns at the first read of the text, before the old
    /// pasteboard is back, so a test that checks the final pasteboard goes through this.
    func insertAndSettle(_ text: String, into target: AppIdentity? = nil) async -> InsertionOutcome {
        let outcome = await sut.insert(text, into: target)
        await sut.drain()
        return outcome
    }

    var calls: [FakePasteboard.Call] { pasteboard.calls }
    var didRestore: Bool { calls.contains(.restore) }
}
