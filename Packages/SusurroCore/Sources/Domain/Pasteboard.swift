import Foundation
import Synchronization

/// One type of a pasteboard item, with its bytes.
public struct PasteboardEntry: Sendable, Equatable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// What a pasteboard held: every item, and every type of each item.
public struct PasteboardSnapshot: Sendable, Equatable {
    /// Why a snapshot does not hold everything the pasteboard offered. Putting it back would then lose part of the
    /// user's clipboard, so the paste leaves the dictation on the clipboard instead of restoring.
    public enum Gap: String, Sendable, Equatable {
        /// A type gave no data when asked, as a file promise or a type that its owner never provides does.
        case typeWithoutData
        /// The contents were larger than a snapshot may be.
        case tooLarge
        /// Reading the contents took longer than a snapshot may take.
        case tooSlow
        /// Someone wrote to the pasteboard while it was being read.
        case changedWhileReading
    }

    public let items: [[PasteboardEntry]]
    /// Nil when the snapshot is faithful.
    public let gap: Gap?

    public init(items: [[PasteboardEntry]], gap: Gap? = nil) {
        self.items = items
        self.gap = gap
    }

    public static let empty = PasteboardSnapshot(items: [])

    /// Whether putting the snapshot back restores everything the pasteboard held.
    public var isFaithful: Bool { gap == nil }
}

/// A running count of the requests for a promised pasteboard value. The pasteboard asks the owner of a promise for the
/// data when an app first reads it, so the first request after the paste chord is the receipt that the paste landed.
/// Adapters call `record` from whichever thread the request arrives on.
public final class ReadReceipts: Sendable {
    private let reads = Mutex(0)

    public init() {}

    /// How many times the data was requested.
    public var count: Int { reads.withLock { $0 } }

    /// Notes one request for the data.
    public func record() { reads.withLock { $0 += 1 } }
}

public enum PasteboardError: Error, Sendable, Equatable {
    /// The pasteboard refused the write.
    case writeRefused
}

/// The general pasteboard, as far as the paste policy needs it.
@MainActor
public protocol Pasteboard {
    /// Rises with every write by anyone.
    var changeCount: Int { get }
    /// Reads every item and every type. Reading can be slow, so adapters do it away from the main actor and give up on
    /// contents that are too large or too slow, which the snapshot reports as a gap.
    func snapshot() async -> PasteboardSnapshot
    /// Replaces the contents with the text as a lazily provided value, marked transient, concealed, and auto-generated
    /// so clipboard managers skip it. The text is supplied only when someone asks for it.
    func publishPromise(_ text: String) throws -> ReadReceipts
    /// Replaces the contents with the text itself, marked in the same way, with nothing promised.
    func writeConcrete(_ text: String) throws
    /// Replaces the contents with the snapshot.
    func restore(_ snapshot: PasteboardSnapshot) throws
}
