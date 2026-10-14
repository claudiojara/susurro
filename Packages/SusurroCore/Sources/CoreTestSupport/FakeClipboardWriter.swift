import Domain
import Synchronization

/// A clipboard that keeps what it was given.
public final class FakeClipboardWriter: ClipboardWriting {
    private let texts = Mutex<[String]>([])

    public init() {}

    /// Everything copied, in order.
    public var copiedTexts: [String] { texts.withLock { $0 } }

    public func copy(_ text: String) async {
        texts.withLock { $0.append(text) }
    }
}
