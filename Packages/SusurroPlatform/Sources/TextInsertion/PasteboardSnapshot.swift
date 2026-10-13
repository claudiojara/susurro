import AppKit

/// What was on a pasteboard: every item, and every type of each item that offered data.
struct PasteboardSnapshot {
    private struct Entry {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private let items: [[Entry]]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            // A type with no data now, such as one the system derives on request, is skipped. The system derives it
            // again when the snapshot is restored.
            item.types.compactMap { type in item.data(forType: type).map { Entry(type: type, data: $0) } }
        }
    }

    /// Replaces the contents of the pasteboard with the snapshot and says whether the pasteboard took it. This is best
    /// effort: if the pasteboard refuses the write there is nothing else to try.
    ///
    /// - Parameter writeItems: Puts the items on the pasteboard. Tests pass one that refuses.
    @discardableResult
    func restore(
        to pasteboard: NSPasteboard,
        writing writeItems: (NSPasteboard, [NSPasteboardItem]) -> Bool = { $0.writeObjects($1) }
    ) -> Bool {
        pasteboard.clearContents()
        let restored = items.map { entries in
            // A pasteboard item belongs to the pasteboard it was read from or written to and cannot be written again,
            // so the snapshot keeps the data and every restore builds new items.
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        // An empty pasteboard is restored by clearing it, which is done.
        return restored.isEmpty || writeItems(pasteboard, restored)
    }
}
