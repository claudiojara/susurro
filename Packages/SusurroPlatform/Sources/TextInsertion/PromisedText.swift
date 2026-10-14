import AppKit
import Domain

/// The transcript as a promise on the pasteboard. The text is supplied only when an app asks for it, so the first
/// request is the receipt that a paste reached the app. The pasteboard asks only for the first read and serves later
/// reads from its cache (see `PromisedTextTests`), so the count rises once in practice, and the minimum dwell, not the
/// count, is what covers an app that reads the text again.
final class PromisedText: NSObject, NSPasteboardItemDataProvider, Sendable {
    private let text: String
    /// The count of requests for the text.
    let receipts: ReadReceipts

    init(_ text: String, receipts: ReadReceipts = ReadReceipts()) {
        self.text = text
        self.receipts = receipts
        super.init()
    }

    // The pasteboard calls this on whichever thread the request arrives, which is not documented, so the count is
    // guarded by a lock.
    nonisolated func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        // Only `.string` is promised, and the markers and the source are concrete, so no other request should arrive.
        // One that does is not a read of the text: it provides nothing and does not count as a receipt.
        guard type == .string else { return }
        item.setString(text, forType: .string)
        receipts.record()
    }
}
