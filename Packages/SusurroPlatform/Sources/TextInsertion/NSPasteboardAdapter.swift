import AppKit
import Domain

/// How much of a pasteboard a snapshot may take, and for how long.
struct SnapshotLimits: Sendable {
    /// The most bytes a snapshot holds, over every type of every item. A larger clipboard is not worth stalling a paste
    /// for, and holding it in memory until the paste is over.
    var maxBytes: Int
    /// The longest the reading may take. Asking for a lazily provided type makes its owner produce the data, which can
    /// be slow.
    var maxDuration: Duration

    static let standard = SnapshotLimits(maxBytes: 32 * 1_024 * 1_024, maxDuration: .milliseconds(500))
}

/// The general pasteboard as the paste policy sees it. The dictation is written as a promise under the markers that ask
/// clipboard managers to skip it, with the current host only, so Universal Clipboard never carries it to another device.
@MainActor
public final class NSPasteboardAdapter: Domain.Pasteboard {
    private let pasteboard: NSPasteboard
    private let sourceBundleID: String
    private let limits: SnapshotLimits
    /// The promise on the pasteboard now. The pasteboard does not retain the owner of a promise, so it is held here until
    /// the contents are replaced.
    private var promise: PromisedText?

    /// - Parameters:
    ///   - sourceBundleID: Written to the pasteboard so that clipboard managers can tell which app wrote the text.
    public convenience init(
        pasteboard: NSPasteboard = .general,
        sourceBundleID: String = Bundle.main.bundleIdentifier ?? "dev.claudiojara.susurro"
    ) {
        self.init(pasteboard: pasteboard, sourceBundleID: sourceBundleID, limits: .standard)
    }

    init(pasteboard: NSPasteboard, sourceBundleID: String, limits: SnapshotLimits) {
        self.pasteboard = pasteboard
        self.sourceBundleID = sourceBundleID
        self.limits = limits
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func snapshot() async -> PasteboardSnapshot {
        // `NSPasteboard` is not marked as Sendable, and reading it from another thread is how this stays off the main
        // actor: a type that a slow app provides lazily would otherwise freeze the menu bar until the app answers. The
        // pasteboard is only read here.
        let source = UncheckedPasteboard(pasteboard)
        let limits = limits
        return await Task.detached(priority: .userInitiated) {
            Self.read(source.pasteboard, limits: limits)
        }.value
    }

    public func publishPromise(_ text: String) throws -> ReadReceipts {
        let promised = PromisedText(text)
        let item = NSPasteboardItem.marked(source: sourceBundleID) { $0.setDataProvider(promised, forTypes: [.string]) }
        try replaceContents(with: item)
        promise = promised
        return promised.receipts
    }

    public func writeConcrete(_ text: String) throws {
        let item = NSPasteboardItem.marked(source: sourceBundleID) { $0.setString(text, forType: .string) }
        try replaceContents(with: item)
    }

    /// Replaces the contents with the snapshot. The restore is for this Mac only, as the write of the dictation was, so a
    /// restored clipboard is never more widely visible than the original: it cannot reach another device through
    /// Universal Clipboard. The cost is that contents the user copied here, and that this Mac was offering to their
    /// other devices, are no longer offered after the restore.
    public func restore(_ snapshot: PasteboardSnapshot) throws {
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        // The old promise is released only after the pasteboard let go of it.
        promise = nil
        // A pasteboard item belongs to the pasteboard it was read from or written to and cannot be written again, so the
        // snapshot keeps the data and every restore builds new items.
        let items = snapshot.items.map { entries in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type)) }
            return item
        }
        // An empty pasteboard is restored by clearing it, which is done.
        guard items.isEmpty || pasteboard.writeObjects(items) else { throw PasteboardError.writeRefused }
    }

    /// Replaces the pasteboard contents with `item`. Throws when the item could not be built or the pasteboard refused
    /// it, and then the pasteboard is empty.
    private func replaceContents(with item: NSPasteboardItem?) throws {
        // Current host only: Universal Clipboard would otherwise carry the dictation to the user's other devices, and the
        // sync's own read of the text could look like an app reading it.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        // The old promise is released only after the pasteboard let go of it.
        promise = nil
        guard let item, pasteboard.writeObjects([item]) else { throw PasteboardError.writeRefused }
    }

    // MARK: Reading

    private struct UncheckedPasteboard: @unchecked Sendable {
        let pasteboard: NSPasteboard

        init(_ pasteboard: NSPasteboard) {
            self.pasteboard = pasteboard
        }
    }

    /// Every item and every type that gives data, up to the limits. What the snapshot lacks, it says in its gap.
    nonisolated static func read(_ pasteboard: NSPasteboard, limits: SnapshotLimits) -> PasteboardSnapshot {
        let clock = ContinuousClock()
        let start = clock.now
        let changeCountAtStart = pasteboard.changeCount
        var items: [[PasteboardEntry]] = []
        var bytes = 0
        var gap: PasteboardSnapshot.Gap?
        reading: for item in pasteboard.pasteboardItems ?? [] {
            var entries: [PasteboardEntry] = []
            for type in item.types {
                guard start.duration(to: clock.now) <= limits.maxDuration else {
                    gap = .tooSlow
                    break reading
                }
                guard let data = item.data(forType: type) else {
                    // A type made up for the system's own bookkeeping is derived again when the contents come back. Any
                    // other type that gives nothing, such as a file promise, is lost by a restore.
                    if !type.rawValue.hasPrefix("dyn.") { gap = gap ?? .typeWithoutData }
                    continue
                }
                bytes += data.count
                guard bytes <= limits.maxBytes else {
                    gap = .tooLarge
                    break reading
                }
                entries.append(PasteboardEntry(type: type.rawValue, data: data))
            }
            items.append(entries)
        }
        // Someone wrote while we read, so what was read is a mix of two clipboards.
        if gap == nil, pasteboard.changeCount != changeCountAtStart { gap = .changedWhileReading }
        return PasteboardSnapshot(items: items, gap: gap)
    }
}
