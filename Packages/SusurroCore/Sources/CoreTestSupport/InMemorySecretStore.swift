import Domain
import Synchronization

/// A key store that holds its keys in memory, for tests. It also counts how often each account was read, since the real
/// store must be asked every time.
public final class InMemorySecretStore: SecretStore {
    private struct State {
        var secrets: [SecretAccount: String]
        var reads: [SecretAccount: Int] = [:]
        var failure: (any Error)?
    }

    private let state: Mutex<State>

    public init(_ secrets: [SecretAccount: String] = [:]) {
        state = Mutex(State(secrets: secrets))
    }

    public func secret(for account: SecretAccount) throws -> String? {
        try state.withLock { state in
            state.reads[account, default: 0] += 1
            if let failure = state.failure { throw failure }
            return state.secrets[account]
        }
    }

    public func set(_ secret: String?, for account: SecretAccount) {
        state.withLock { $0.secrets[account] = secret }
    }

    /// Makes every read throw `error`, or work again when nil.
    public func failReads(with error: (any Error)?) {
        state.withLock { $0.failure = error }
    }

    public func readCount(of account: SecretAccount) -> Int {
        state.withLock { $0.reads[account, default: 0] }
    }
}
