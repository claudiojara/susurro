import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Read receipt", .timeLimit(.minutes(1)))
struct ReceiptTests: PasteTestCase {
    let fixture = PasteFixture()

    @Test("the text is promised under the markers, and it is provided only when an app reads it")
    func promisedUnderMarkers() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        var typesBeforeRead: Set<String> = []
        var itemCount = 0
        var source: String?
        var textWhenRead: String?
        keys.onPost = { [fixture] in
            typesBeforeRead = fixture.declaredTypes()
            itemCount = fixture.pasteboard.pasteboardItems?.count ?? 0
            source = fixture.pasteboard.pasteboardItems?.first?.string(
                forType: NSPasteboard.PasteboardType("org.nspasteboard.source")
            )
            textWhenRead = fixture.readAsApp()
        }

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(typesBeforeRead == Self.markerTypes.union(["public.utf8-plain-text"]))
        #expect(itemCount == 1)
        #expect(source == Self.sourceBundleID)
        #expect(textWhenRead == "hello world")
        #expect(outcome == .inserted)
    }

    @Test("the rich pasteboard stays replaced until an app has read the text")
    func restoredOnlyAfterTheRead() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var polls = 0
        var promisedWhilePolling: [Bool] = []
        onSleep = { [fixture] duration in
            guard duration == Self.receiptPollInterval else { return }
            polls += 1
            if polls < 5 {
                promisedWhilePolling.append(fixture.declaredTypes().contains("org.nspasteboard.TransientType"))
            } else {
                _ = fixture.readAsApp()  // the app reads on the fifth poll
            }
        }

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(promisedWhilePolling == [true, true, true, true])
        #expect(clock.elapsed == Self.minimumDwell)
        #expect(contents() == before)
    }

    @Test("the outcome comes at the first read, while the old pasteboard is still out, and the restore follows")
    func outcomeAtTheFirstRead() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)
        let sut = makeInserter(keys)
        let dwell = clock.suspendNextSleep()  // the first pause after the chord is the minimum dwell

        let outcome = await sut.insert("hello world")

        #expect(outcome == .inserted)
        #expect(clock.elapsed == .zero)
        #expect(isTextPromised())
        dwell.release.open()
        await sut.drain()
        #expect(clock.elapsed == Self.minimumDwell)
        #expect(contents() == before)
    }

    @Test("a late first read is the moment of the outcome, and the restore still waits for the minimum dwell")
    func outcomeAtALateFirstRead() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var polls = 0
        var dwell: SteppedClock.Suspension?
        onSleep = { [fixture, clock] _ in
            polls += 1
            guard polls == 5 else { return }
            _ = fixture.readAsApp()  // the app reads on the fifth poll
            dwell = clock.suspendNextSleep()  // the next pause is held, so the clock stops where the outcome is
        }
        let sut = makeInserter(keys)

        let outcome = await sut.insert("hello world")

        #expect(outcome == .inserted)
        #expect(clock.elapsed == Self.receiptPollInterval * 5)
        #expect(isTextPromised())
        dwell?.release.open()
        await sut.drain()
        #expect(clock.elapsed == Self.minimumDwell)
        #expect(contents() == before)
    }

    @Test("a pause that fails after the first read cuts the wait short, and the old pasteboard still comes back")
    func failingPauseAfterTheReadStillRestores() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)
        onSleep = { _ in throw CancellationError() }

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(sleeps == [Self.receiptPollInterval])
        #expect(contents() == before)
    }

    @Test("with no read for 8 seconds the marked text stays on the pasteboard, with no restore")
    func noReadTimesOut() async {
        putRichContent()
        let keys = FakeKeystrokePoster()

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == 1)
        #expect(sleeps.reduce(.zero, +) == Self.receiptTimeout)
        expectMarkedTextLeft("hello world")
    }

    @Test("a caller cancelled after the chord was posted still gets the paste finished and the pasteboard restored")
    func cancelledAfterTheChord() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var caller: Task<InsertionOutcome, Never>?
        keys.onPost = { [fixture] in
            _ = fixture.readAsApp()
            caller?.cancel()
        }
        let sut = makeInserter(keys)

        caller = Task { await sut.insert("hello world") }
        let outcome = await caller?.value
        await sut.drain()

        #expect(outcome == .inserted)
        #expect(completedSleeps.reduce(.zero, +) == Self.minimumDwell)
        #expect(contents() == before)
    }

    @Test("the old pasteboard is not restored before the minimum dwell after the chord")
    func noRestoreBeforeTheMinimumDwell() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)
        var promisedAtEveryPause: [Bool] = []
        onSleep = { [fixture] _ in
            promisedAtEveryPause.append(fixture.declaredTypes().contains("org.nspasteboard.TransientType"))
        }

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(promisedAtEveryPause == Array(repeating: true, count: 20))  // one pause per 50 ms, up to 1 s
        #expect(clock.elapsed == Self.minimumDwell)
        #expect(contents() == before)
    }

    @Test("the old pasteboard comes back 200 ms after the last read, when that is later than the minimum dwell")
    func quietPeriodAfterALateRead() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var pauses = 0
        onSleep = { [fixture] _ in
            pauses += 1
            if pauses == 19 { _ = fixture.readAsApp() }  // the app reads at 950 ms
        }

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(clock.elapsed == Duration.milliseconds(950) + Self.restoreDelay)
        #expect(contents() == before)
    }

    @Test("a read before the chord is not a receipt, so the paste counts as failed and the text is left")
    func readBeforeTheChordIsNotAReceipt() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        // A clipboard manager that ignores the markers reads the text as soon as it is written. The pasteboard then
        // serves every later read from its cache, so the app's own read cannot be seen either.
        let sut = makeInserter(
            keys,
            writeItem: { pasteboard, item in
                let accepted = pasteboard.writeObjects([item])
                _ = pasteboard.string(forType: .string)
                return accepted
            }
        )

        let outcome = await sut.insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == 1)
        #expect(clock.elapsed == Self.receiptTimeout)
        expectMarkedTextLeft("hello world")
    }

    @Test("a copy by the user while the paste waits for a read is not overwritten when the wait ends")
    func userCopyDuringTheWaitWinsOverTheFallback() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        var pauses = 0
        onSleep = { [pasteboard] _ in
            pauses += 1
            if pauses == 3 {
                pasteboard.clearContents()
                pasteboard.setString("user copy", forType: .string)
            }
        }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .notInserted(.clipboardChanged))  // the text is nowhere: not pasted, and not kept
        #expect(clock.elapsed == Self.receiptTimeout)
        #expect(pasteboardText == "user copy")
        #expect(contents().count == 1)
    }

    @Test("the wait for a read ends by the clock, not by the number of pauses")
    func receiptWaitFollowsTheClock() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        onSleep = { [clock] _ in clock.advance(by: .seconds(9)) }  // the main actor was busy for 9 s

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(sleeps == [Self.receiptPollInterval])
        expectMarkedTextLeft("hello world")
    }

    @Test("a pause that fails while waiting for a read ends the wait and leaves the text")
    func failingPauseEndsTheWaitForARead() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        onSleep = { _ in throw CancellationError() }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(sleeps == [Self.receiptPollInterval])
        expectMarkedTextLeft("hello world")
    }
}
