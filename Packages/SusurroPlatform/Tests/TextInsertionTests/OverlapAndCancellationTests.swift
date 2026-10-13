import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Overlap and cancellation", .timeLimit(.minutes(1)))
struct OverlapAndCancellationTests: PasteTestCase {
    let fixture = PasteFixture()

    @Test(
        "a second insertion started while the first waits for its read does not take the first text for the pasteboard")
    func secondInsertionWaitsForTheFirst() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        var textsWhenPosted: [String?] = []
        var postedAt: [Duration] = []
        keys.onPost = { [fixture, clock] in
            textsWhenPosted.append(fixture.readAsApp())
            postedAt.append(clock.elapsed)
        }
        let sut = makeInserter(keys)
        var second: Task<InsertionOutcome, Never>?
        onSleep = { _ in
            if second == nil { second = Task { await sut.insert("two") } }  // the first is still waiting out its dwell
        }

        let first = await sut.insert("one")
        await sut.drain()  // by now the first has waited out its dwell, so the hook has started the second
        let secondOutcome = await second?.value
        await sut.drain()

        #expect([first, secondOutcome] == [.inserted, .inserted])
        #expect(textsWhenPosted == ["one", "two"])
        #expect(postedAt.last.map { $0 < .seconds(2) } == true)  // the second goes ahead as soon as the first is done
        #expect(contents() == before)
    }

    @Test("a second insertion does not wait for ever for a first one that is stuck, and leaves its text instead")
    func waitForTheFirstIsBounded() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        let sut = makeInserter(keys)
        let stuck = clock.suspendNextSleep()

        let first = Task { await sut.insert("one") }
        await stuck.entered.wait()
        let secondOutcome = await sut.insert("two")
        let waited = clock.elapsed
        stuck.release.open()
        _ = await first.value

        #expect(secondOutcome == .copiedToClipboard(.pasteFailed))
        #expect(waited == Self.overlapWait)
        #expect(keys.postCount == 1)  // the second posts no chord, and its snapshot would have been the first's text
        expectMarkedTextLeft("two")
    }

    @Test("a second insertion whose pause fails while it waits for the first leaves its text instead of pasting")
    func failingPauseEndsTheWaitForTheFirst() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        let sut = makeInserter(keys)
        let stuck = clock.suspendNextSleep()
        let first = Task { await sut.insert("one") }
        await stuck.entered.wait()
        onSleep = { _ in throw CancellationError() }

        let secondOutcome = await sut.insert("two")
        stuck.release.open()
        _ = await first.value

        #expect(secondOutcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == 1)
        #expect(sleeps == [Self.receiptPollInterval, Self.receiptPollInterval])
        expectMarkedTextLeft("two")
    }

    @Test("a caller cancelled while it waits for the first insertion writes nothing")
    func cancelledWhileWaitingForTheFirst() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        let sut = makeInserter(keys)
        let stuck = clock.suspendNextSleep()
        let first = Task { await sut.insert("one") }
        await stuck.entered.wait()
        let changeCount = pasteboard.changeCount
        var caller: Task<InsertionOutcome, Never>?
        onSleep = { _ in caller?.cancel() }  // the next pause then throws, as a cancelled sleep does

        caller = Task { await sut.insert("two") }
        let outcome = await caller?.value
        let changeCountAfter = pasteboard.changeCount
        stuck.release.open()
        _ = await first.value

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(changeCountAfter == changeCount)
        #expect(keys.postCount == 1)
        expectMarkedTextLeft("one")  // the first gave up on its own, and the cancelled caller never wrote "two"
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
}
