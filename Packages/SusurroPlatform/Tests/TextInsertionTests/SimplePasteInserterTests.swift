import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Simple paste inserter", .timeLimit(.minutes(1)))
struct SimplePasteInserterTests: PasteTestCase {
    let fixture = PasteFixture()

    @Test("the text is on the pasteboard when the chord is posted, and the rich pasteboard is back after 300 ms")
    func pastesAndRestores() async throws {
        putRichContent()
        let before = contents()
        let first = try #require(before.first)
        #expect(before.count == 2)
        #expect(first.first { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }?.data == Self.rtf)
        #expect(first.first { $0.type == NSPasteboard.PasteboardType.png.rawValue }?.data == Self.png)
        let keys = FakeKeystrokePoster()
        var textWhenPosted: String?
        var textDuringDelay: String?
        keys.onPost = { [pasteboard] in textWhenPosted = pasteboard.string(forType: .string) }
        onSleep = { [pasteboard] _ in textDuringDelay = pasteboard.string(forType: .string) }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .inserted)
        #expect(textWhenPosted == "hello world")
        #expect(textDuringDelay == "hello world")
        #expect(clock.elapsed == Self.minimumDwell)
        #expect(keys.postCount == 1)
        #expect(contents() == before)
    }

    @Test("an empty pasteboard is empty again after the paste")
    func emptyPasteboardIsRestored() async {
        pasteboard.clearContents()
        let keys = FakeKeystrokePoster()
        var textWhenPosted: String?
        keys.onPost = { [pasteboard] in textWhenPosted = pasteboard.string(forType: .string) }

        let outcome = await makeInserter(keys).insert("dictated")

        #expect(outcome == .inserted)
        #expect(textWhenPosted == "dictated")
        #expect(pasteboardText == nil)
        #expect(contents().isEmpty)
    }

    @Test("a copy by the user after the read is not overwritten")
    func userCopyWins() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)
        onSleep = { [pasteboard] _ in
            pasteboard.clearContents()
            pasteboard.setString("user copy", forType: .string)
        }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .inserted)
        #expect(pasteboardText == "user copy")
        #expect(contents().count == 1)
    }

    @Test("two dictations in a row each restore the original pasteboard")
    func sequentialInsertions() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var texts: [String?] = []
        keys.onPost = { [pasteboard] in texts.append(pasteboard.string(forType: .string)) }
        let sut = makeInserter(keys)

        let first = await sut.insert("one")
        let afterFirst = contents()
        let second = await sut.insert("two")

        #expect([first, second] == [.inserted, .inserted])
        #expect(texts == ["one", "two"])
        #expect(afterFirst == before)
        #expect(contents() == before)
    }

    @Test("empty text leaves the pasteboard and its change count alone")
    func emptyText() async {
        putRichContent()
        let before = contents()
        let changeCount = pasteboard.changeCount
        let keys = FakeKeystrokePoster()

        let outcome = await makeInserter(keys).insert("")

        #expect(outcome == .inserted)
        #expect(pasteboard.changeCount == changeCount)
        #expect(contents() == before)
        #expect(keys.calls.isEmpty)
        #expect(sleeps.isEmpty)
    }

    @Test(
        "when the chord cannot be posted the marked text stays on the pasteboard, with no restore",
        arguments: [
            (KeystrokeError.accessibilityNotGranted, InsertionOutcome.copiedToClipboard(.accessibilityMissing)),
            (.eventCreationFailed, .copiedToClipboard(.pasteFailed)),
        ]
    )
    func chordNotPosted(failure: KeystrokeError, expected: InsertionOutcome) async {
        putRichContent()
        let keys = FakeKeystrokePoster(postFailure: failure)

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == expected)
        #expect(pasteboardText == "hello world")
        #expect(contents().count == 1)
        #expect(declaredTypes().isSuperset(of: Self.markerTypes))
        #expect(sleeps.isEmpty)
    }

    @Test("a modifier still held is waited for, polling at a fixed interval, before the chord")
    func waitsForModifiers() async {
        let keys = FakeKeystrokePoster(modifiersHeldFor: 3)
        appReadsOnPaste(keys)

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .inserted)
        #expect(keys.calls == [.modifiersHeld, .modifiersHeld, .modifiersHeld, .modifiersHeld, .postPaste])
        #expect(Array(sleeps.prefix(3)) == Array(repeating: Self.modifierPollInterval, count: 3))
        #expect(clock.elapsed == Self.modifierPollInterval * 3 + Self.minimumDwell)
    }

    @Test("while a modifier is held the user's pasteboard is untouched, and it is back at the end")
    func pasteboardUntouchedWhileWaiting() async {
        putRichContent()
        let before = contents()
        let changeCount = pasteboard.changeCount
        let keys = FakeKeystrokePoster(modifiersHeldFor: 3)
        appReadsOnPaste(keys)
        var seenDuringWait: [[[Entry]]] = []
        var changeCountsDuringWait: [Int] = []
        onSleep = { [fixture] duration in
            guard duration == Self.modifierPollInterval else { return }
            seenDuringWait.append(fixture.contents())
            changeCountsDuringWait.append(fixture.pasteboard.changeCount)
        }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .inserted)
        #expect(seenDuringWait == Array(repeating: before, count: 3))
        #expect(changeCountsDuringWait == Array(repeating: changeCount, count: 3))
        #expect(contents() == before)
    }

    /// When a modifier that is held is let go, in terms of the polls the inserter is allowed.
    enum Release {
        case atLastPoll
        case onePollLate
        case never
    }

    @Test(
        "modifiers are waited for up to 500 ms; past that no chord is posted and the marked text stays",
        arguments: [Release.atLastPoll, .onePollLate, .never]
    )
    func modifiersTimeout(release: Release) async {
        putRichContent()
        let allowedPolls = Int(Self.modifierTimeout / Self.modifierPollInterval)
        let heldFor =
            switch release {
            case .atLastPoll: allowedPolls
            case .onePollLate: allowedPolls + 1
            case .never: allowedPolls * 10
            }
        let keys = FakeKeystrokePoster(modifiersHeldFor: heldFor)
        appReadsOnPaste(keys)

        let outcome = await makeInserter(keys).insert("hello world")

        let waited = sleeps.filter { $0 == Self.modifierPollInterval }.reduce(.zero, +)
        #expect(waited == Self.modifierTimeout)
        if release == .atLastPoll {
            #expect(keys.postCount == 1)
            #expect(outcome == .inserted)
            #expect(clock.elapsed == Self.modifierTimeout + Self.minimumDwell)
            #expect(contents().count == 2)
        } else {
            #expect(keys.postCount == 0)
            #expect(outcome == .copiedToClipboard(.pasteFailed))
            #expect(pasteboardText == "hello world")
            #expect(contents().count == 1)
            #expect(declaredTypes().isSuperset(of: Self.markerTypes))
            #expect(clock.elapsed == Self.modifierTimeout)
        }
    }

    @Test("a wait for modifiers that is cancelled writes nothing and posts no chord", arguments: [1, 3])
    func cancelledWhileWaitingForModifiers(cancelledPoll: Int) async {
        putRichContent()
        let before = contents()
        let changeCount = pasteboard.changeCount
        let keys = FakeKeystrokePoster(modifiersHeldFor: 5)
        var polls = 0
        onSleep = { _ in
            polls += 1
            if polls == cancelledPoll { throw CancellationError() }
        }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(polls == cancelledPoll)
        #expect(keys.postCount == 0)
        #expect(pasteboard.changeCount == changeCount)
        #expect(contents() == before)
    }

    @Test("a write that the pasteboard refuses posts no chord and gives the old contents back")
    func refusedWrite() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()

        let outcome = await makeInserter(keys, writeItem: { _, _ in false }).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == 0)
        #expect(contents() == before)
    }

    @Test(
        "a second insertion started while the first waits for its read does not take the first text for the pasteboard")
    func secondInsertionWaitsForTheFirst() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var textsWhenPosted: [String?] = []
        var postedAt: [Duration] = []
        keys.onPost = { [pasteboard, clock] in
            textsWhenPosted.append(pasteboard.string(forType: .string))
            postedAt.append(clock.elapsed)
        }
        let sut = makeInserter(keys)
        var second: Task<InsertionOutcome, Never>?
        onSleep = { _ in
            if second == nil { second = Task { await sut.insert("two") } }  // the first is still waiting out its dwell
        }

        let first = await sut.insert("one")
        let secondOutcome = await second?.value

        #expect([first, secondOutcome] == [.inserted, .inserted])
        #expect(textsWhenPosted == ["one", "two"])
        #expect(postedAt.last.map { $0 < .seconds(2) } == true)  // the second goes ahead as soon as the first is done
        #expect(contents() == before)
    }

    @Test("a second insertion does not wait for ever for a first one that is stuck")
    func waitForTheFirstIsBounded() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        var postedAt: [Duration] = []
        keys.onPost = { [clock] in postedAt.append(clock.elapsed) }
        let sut = makeInserter(keys)
        let stuck = clock.suspendNextSleep()

        let first = Task { await sut.insert("one") }
        await stuck.entered.wait()
        let secondOutcome = await sut.insert("two")
        stuck.release.open()
        _ = await first.value

        #expect(secondOutcome == .copiedToClipboard(.pasteFailed))
        #expect(postedAt.count == 2)
        #expect(postedAt.last.map { $0 >= Self.modifierTimeout + Self.receiptTimeout + Self.restoreDelay } == true)
    }

    @Test("a caller cancelled once the modifiers are up writes nothing")
    func cancelledBeforeTheWrite() async {
        putRichContent()
        let before = contents()
        let changeCount = pasteboard.changeCount
        let keys = FakeKeystrokePoster(modifiersHeldFor: 1)
        let sut = makeInserter(keys)
        var caller: Task<InsertionOutcome, Never>?
        onSleep = { _ in caller?.cancel() }  // the wait itself is not cut short, the task is only marked as cancelled

        caller = Task { await sut.insert("hello world") }
        let outcome = await caller?.value

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == 0)
        #expect(pasteboard.changeCount == changeCount)
        #expect(contents() == before)
    }

    @Test("a caller cancelled after the write posts no chord and gives the old contents back")
    func cancelledBeforeTheChord() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var caller: Task<InsertionOutcome, Never>?
        let sut = makeInserter(
            keys,
            writeItem: { pasteboard, item in
                let accepted = pasteboard.writeObjects([item])
                caller?.cancel()
                return accepted
            }
        )

        caller = Task { await sut.insert("hello world") }
        let outcome = await caller?.value

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == 0)
        #expect(contents() == before)
    }

    @Test("the wait for modifiers ends by the clock, not by the number of pauses")
    func modifierWaitFollowsTheClock() async {
        putRichContent()
        let keys = FakeKeystrokePoster(modifiersHeldFor: 1_000)
        onSleep = { [clock] _ in clock.advance(by: .seconds(2)) }  // the main actor was busy for 2 s

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(sleeps == [Self.modifierPollInterval])
        #expect(keys.postCount == 0)
        #expect(pasteboardText == "hello world")
    }
}
