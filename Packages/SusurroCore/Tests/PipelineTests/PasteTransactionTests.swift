import CoreTestSupport
import Domain
import Foundation
import Testing

@MainActor
@Suite("Paste transaction", .timeLimit(.minutes(1)))
struct PasteTransactionTests {
    // MARK: Promise (5a.3)

    @Test("the text is published as a promise and supplied only when an app asks for it")
    func promiseIsLazy() async {
        let h = PasteHarness()
        var pendingWhenPosted = -1
        var textWhenRead: String?
        h.keys.onPost = { [pasteboard = h.pasteboard] in
            pendingWhenPosted = pasteboard.pendingPromiseCount
            textWhenRead = pasteboard.readAsApp()
        }

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(pendingWhenPosted == 1)
        #expect(textWhenRead == "hello world")
        #expect(h.calls.contains(.publishPromise("hello world")))
        #expect(!h.calls.contains(.writeConcrete("hello world")))
    }

    // MARK: Restore (5a.4)

    @Test("after a read and a quiet period a rich pasteboard, with every item and type, is back")
    func cleanRestore() async {
        let h = PasteHarness()
        h.appReadsOnPaste()

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
    }

    @Test("an empty pasteboard is empty again after the paste")
    func emptyPasteboardIsRestored() async {
        let h = PasteHarness(items: [])
        h.appReadsOnPaste()

        let outcome = await h.insertAndSettle("dictated")

        #expect(outcome == .inserted)
        #expect(h.pasteboard.content == .items([]))
    }

    @Test("the outcome comes at the first read, while the old pasteboard is still out, and the restore follows")
    func outcomeAtTheFirstRead() async {
        let h = PasteHarness()
        h.appReadsOnPaste()
        let dwell = h.clock.suspendNextSleep()  // the first pause after the chord is the wait for the quiet period

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .inserted)
        #expect(h.pasteboard.pendingPromiseCount == 0)
        #expect(!h.didRestore)
        dwell.release.open()
        await h.sut.drain()
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
    }

    @Test("a copy by the user during the quiet period means no restore")
    func userCopiedMeanwhile() async {
        let h = PasteHarness()
        h.appReadsOnPaste()
        h.onSleep { [pasteboard = h.pasteboard] _ in pasteboard.userCopies(text: "user copy") }

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(!h.didRestore)
        #expect(h.pasteboard.readAsApp() == "user copy")
    }

    @Test("the baseline is the change count right after the promise is published")
    func baselineIsTakenAfterPublishing() async throws {
        let h = PasteHarness()
        var countAtChord = -1
        h.keys.onPost = { [pasteboard = h.pasteboard] in
            countAtChord = pasteboard.changeCount
            _ = pasteboard.readAsApp()
        }

        _ = await h.insertAndSettle("hello world")

        // The count after our write is the baseline: the restore, which is the next write, is allowed by it.
        #expect(countAtChord == 1)
        #expect(h.didRestore)
    }

    @Test("another request for the data resets the quiet period")
    func anotherRequestResetsTheQuietTimer() async {
        let h = PasteHarness()
        h.appReadsOnPaste()
        // The minimum dwell ends at 1 s. A request at 950 ms makes the quiet period end at 1150 ms.
        h.onSleep { [clock = h.clock, pasteboard = h.pasteboard] _ in
            if clock.elapsed == .milliseconds(950) { pasteboard.requestFromProvider() }
        }

        _ = await h.insertAndSettle("hello world")

        #expect(h.clock.elapsed == .milliseconds(1_150))
        #expect(h.didRestore)
    }

    @Test("a snapshot with a gap is not put back, and the log says why")
    func snapshotWithAGap() async {
        let h = PasteHarness()
        h.pasteboard.snapshotGap = .typeWithoutData
        h.appReadsOnPaste()

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(!h.didRestore)
        #expect(h.diagnostics.events == [.clipboardNotRestored(reason: "typeWithoutData")])
    }

    @Test("a restore that the pasteboard refuses is logged")
    func refusedRestore() async {
        let h = PasteHarness()
        h.pasteboard.refusesRestore = true
        h.appReadsOnPaste()

        _ = await h.insertAndSettle("hello world")

        #expect(h.diagnostics.events == [.clipboardRestoreFailed])
    }

    // MARK: Safe chord (5a.5)

    @Test("with Option held after the release no chord is posted until it is let go")
    func modifierStillHeld() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(modifiersHeldFor: 3))
        h.appReadsOnPaste()

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(
            h.keys.calls == [.modifiersHeld, .modifiersHeld, .modifiersHeld, .modifiersHeld, .postPaste])
        #expect(Array(h.clock.sleeps.prefix(3)) == Array(repeating: PasteHarness.modifierPollInterval, count: 3))
    }

    @Test("a modifier that is never let go gives no chord and the failure path")
    func modifierNeverReleased() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(modifiersHeldFor: .max))

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.keys.postCount == 0)
        #expect(h.clock.sleeps.reduce(.zero, +) == PasteHarness.modifierTimeout)
        #expect(h.pasteboard.content == .concrete("hello world"))
        #expect(h.diagnostics.events == [.pasteNotCompleted(cause: "modifiersHeld")])
    }

    // MARK: Success detection (5a.6)

    @Test("a request for the data after the chord is a success, without waiting for the timeout")
    func targetReadsTheData() async {
        let h = PasteHarness()
        h.appReadsOnPaste()

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(h.clock.elapsed < PasteHarness.receiptTimeout)
    }

    @Test("with no read for 8 seconds the paste failed")
    func noReceipt() async {
        let h = PasteHarness()

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.keys.postCount == 1)
        #expect(h.clock.sleeps.reduce(.zero, +) == PasteHarness.receiptTimeout)
    }

    @Test("a read that comes just before the timeout is still a success")
    func lateReceipt() async {
        let h = PasteHarness()
        h.onSleep { [clock = h.clock, pasteboard = h.pasteboard] _ in
            if clock.elapsed == .milliseconds(7_950) { _ = pasteboard.readAsApp() }
        }

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
    }

    @Test("a chord that could not be posted shortens the wait for a read to 500 ms")
    func chordFailureShortensTheWait() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(postFailure: .eventCreationFailed))

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.clock.sleeps.reduce(.zero, +) == PasteHarness.chordFailureTimeout)
    }

    // MARK: Failure fallback (5a.7)

    @Test("without Accessibility the text stays on the pasteboard, with no restore, and the notice names it")
    func accessibilityMissing() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(postFailure: .accessibilityNotGranted))

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.accessibilityMissing))
        #expect(h.pasteboard.content == .concrete("hello world"))
        #expect(!h.didRestore)
        #expect(h.diagnostics.events == [.pasteNotCompleted(cause: "accessibilityMissing")])
    }

    @Test("a chord that fails for another reason gives the text-on-clipboard notice")
    func genericFailure() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(postFailure: .eventCreationFailed))

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.pasteboard.content == .concrete("hello world"))
        #expect(!h.didRestore)
    }

    // MARK: A failed paste replaces the promise (5a.8)

    enum Failing: CaseIterable, CustomTestStringConvertible {
        case noReceipt
        case chordNotPosted
        case modifierTimeout

        var testDescription: String {
            switch self {
            case .noReceipt: "the 8 s timeout"
            case .chordNotPosted: "a chord-post failure"
            case .modifierTimeout: "a modifier timeout"
            }
        }

        @MainActor
        func harness() -> PasteHarness {
            switch self {
            case .noReceipt: PasteHarness()
            case .chordNotPosted: PasteHarness(keys: FakeKeystrokePoster(postFailure: .eventCreationFailed))
            case .modifierTimeout: PasteHarness(keys: FakeKeystrokePoster(modifiersHeldFor: .max))
            }
        }
    }

    @Test(
        "a failed paste leaves the concrete text, not the promise, and schedules no restore",
        arguments: Failing.allCases)
    func failedPasteReplacesThePromise(failing: Failing) async {
        let h = failing.harness()
        let before = h.pasteboard.changeCount

        let outcome = await h.sut.insert("hello world")
        await h.sut.drain()

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.calls.contains(.writeConcrete("hello world")))
        #expect(h.pasteboard.pendingPromiseCount == 0)
        #expect(h.pasteboard.content == .concrete("hello world"))
        #expect(h.pasteboard.changeCount > before)
        #expect(!h.didRestore)
    }

    @Test("a late request on the abandoned promise changes neither the result nor the pasteboard")
    func lateRequestOnTheAbandonedPromise() async {
        let h = PasteHarness()

        let outcome = await h.sut.insert("hello world")
        h.pasteboard.requestFromAbandonedPromise()
        await h.sut.drain()

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.pasteboard.content == .concrete("hello world"))
        #expect(!h.didRestore)
    }

    @Test("a copy by the user while the paste waited wins, and the text is nowhere")
    func userCopyDuringTheWait() async {
        let h = PasteHarness()
        h.onSleep { [pasteboard = h.pasteboard] _ in pasteboard.userCopies(text: "user copy") }

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .notInserted(.clipboardChanged))
        #expect(h.pasteboard.readAsApp() == "user copy")
        #expect(!h.calls.contains(.writeConcrete("hello world")))
    }

    @Test("a promise that the pasteboard refuses posts no chord and gives the old contents back")
    func refusedPromise() async {
        let h = PasteHarness()
        h.pasteboard.refusesPublish = true

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .notInserted(.clipboardWriteFailed))
        #expect(h.keys.postCount == 0)
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
        #expect(h.diagnostics.events == [.pasteboardWriteRefused])
    }

    @Test("when the chord fails and the pasteboard refuses the plain text too, the outcome says it is nowhere")
    func refusedFallback() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(postFailure: .eventCreationFailed))
        h.pasteboard.refusesConcrete = true

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .notInserted(.clipboardWriteFailed))
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
    }

    // MARK: Target verification (5a.9)

    @Test("a different app in front than at the start of the dictation gets no chord and the text on the clipboard")
    func appSwitched() async {
        let h = PasteHarness(frontmost: .slack)

        let outcome = await h.sut.insert("hello world", into: .mail)

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.keys.postCount == 0)
        #expect(h.pasteboard.content == .concrete("hello world"))
        #expect(!h.didRestore)
        #expect(h.diagnostics.events == [.pasteNotCompleted(cause: "targetChanged")])
    }

    @Test("with no app in front the target cannot be confirmed, so the text goes to the clipboard")
    func noAppInFront() async {
        let h = PasteHarness(frontmost: nil)

        let outcome = await h.sut.insert("hello world", into: .mail)

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.keys.postCount == 0)
    }

    @Test("the same app in front pastes as usual")
    func sameApp() async {
        let h = PasteHarness(frontmost: .mail)
        h.appReadsOnPaste()

        let outcome = await h.insertAndSettle("hello world", into: .mail)

        #expect(outcome == .inserted)
        #expect(h.keys.postCount == 1)
    }

    @Test("with no target nothing is compared")
    func noTarget() async {
        let h = PasteHarness(frontmost: .slack)
        h.appReadsOnPaste()

        let outcome = await h.insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(h.frontmost.reads == 0)
    }

    // MARK: Ordering and empty text (5a.10)

    @Test("empty text makes no pasteboard calls and leaves the change count alone")
    func emptyText() async {
        let h = PasteHarness()

        let outcome = await h.sut.insert("")

        #expect(outcome == .inserted)
        #expect(h.calls.isEmpty)
        #expect(h.pasteboard.changeCount == 0)
        #expect(h.keys.calls.isEmpty)
        #expect(h.clock.sleeps.isEmpty)
    }

    @Test("two submissions run one at a time, in the order they were submitted")
    func serialInSubmissionOrder() async {
        let h = PasteHarness()
        h.appReadsOnPaste()

        async let first = h.sut.insert("one")
        async let second = h.sut.insert("two")
        let outcomes = await [first, second]
        await h.sut.drain()

        #expect(outcomes == [.inserted, .inserted])
        #expect(
            h.calls == [
                .snapshot, .publishPromise("one"), .restore,
                .snapshot, .publishPromise("two"), .restore,
            ])
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
    }

    // MARK: Cancellation and termination

    @Test("a caller cancelled after the chord was posted still gets the paste finished and the pasteboard restored")
    func cancelledAfterTheChord() async {
        let h = PasteHarness()
        var caller: Task<InsertionOutcome, Never>?
        h.keys.onPost = { [pasteboard = h.pasteboard] in
            _ = pasteboard.readAsApp()
            caller?.cancel()
        }

        caller = Task { await h.sut.insert("hello world") }
        let outcome = await caller?.value
        await h.sut.drain()

        #expect(outcome == .inserted)
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
    }

    @Test("a caller cancelled before the chord leaves the pasteboard as it was")
    func cancelledBeforeTheChord() async {
        let h = PasteHarness(keys: FakeKeystrokePoster(modifiersHeldFor: .max))
        h.onSleep { _ in throw CancellationError() }

        let outcome = await h.sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(h.keys.postCount == 0)
        #expect(h.calls.isEmpty)
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
    }

    @Test("termination puts the old pasteboard back at once, and only when the text is still ours")
    func restoreForTermination() async {
        let h = PasteHarness()
        h.appReadsOnPaste()
        let dwell = h.clock.suspendNextSleep()

        let outcome = await h.sut.insert("hello world")
        h.sut.restoreForTermination()

        #expect(outcome == .inserted)
        #expect(h.pasteboard.content == .items(PasteHarness.richItems))
        #expect(h.diagnostics.events == [.clipboardRestoreAtTermination(restored: true)])
        dwell.release.open()
        await h.sut.drain()
        #expect(h.calls.filter { $0 == .restore }.count == 1)
    }

    @Test("termination with nothing under way restores nothing")
    func terminationWithNothingToRestore() {
        let h = PasteHarness()

        h.sut.restoreForTermination()

        #expect(h.calls.isEmpty)
        #expect(h.diagnostics.events == [.clipboardRestoreAtTermination(restored: false)])
    }
}
