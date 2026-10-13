import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Paste and restore", .timeLimit(.minutes(1)))
struct PasteRestoreTests: PasteTestCase {
    let fixture = PasteFixture()

    @Test("the text is on the pasteboard when the chord is posted")
    func textIsOnThePasteboardWhenTheChordIsPosted() async {
        putRichContent()
        let keys = FakeKeystrokePoster()
        var textWhenPosted: String?
        keys.onPost = { [fixture] in textWhenPosted = fixture.readAsApp() }

        _ = await makeInserter(keys).insertAndSettle("hello world")

        #expect(textWhenPosted == "hello world")
        #expect(keys.postCount == 1)
    }

    @Test("a rich pasteboard, with every item and type, is back after the paste")
    func richPasteboardIsBackAfterThePaste() async throws {
        putRichContent()
        let before = contents()
        let first = try #require(before.first)
        #expect(before.count == 2)
        #expect(first.first { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }?.data == Self.rtf)
        #expect(first.first { $0.type == NSPasteboard.PasteboardType.png.rawValue }?.data == Self.png)
        let keys = FakeKeystrokePoster()
        appReadsOnPaste(keys)

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

        #expect(outcome == .inserted)
        #expect(contents() == before)
    }

    @Test("an empty pasteboard is empty again after the paste")
    func emptyPasteboardIsRestored() async {
        pasteboard.clearContents()
        let keys = FakeKeystrokePoster()
        var textWhenPosted: String?
        keys.onPost = { [fixture] in textWhenPosted = fixture.readAsApp() }

        let outcome = await makeInserter(keys).insertAndSettle("dictated")

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

        let outcome = await makeInserter(keys).insertAndSettle("hello world")

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
        keys.onPost = { [fixture] in texts.append(fixture.readAsApp()) }
        let sut = makeInserter(keys)

        let first = await sut.insertAndSettle("one")
        let afterFirst = contents()
        let second = await sut.insertAndSettle("two")

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
        expectMarkedTextLeft("hello world")
        #expect(sleeps.isEmpty)
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
}
