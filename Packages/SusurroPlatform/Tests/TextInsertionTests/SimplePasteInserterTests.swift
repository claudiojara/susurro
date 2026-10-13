import AppKit
import CoreTestSupport
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Simple paste inserter", .timeLimit(.minutes(1)))
final class SimplePasteInserterTests {
    private static let restoreDelay = Duration.milliseconds(300)
    private static let modifierTimeout = Duration.milliseconds(500)
    private static let rtf = Data("{\\rtf1 rich}".utf8)
    private static let png = Data([0x89, 0x50, 0x4E, 0x47])

    /// A pasteboard of its own, so the tests never touch the user's clipboard.
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("susurro-test-\(UUID().uuidString)"))
    /// Every pause the inserter asked for, in order.
    private var sleeps: [Duration] = []
    /// Runs when the inserter pauses, standing in for whatever happens meanwhile. It may throw to cancel the pause.
    private var onSleep: (Duration) throws -> Void = { _ in }

    isolated deinit {
        pasteboard.releaseGlobally()
    }

    private func makeInserter(_ keys: FakeKeystrokePoster = FakeKeystrokePoster()) -> SimplePasteInserter {
        SimplePasteInserter(
            pasteboard: pasteboard,
            keystrokes: keys,
            sleep: { [unowned self] duration in
                sleeps.append(duration)
                try onSleep(duration)
            }
        )
    }

    /// Two items, as a copied rich selection leaves them: text with RTF and an image, and a second text.
    private func putRichContent() {
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("alpha", forType: .string)
        first.setData(Self.rtf, forType: .rtf)
        first.setData(Self.png, forType: .png)
        let second = NSPasteboardItem()
        second.setString("beta", forType: .string)
        _ = pasteboard.writeObjects([first, second])
    }

    /// Every item with the data of each of its types.
    private func contents() -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { result, type in result[type.rawValue] = item.data(forType: type) }
        }
    }

    private var pasteboardText: String? { pasteboard.string(forType: .string) }

    // MARK: Paste and restore

    @Test("the text is on the pasteboard when the chord is posted, and the rich pasteboard is back after 300 ms")
    func pastesAndRestores() async throws {
        putRichContent()
        let before = contents()
        let first = try #require(before.first)
        #expect(before.count == 2)
        #expect(first[NSPasteboard.PasteboardType.rtf.rawValue] == Self.rtf)
        #expect(first[NSPasteboard.PasteboardType.png.rawValue] == Self.png)
        let keys = FakeKeystrokePoster()
        var textWhenPosted: String?
        var textDuringDelay: String?
        keys.onPost = { [pasteboard] in textWhenPosted = pasteboard.string(forType: .string) }
        onSleep = { [pasteboard] _ in textDuringDelay = pasteboard.string(forType: .string) }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .inserted)
        #expect(textWhenPosted == "hello world")
        #expect(textDuringDelay == "hello world")
        #expect(sleeps == [Self.restoreDelay])
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

    @Test("a copy by the user during the delay is not overwritten")
    func userCopyWins() async {
        putRichContent()
        onSleep = { [pasteboard] _ in
            pasteboard.clearContents()
            pasteboard.setString("user copy", forType: .string)
        }

        let outcome = await makeInserter().insert("hello world")

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

    // MARK: Safety

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
        "when the chord cannot be posted the text stays on the pasteboard, with no restore",
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
        #expect(sleeps.isEmpty)
    }

    @Test("a modifier still held is waited for, polling at a fixed interval, before the chord")
    func waitsForModifiers() async {
        let keys = FakeKeystrokePoster(modifiersHeldFor: 3)

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .inserted)
        #expect(keys.calls == [.modifiersHeld, .modifiersHeld, .modifiersHeld, .modifiersHeld, .postPaste])
        #expect(sleeps == Array(repeating: PasteTiming.modifierPollInterval, count: 3) + [Self.restoreDelay])
    }

    @Test(
        "modifiers are waited for up to 500 ms; past that no chord is posted and the text stays on the pasteboard",
        arguments: [
            (0, true),  // released at the last poll
            (1, false),  // one poll too late
            (Int.max, false),  // never released
        ]
    )
    func modifiersTimeout(extraPolls: Int, posts: Bool) async {
        putRichContent()
        let allowedPolls = Int(Self.modifierTimeout / PasteTiming.modifierPollInterval)
        let keys = FakeKeystrokePoster(modifiersHeldFor: extraPolls == .max ? .max : allowedPolls + extraPolls)

        let outcome = await makeInserter(keys).insert("hello world")

        let waited = sleeps.filter { $0 == PasteTiming.modifierPollInterval }.reduce(.zero, +)
        #expect(waited == Self.modifierTimeout)
        #expect(keys.postCount == (posts ? 1 : 0))
        if posts {
            #expect(outcome == .inserted)
            #expect(sleeps.last == Self.restoreDelay)
            #expect(contents().count == 2)
        } else {
            #expect(outcome == .copiedToClipboard(.pasteFailed))
            #expect(pasteboardText == "hello world")
            #expect(contents().count == 1)
            #expect(!sleeps.contains(Self.restoreDelay))
        }
    }

    @Test(
        "a pause that is cancelled leaves the text on the pasteboard and restores nothing",
        arguments: [
            (PasteTiming.modifierPollInterval, 0),  // while waiting for modifiers
            (Duration.milliseconds(300), 1),  // while waiting to restore
        ]
    )
    func cancelledPause(cancelledPause: Duration, postsBefore: Int) async {
        putRichContent()
        let keys = FakeKeystrokePoster(modifiersHeldFor: 1)
        onSleep = { duration in
            if duration == cancelledPause { throw CancellationError() }
        }

        let outcome = await makeInserter(keys).insert("hello world")

        #expect(outcome == .copiedToClipboard(.pasteFailed))
        #expect(keys.postCount == postsBefore)
        #expect(pasteboardText == "hello world")
        #expect(contents().count == 1)
    }
}
