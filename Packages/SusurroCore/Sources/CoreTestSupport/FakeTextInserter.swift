import Domain
import Synchronization

/// Records the text it is given and reports a fixed outcome. A `gated` inserter suspends until `releaseInsertion()`,
/// after signalling `entered`.
public final class FakeTextInserter: TextInserter {
    public let entered = Gate()
    private let texts = Mutex<[String]>([])
    private let outcome: InsertionOutcome
    private let release: Gate?

    public init(outcome: InsertionOutcome = .inserted, gated: Bool = false) {
        self.outcome = outcome
        release = gated ? Gate() : nil
    }

    public var insertedTexts: [String] { texts.withLock { $0 } }

    public func releaseInsertion() { release?.open() }

    public func insert(_ text: String) async -> InsertionOutcome {
        texts.withLock { $0.append(text) }
        entered.open()
        await release?.wait()
        return outcome
    }
}
