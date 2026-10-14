import Domain
import Synchronization

/// A screen text recognizer with a fixed answer. It records the app of every call. A `gated` one suspends in
/// `recognize` until `release()` or until it is cancelled, after signalling `entered`.
public final class FakeScreenTextRecognizer: ScreenTextRecognizer {
    /// Opened when `recognize` is entered.
    public let entered = Gate()
    private let lines: [String]
    private let failure: (any Error)?
    private let gate: Gate?
    private let apps = Mutex<[AppIdentity]>([])

    public init(lines: [String] = [], failure: (any Error)? = nil, gated: Bool = false) {
        self.lines = lines
        self.failure = failure
        gate = gated ? Gate() : nil
    }

    /// The apps `recognize` was called for, in order.
    public var recognizedApps: [AppIdentity] { apps.withLock { $0 } }
    public var callCount: Int { recognizedApps.count }

    public func release() { gate?.open() }

    public func recognize(windowOf app: AppIdentity) async throws -> [String] {
        apps.withLock { $0.append(app) }
        entered.open()
        await gate?.wait()
        try Task.checkCancellation()
        if let failure { throw failure }
        return lines
    }
}
