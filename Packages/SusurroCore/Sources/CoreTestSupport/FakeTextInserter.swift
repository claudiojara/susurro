import Domain
import Synchronization

/// Records the text it is given and reports a fixed outcome. A `gated` inserter suspends until `releaseInsertion()`,
/// after signalling `entered`. One with a `gatedDrain` suspends in `drain` until `releaseDrain()`, after signalling
/// `drainEntered`.
public final class FakeTextInserter: TextInserter {
    public let entered = Gate()
    public let drainEntered = Gate()
    private let texts = Mutex<[String]>([])
    private let drains = Mutex(0)
    private let outcome: InsertionOutcome
    private let release: Gate?
    private let drainRelease: Gate?

    public init(outcome: InsertionOutcome = .inserted, gated: Bool = false, gatedDrain: Bool = false) {
        self.outcome = outcome
        release = gated ? Gate() : nil
        drainRelease = gatedDrain ? Gate() : nil
    }

    public var insertedTexts: [String] { texts.withLock { $0 } }
    public var drainCount: Int { drains.withLock { $0 } }

    public func releaseInsertion() { release?.open() }
    public func releaseDrain() { drainRelease?.open() }

    public func insert(_ text: String) async -> InsertionOutcome {
        texts.withLock { $0.append(text) }
        entered.open()
        await release?.wait()
        return outcome
    }

    public func drain() async {
        drains.withLock { $0 += 1 }
        drainEntered.open()
        await drainRelease?.wait()
    }
}
