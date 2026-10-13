import Domain

/// A keyboard that the test scripts. It logs every call in order.
@MainActor
public final class FakeKeystrokePoster: KeystrokePoster {
    public enum Call: Sendable, Equatable {
        case modifiersHeld
        case postPaste
    }

    public private(set) var calls: [Call] = []
    /// Runs each time the paste is posted successfully.
    public var onPost: () -> Void = {}
    private var heldChecksLeft: Int
    private let postFailure: KeystrokeError?

    /// Modifiers read as held for the first `modifiersHeldFor` checks and as released after that. A `postFailure`
    /// makes `postPaste` throw it.
    public init(modifiersHeldFor: Int = 0, postFailure: KeystrokeError? = nil) {
        heldChecksLeft = modifiersHeldFor
        self.postFailure = postFailure
    }

    public var postCount: Int { calls.filter { $0 == .postPaste }.count }

    public func modifiersHeld() -> Bool {
        calls.append(.modifiersHeld)
        guard heldChecksLeft > 0 else { return false }
        heldChecksLeft -= 1
        return true
    }

    public func postPaste() throws {
        calls.append(.postPaste)
        if let postFailure { throw postFailure }
        onPost()
    }
}
