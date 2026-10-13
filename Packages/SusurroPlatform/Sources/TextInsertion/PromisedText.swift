import AppKit
import Synchronization

/// The transcript as a promise on the pasteboard. The text is supplied only when an app asks for it, so the first
/// request is the receipt that a paste reached the app.
final class PromisedText: NSObject, NSPasteboardItemDataProvider, Sendable {
    private let text: String
    private let reads = Mutex(0)

    init(_ text: String) {
        self.text = text
        super.init()
    }

    /// How many times an app has asked for the text.
    var receipts: Int { reads.withLock { $0 } }

    // The pasteboard calls this on whichever thread the request arrives, which is not documented, so the count is
    // guarded by a lock.
    nonisolated func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .string else { return }
        item.setString(text, forType: .string)
        reads.withLock { $0 += 1 }
    }
}
