/// An account of the user's key store. The names are the Keychain accounts of the service `app.tuminuta`, which the user
/// fills in outside the app.
public enum SecretAccount: String, Sendable, Equatable, CaseIterable {
    case deepgram
    case anthropic
    case openAICompatible = "openai-compatible"
}

/// Where the keys of the cloud providers come from. The app only reads them: it never creates, changes, or deletes a
/// key, and never keeps one beyond the call that needs it, in memory or anywhere else. A key is never logged, never put
/// in a setting, and never shown. A caller that only needs to know whether a key exists asks `hasSecret`.
public protocol SecretStore: Sendable {
    /// The key of the account, or nil when there is none. Throws when the store could not be read, for example while the
    /// Keychain is locked.
    func secret(for account: SecretAccount) throws -> String?
}

extension SecretStore {
    /// Whether the account has a key. A store that cannot be read has none.
    public func hasSecret(for account: SecretAccount) -> Bool {
        guard let secret = try? secret(for: account) else { return false }
        return !secret.isEmpty
    }
}
