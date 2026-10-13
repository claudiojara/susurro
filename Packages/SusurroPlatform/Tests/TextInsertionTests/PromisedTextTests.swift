import AppKit
import Testing

@testable import TextInsertion

@Suite("Promised text", .timeLimit(.minutes(1)))
struct PromisedTextTests {
    @Test("a request for the string provides the text and counts as a read")
    func stringRequestIsAReceipt() {
        let promise = PromisedText("hello")
        let item = NSPasteboardItem()
        #expect(promise.receipts == 0)

        promise.pasteboard(nil, item: item, provideDataForType: .string)

        #expect(item.string(forType: .string) == "hello")
        #expect(promise.receipts == 1)
    }

    @Test("a request for another type provides nothing and is not a read")
    func otherTypesAreNotAReceipt() {
        let promise = PromisedText("hello")
        let item = NSPasteboardItem()

        promise.pasteboard(nil, item: item, provideDataForType: .rtf)

        #expect(item.types.isEmpty)
        #expect(promise.receipts == 0)
    }

    @Test("requests from several threads are all counted")
    func readsFromSeveralThreads() {
        let promise = PromisedText("hello")

        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            promise.pasteboard(nil, item: NSPasteboardItem(), provideDataForType: .string)
        }

        #expect(promise.receipts == 1_000)
    }
}
