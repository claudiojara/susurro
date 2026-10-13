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

    // The next two pin what the paste depends on. They describe how the pasteboard behaves today, so a change in a later
    // macOS shows up here. Another process reading the text behaves the same way (checked by hand).

    @Test("a read of the promised text does not change the pasteboard's change count")
    func readKeepsTheChangeCount() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("susurro-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let promise = PromisedText("hello")
        let item = NSPasteboardItem()
        item.setDataProvider(promise, forTypes: [.string])
        pasteboard.clearContents()
        _ = pasteboard.writeObjects([item])
        let written = pasteboard.changeCount

        #expect(pasteboard.string(forType: .string) == "hello")

        #expect(promise.receipts == 1)
        #expect(pasteboard.changeCount == written)
    }

    @Test("only the first read reaches the provider, because the pasteboard serves later reads from its cache")
    func laterReadsAreNotCounted() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("susurro-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let promise = PromisedText("hello")
        let item = NSPasteboardItem()
        item.setDataProvider(promise, forTypes: [.string])
        pasteboard.clearContents()
        _ = pasteboard.writeObjects([item])

        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(pasteboard.string(forType: .string) == "hello")

        #expect(promise.receipts == 1)
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
