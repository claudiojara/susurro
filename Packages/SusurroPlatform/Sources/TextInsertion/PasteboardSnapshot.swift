import AppKit

/// What was on a pasteboard: every item, and every type of each item that offered data.
struct PasteboardSnapshot: Equatable {
    private struct Entry: Equatable {
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

    /// Replaces the contents of the pasteboard with the snapshot.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entries in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        _ = pasteboard.writeObjects(restored)
    }
}
