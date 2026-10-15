import Synchronization

/// Keeps the keys a store handed over in memory for the rest of the session, so that the Keychain is read at most once per
/// account instead of once per dictation (ADR 0037). A read of the Keychain can make macOS ask for the login password,
/// and asking on every dictation is what the cache prevents.
///
/// Only a key that was found is kept. A missing key and a failed read are not, so a key the user adds later is found
/// without a relaunch, and a read the user refused is asked again next time. Asking whether a key exists goes to the store
/// every time: it never hands the key over, and the Keychain does not ask the user about it. An account nobody needs is
/// never read. The keys live only in this object's memory: never on disk, in a setting, or in a log.
public final class SessionSecretCache: SecretStore {
    private let store: any SecretStore
    private let keys = Mutex<[SecretAccount: String]>([:])

    public init(_ store: any SecretStore) {
        self.store = store
    }

    public func secret(for account: SecretAccount) throws -> String? {
        if let kept = keys.withLock({ $0[account] }) { return kept }
        guard let secret = try store.secret(for: account), !secret.isEmpty else { return nil }
        keys.withLock { $0[account] = secret }
        return secret
    }

    public func hasSecret(for account: SecretAccount) -> Bool {
        store.hasSecret(for: account)
    }

    /// Forgets every key, so the next call reads the store again.
    public func invalidate() {
        keys.withLock { $0.removeAll() }
    }

    /// Reads the keys of `accounts` now, off the dictation, so that the first dictation does not wait on the Keychain or
    /// its prompt. A key that is missing or cannot be read is left to the first use, which reports it.
    public func prefetch(_ accounts: Set<SecretAccount>) async {
        for account in accounts.sorted(by: { $0.rawValue < $1.rawValue }) {
            _ = try? secret(for: account)
        }
    }

    /// Prefetches the keys in use now, and each time one of the settings named in `names` changes drops every key and
    /// prefetches the ones in use then, until the task is cancelled. Turning a provider off and on again is how the user
    /// makes the app read a changed key.
    /// - Parameter didRefresh: Called after each prefetch, with nil for the first one and the setting's name after.
    ///   Tests wait on it.
    public func following(
        _ settings: any SettingsStore, names: Set<String>, didRefresh: @Sendable (String?) -> Void = { _ in }
    ) async {
        let changes = settings.changes()
        await prefetch(SecretAccount.inUse(by: settings))
        didRefresh(nil)
        for await change in changes where names.contains(change.name) {
            invalidate()
            await prefetch(SecretAccount.inUse(by: settings))
            didRefresh(change.name)
        }
    }
}

extension SecretAccount {
    /// The accounts whose keys the settings will use: the selected recognizer's when it is Deepgram and Deepgram is on,
    /// and the selected cleaner's when cleanup is on, the cleaner is a cloud one, and that cleaner is on.
    public static func inUse(by settings: any SettingsStore) -> Set<SecretAccount> {
        var accounts: Set<SecretAccount> = []
        if settings.value(for: SpeechSettings.provider) == ProviderID.deepgram,
            settings.value(for: SpeechSettings.deepgramEnabled)
        {
            accounts.insert(.deepgram)
        }
        if settings.value(for: CleanupSettings.enabled) {
            switch settings.value(for: CleanupSettings.provider) {
            case ProviderID.anthropic where settings.value(for: CleanupSettings.anthropicEnabled):
                accounts.insert(.anthropic)
            case ProviderID.openAICompatible where settings.value(for: CleanupSettings.openAICompatibleEnabled):
                accounts.insert(.openAICompatible)
            default: break
            }
        }
        return accounts
    }
}
