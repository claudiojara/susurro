import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Restore at termination", .timeLimit(.minutes(1)))
struct TerminationRestoreTests: PasteTestCase {
    let fixture = PasteFixture()

    @Test("terminating while a paste waits for its read gives the old contents back at once")
    func duringTheWaitForARead() async {
        putRichContent()
        let before = contents()
        let sut = makeInserter()  // no app reads the text
        let stuck = clock.suspendNextSleep()
        let paste = Task { await sut.insert("hello world") }
        await stuck.entered.wait()
        let promisedBefore = isTextPromised()

        sut.restoreForTermination()
        let after = contents()
        stuck.release.open()
        _ = await paste.value
        await sut.drain()

        #expect(promisedBefore)
        #expect(after == before)
        #expect(contents() == before)  // the paste that was cut short does not write again
    }

    @Test("terminating during the quiet period after a read gives the old contents back without waiting for it")
    func duringTheQuietPeriod() async {
        putRichContent()
        let before = contents()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)
        let sut = makeInserter(keys)
        let stuck = clock.suspendNextSleep()  // holds the first pause of the restore task

        let outcome = await sut.insert("hello world")
        await stuck.entered.wait()
        let promisedBefore = isTextPromised()
        sut.restoreForTermination()
        let after = contents()
        let changeCountAfter = pasteboard.changeCount
        stuck.release.open()
        await sut.drain()

        #expect(outcome == .inserted)
        #expect(promisedBefore)
        #expect(after == before)
        #expect(pasteboard.changeCount == changeCountAfter)  // the restore task finds nothing left to do
    }

    @Test("terminating with no paste waiting leaves the pasteboard alone")
    func nothingWaiting() async {
        putRichContent()
        let before = contents()
        let changeCount = pasteboard.changeCount
        let sut = makeInserter()

        sut.restoreForTermination()

        #expect(pasteboard.changeCount == changeCount)
        #expect(contents() == before)
    }

    @Test("terminating after a paste has finished leaves the pasteboard alone")
    func afterAFinishedPaste() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)
        let sut = makeInserter(keys)
        _ = await sut.insertAndSettle("hello world")
        let changeCount = pasteboard.changeCount

        sut.restoreForTermination()

        #expect(pasteboard.changeCount == changeCount)
    }

    @Test("terminating leaves a copy the user made while the paste waited")
    func userCopyWins() async {
        putRichContent()
        let sut = makeInserter()
        let stuck = clock.suspendNextSleep()
        let paste = Task { await sut.insert("hello world") }
        await stuck.entered.wait()
        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)

        sut.restoreForTermination()
        stuck.release.open()
        _ = await paste.value

        #expect(pasteboardText == "user copy")
    }

    @Test("a text left on the clipboard on purpose stays there")
    func leftTextStays() async {
        putRichContent()
        let sut = makeInserter(FakeKeystrokePoster(postFailure: .eventCreationFailed))
        _ = await sut.insert("hello world")

        sut.restoreForTermination()

        expectMarkedTextLeft("hello world")
    }
}
