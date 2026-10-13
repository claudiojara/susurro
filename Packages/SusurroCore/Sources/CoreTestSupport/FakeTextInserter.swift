import Domain
import Synchronization

public final class FakeTextInserter: TextInserter {
    private let texts = Mutex<[String]>([])

    public init() {}

    public var insertedTexts: [String] { texts.withLock { $0 } }

    public func insert(_ text: String) async {
        texts.withLock { $0.append(text) }
    }
}
