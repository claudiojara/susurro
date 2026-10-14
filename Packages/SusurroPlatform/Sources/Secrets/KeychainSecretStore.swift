import Domain
import Foundation
import Security

/// What the Keychain answered to a search.
public struct KeychainAnswer: Sendable {
    public let status: OSStatus
    /// The data of the item, when the search asked for it and found it.
    public let data: Data?

    public init(status: OSStatus, data: Data? = nil) {
        self.status = status
        self.data = data
    }
}

/// The one thing the app does with the Keychain: look an item up. There is no way to add, change, or delete an item
/// through it, so a store built on it cannot write, whatever its code does.
public protocol KeychainClient: Sendable {
    /// `SecItemCopyMatching` for `query`.
    func copyMatching(_ query: [String: Any]) -> KeychainAnswer
}

/// The system's Keychain.
public struct SystemKeychainClient: KeychainClient {
    public init() {}

    public func copyMatching(_ query: [String: Any]) -> KeychainAnswer {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return KeychainAnswer(status: status, data: result as? Data)
    }
}

/// Why a key could not be read. The status is the system's code and carries no key.
public struct KeychainReadError: Error, Sendable, Equatable {
    public let status: OSStatus
}

/// Reads the keys of the cloud providers from the user's Keychain: the generic passwords of the service `app.tuminuta`,
/// one account for each provider. The items are the user's, made outside the app. The store only searches: it never adds,
/// changes, or deletes an item, never keeps a key after the call that asked for it, and never logs one. What it logs on a
/// failure is the account and the system's status code.
public struct KeychainSecretStore: SecretStore {
    /// The service the user's items are filed under.
    public static let service = "app.tuminuta"

    private let client: any KeychainClient
    private let diagnostics: any DiagnosticsLog

    public init(client: any KeychainClient = SystemKeychainClient(), diagnostics: any DiagnosticsLog = NoDiagnostics())
    {
        self.client = client
        self.diagnostics = diagnostics
    }

    public func secret(for account: SecretAccount) throws -> String? {
        var query = Self.query(for: account)
        query[kSecReturnData as String] = true
        let answer = client.copyMatching(query)
        switch answer.status {
        case errSecSuccess:
            return answer.data.flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            diagnostics.record(.secretUnreadable(account: account, status: answer.status))
            throw KeychainReadError(status: answer.status)
        }
    }

    /// Asks only whether the item exists, for its attributes and not its data, so that checking never hands a key over,
    /// and the system has nothing to ask the user about.
    public func hasSecret(for account: SecretAccount) -> Bool {
        var query = Self.query(for: account)
        query[kSecReturnAttributes as String] = true
        return client.copyMatching(query).status == errSecSuccess
    }

    private static func query(for account: SecretAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
    }
}
