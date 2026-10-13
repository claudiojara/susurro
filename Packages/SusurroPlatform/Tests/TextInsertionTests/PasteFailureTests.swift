import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Paste failures", .timeLimit(.minutes(1)))
struct PasteFailureTests: PasteTestCase {
    let fixture = PasteFixture()

    /// A pasteboard that takes the first write, the promise, and refuses the second, the plain text.
    private func refuseTheFallback() -> (NSPasteboard, NSPasteboardItem) -> Bool {
        var writes = 0
        return { pasteboard, item in
            writes += 1
            return writes == 1 && pasteboard.writeObjects([item])
        }
    }

    // MARK: The old contents come back when the fallback is refused

    @Test("when the chord fails and the pasteboard refuses the plain text too, the old contents come back")
    func refusedFallbackAfterChordFailure() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster(postFailure: .eventCreationFailed)

        let outcome = await makeInserter(keys, writeItem: refuseTheFallback()).insert("hello world")

        #expect(outcome == .notInserted(.clipboardWriteFailed))
        #expect(contents() == before)
    }

    @Test("when no app reads the text and the pasteboard refuses the plain text, the old contents come back")
    func refusedFallbackAfterNoRead() async {
        putRichContent()
        let before = contents()

        let outcome = await makeInserter(writeItem: refuseTheFallback()).insert("hello world")

        #expect(outcome == .notInserted(.clipboardWriteFailed))
        #expect(contents() == before)
    }

    @Test("a plain text fallback that is accepted leaves the text, not the old contents")
    func acceptedFallbackLeavesTheText() async {
        putRichContent()
        let keys = FakeKeystrokePoster(postFailure: .eventCreationFailed)

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        expectMarkedTextLeft("hello world")
    }

    // MARK: Log events

    @Test("a paste that lands logs nothing")
    func quietWhenAllGoesWell() async {
        putRichContent()
        let log = RecordingDiagnostics()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)

        _ = await makeInserter(keys, diagnostics: log).insertAndSettle("hello world")

        #expect(log.events.isEmpty)
    }

    @Test("a modifier key that stays down is logged as the cause")
    func modifiersHeldIsLogged() async {
        let log = RecordingDiagnostics()

        _ = await makeInserter(FakeKeystrokePoster(modifiersHeldFor: 1_000), diagnostics: log).insert("hello world")

        #expect(log.events == [.pasteNotCompleted(cause: "modifiersHeld")])
    }

    @Test(
        "a chord that cannot be posted is logged with the reason",
        arguments: [
            (KeystrokeError.accessibilityNotGranted, "accessibilityMissing"),
            (.eventCreationFailed, "chordNotPosted"),
        ]
    )
    func chordFailureIsLogged(failure: KeystrokeError, cause: String) async {
        let log = RecordingDiagnostics()

        _ = await makeInserter(FakeKeystrokePoster(postFailure: failure), diagnostics: log).insert("hello world")

        #expect(log.events == [.pasteNotCompleted(cause: cause)])
    }

    @Test("a text that no app reads is logged as unread")
    func noReadIsLogged() async {
        let log = RecordingDiagnostics()

        _ = await makeInserter(diagnostics: log).insert("hello world")

        #expect(log.events == [.pasteNotCompleted(cause: "noRead")])
    }

    @Test("an earlier paste that never finishes is logged as the cause")
    func earlierPasteStuckIsLogged() async {
        let log = RecordingDiagnostics()
        let sut = makeInserter(diagnostics: log)
        let stuck = clock.suspendNextSleep()
        let first = Task { await sut.insert("one") }
        await stuck.entered.wait()

        _ = await sut.insert("two")
        stuck.release.open()
        _ = await first.value

        // The first one gives up on its own later, as unread.
        #expect(log.events == [.pasteNotCompleted(cause: "earlierPasteStuck"), .pasteNotCompleted(cause: "noRead")])
    }

    @Test("a write that the pasteboard refuses is logged")
    func refusedWriteIsLogged() async {
        putRichContent()
        let log = RecordingDiagnostics()

        _ = await makeInserter(diagnostics: log, writeItem: { _, _ in false }).insert("hello world")

        #expect(log.events == [.pasteboardWriteRefused])
    }

    @Test("a refused fallback is logged after the cause that led to it")
    func refusedFallbackIsLogged() async {
        putRichContent()
        let log = RecordingDiagnostics()
        let keys = FakeKeystrokePoster(postFailure: .eventCreationFailed)

        _ = await makeInserter(keys, diagnostics: log, writeItem: refuseTheFallback()).insert("hello world")

        #expect(log.events == [.pasteNotCompleted(cause: "chordNotPosted"), .pasteboardWriteRefused])
    }

    @Test("old contents that the pasteboard refuses to take back are logged")
    func refusedRestoreIsLogged() async {
        putRichContent()
        let log = RecordingDiagnostics()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)

        let outcome = await makeInserter(keys, diagnostics: log, restoreItems: { _, _ in false }).insertAndSettle("hi")

        #expect(outcome == .inserted)
        #expect(log.events == [.clipboardRestoreFailed])
    }
}
