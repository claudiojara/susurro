import CoreTestSupport
import Domain
import Foundation
import Testing

@MainActor
@Suite("Fake pasteboard")
struct FakePasteboardTests {
    private let rich = [[PasteboardEntry(type: FakePasteboard.textType, data: Data("alpha".utf8))]]

    @Test("the change count rises with every write: publish, concrete text, restore, and a copy by the user")
    func changeCountRises() async throws {
        let pasteboard = FakePasteboard(items: rich)
        #expect(pasteboard.changeCount == 0)

        _ = try pasteboard.publishPromise("one")
        #expect(pasteboard.changeCount == 1)
        try pasteboard.writeConcrete("two")
        #expect(pasteboard.changeCount == 2)
        try pasteboard.restore(PasteboardSnapshot(items: rich))
        #expect(pasteboard.changeCount == 3)
        pasteboard.userCopies(text: "three")
        #expect(pasteboard.changeCount == 4)
    }

    @Test("a snapshot and the reads of the pasteboard do not change the count")
    func readsDoNotChangeTheCount() async throws {
        let pasteboard = FakePasteboard(items: rich)
        _ = try pasteboard.publishPromise("one")
        let count = pasteboard.changeCount

        _ = await pasteboard.snapshot()
        _ = pasteboard.readAsApp()

        #expect(pasteboard.changeCount == count)
    }

    @Test("a promise supplies its text only when read, and the first read is a receipt")
    func promiseIsLazy() throws {
        let pasteboard = FakePasteboard()
        let receipts = try pasteboard.publishPromise("hello")
        #expect(pasteboard.pendingPromiseCount == 1)
        #expect(receipts.count == 0)

        #expect(pasteboard.readAsApp() == "hello")
        #expect(receipts.count == 1)
        #expect(pasteboard.pendingPromiseCount == 0)
    }

    @Test("a later read is served from what the pasteboard keeps, and only an explicit request asks the owner again")
    func laterReadsAreCached() throws {
        let pasteboard = FakePasteboard()
        let receipts = try pasteboard.publishPromise("hello")

        _ = pasteboard.readAsApp()
        _ = pasteboard.readAsApp()
        #expect(receipts.count == 1)

        pasteboard.requestFromProvider()
        #expect(receipts.count == 2)
    }

    @Test("replacing a promise leaves no pending promise, and a request on the abandoned one reaches only its receipts")
    func replacedPromise() throws {
        let pasteboard = FakePasteboard()
        let receipts = try pasteboard.publishPromise("hello")

        try pasteboard.writeConcrete("hello")
        #expect(pasteboard.pendingPromiseCount == 0)
        #expect(pasteboard.content == .concrete("hello"))

        pasteboard.requestFromAbandonedPromise()
        #expect(receipts.count == 1)
        #expect(pasteboard.content == .concrete("hello"))
    }

    @Test("a refused write clears the pasteboard and throws")
    func refusedWrite() {
        let pasteboard = FakePasteboard(items: rich)
        pasteboard.refusesPublish = true

        #expect(throws: PasteboardError.writeRefused) { try pasteboard.publishPromise("hello") }
        #expect(pasteboard.content == .items([]))
        #expect(pasteboard.pendingPromiseCount == 0)
    }

    @Test("a snapshot reports the gap the test sets")
    func snapshotGap() async {
        let pasteboard = FakePasteboard(items: rich)
        pasteboard.snapshotGap = .tooLarge

        let snapshot = await pasteboard.snapshot()

        #expect(snapshot.items == rich)
        #expect(snapshot.gap == .tooLarge)
        #expect(!snapshot.isFaithful)
    }
}
