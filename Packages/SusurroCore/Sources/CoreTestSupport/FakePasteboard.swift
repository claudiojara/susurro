import Domain
import Foundation

/// A pasteboard that models what the paste policy depends on: a change count that rises with every write, a promised
/// text that is supplied only when someone reads it, and the receipts of those reads. It logs every call in order.
@MainActor
public final class FakePasteboard: Pasteboard {
    /// What the pasteboard holds.
    public enum Content: Equatable {
        /// Items another app or the user put there.
        case items([[PasteboardEntry]])
        /// A promised text, which has been supplied once an app has read it.
        case promise(text: String, supplied: Bool)
        /// The text itself, with nothing promised.
        case concrete(String)
    }

    public enum Call: Equatable {
        case snapshot
        case publishPromise(String)
        case writeConcrete(String)
        case restore
    }

    /// The type an item holds its text under.
    public static let textType = "public.utf8-plain-text"

    public private(set) var content: Content
    public private(set) var changeCount = 0
    public private(set) var calls: [Call] = []

    /// Makes `snapshot` report that it is incomplete.
    public var snapshotGap: PasteboardSnapshot.Gap?
    /// Makes `publishPromise` refuse, which clears the pasteboard as a real refusal does.
    public var refusesPublish = false
    /// Makes `writeConcrete` refuse.
    public var refusesConcrete = false
    /// Makes `restore` refuse.
    public var refusesRestore = false
    /// Runs while `snapshot` is reading, standing in for whatever happens meanwhile.
    public var duringSnapshot: () async -> Void = {}

    private var current: ReadReceipts?
    private var retired: [ReadReceipts] = []

    public init(items: [[PasteboardEntry]] = []) {
        content = .items(items)
    }

    /// How many promised values wait for a first read. A promise that was replaced, or supplied, no longer counts.
    public var pendingPromiseCount: Int {
        if case .promise(_, supplied: false) = content { return 1 }
        return 0
    }

    // MARK: What a user or an app does

    /// The user copies something: the pasteboard changes and a copy that is already there is gone.
    public func userCopies(_ items: [[PasteboardEntry]]) {
        retirePromise()
        content = .items(items)
        changeCount += 1
    }

    public func userCopies(text: String) {
        userCopies([[PasteboardEntry(type: Self.textType, data: Data(text.utf8))]])
    }

    /// An app reads the text the way a paste does. The first read of a promise asks its owner, which is the receipt;
    /// later reads are served from what the pasteboard keeps, as the real one does.
    public func readAsApp() -> String? {
        switch content {
        case .promise(let text, let supplied):
            if !supplied {
                content = .promise(text: text, supplied: true)
                current?.record()
            }
            return text
        case .concrete(let text):
            return text
        case .items(let items):
            guard let entry = items.first?.first(where: { $0.type == Self.textType }) else { return nil }
            return String(decoding: entry.data, as: UTF8.self)
        }
    }

    /// The owner of the promise is asked for the data again, which a real pasteboard does not do for a promise that was
    /// supplied. It is the way a test shows a second request.
    public func requestFromProvider() {
        current?.record()
    }

    /// The owner of a promise that was replaced is asked for the data after all. Nothing is on the pasteboard for it.
    public func requestFromAbandonedPromise() {
        retired.last?.record()
    }

    // MARK: Pasteboard

    public func snapshot() async -> PasteboardSnapshot {
        calls.append(.snapshot)
        await duringSnapshot()
        switch content {
        case .items(let items): return PasteboardSnapshot(items: items, gap: snapshotGap)
        case .promise(let text, _), .concrete(let text):
            return PasteboardSnapshot(
                items: [[PasteboardEntry(type: Self.textType, data: Data(text.utf8))]], gap: snapshotGap)
        }
    }

    public func publishPromise(_ text: String) throws -> ReadReceipts {
        calls.append(.publishPromise(text))
        retirePromise()
        changeCount += 1
        guard !refusesPublish else {
            content = .items([])
            throw PasteboardError.writeRefused
        }
        let receipts = ReadReceipts()
        current = receipts
        content = .promise(text: text, supplied: false)
        return receipts
    }

    public func writeConcrete(_ text: String) throws {
        calls.append(.writeConcrete(text))
        retirePromise()
        changeCount += 1
        guard !refusesConcrete else {
            content = .items([])
            throw PasteboardError.writeRefused
        }
        content = .concrete(text)
    }

    public func restore(_ snapshot: PasteboardSnapshot) throws {
        calls.append(.restore)
        retirePromise()
        changeCount += 1
        guard !refusesRestore else {
            content = .items([])
            throw PasteboardError.writeRefused
        }
        content = .items(snapshot.items)
    }

    private func retirePromise() {
        if let current { retired.append(current) }
        current = nil
    }
}
