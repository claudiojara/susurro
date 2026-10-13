import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Modifier wait", .timeLimit(.minutes(1)))
struct ModifierWaitTests: PasteTestCase {
    let fixture = PasteFixture()

    /// When a modifier that is held is let go, in terms of the polls the inserter is allowed.
    enum Release {
        case onePollLate
        case never
    }

    @Test("a modifier still held is waited for, polling at a fixed interval, before the chord")
    func waitsForModifiers() async {
        let keys = FakeKeystrokePoster(modifiersHeldFor: 3)
        appReadsOnPaste(keys)

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

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

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(seenDuringWait == Array(repeating: before, count: 3))
        #expect(changeCountsDuringWait == Array(repeating: changeCount, count: 3))
        #expect(contents() == before)
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

    @Test("the wait for modifiers ends by the clock, not by the number of pauses")
    func modifierWaitFollowsTheClock() async {
        putRichContent()
        let keys = FakeKeystrokePoster(modifiersHeldFor: 1_000)
        onSleep = { [clock] _ in clock.advance(by: .seconds(2)) }  // the main actor was busy for 2 s

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(sleeps == [Self.modifierPollInterval])
        #expect(keys.postCount == 0)
        expectMarkedTextLeft("hello world")
    }

    private var allowedPolls: Int { Int(Self.modifierTimeout / Self.modifierPollInterval) }

    @Test("modifiers released at the last poll still paste")
    func releasedAtTheLastPoll() async {
        putRichContent()
        let keys = FakeKeystrokePoster(modifiersHeldFor: allowedPolls)
        appReadsOnPaste(keys)

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(keys.postCount == 1)
        #expect(clock.elapsed == Self.modifierTimeout + Self.minimumDwell)
        #expect(contents().count == 2)
    }

    @Test(
        "modifiers still held after 500 ms: no chord is posted and the marked text stays",
        arguments: [Release.onePollLate, .never]
    )
    func heldPastTheTimeout(release: Release) async {
        putRichContent()
        let keys = FakeKeystrokePoster(modifiersHeldFor: release == .onePollLate ? allowedPolls + 1 : allowedPolls * 10)
        appReadsOnPaste(keys)

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == 0)
        #expect(clock.elapsed == Self.modifierTimeout)
        expectMarkedTextLeft("hello world")
    }
}
