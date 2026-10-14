import CoreTestSupport
import Domain
import Foundation
import Security
import Synchronization
import Testing

@testable import Secrets

/// A search as the spy saw it, reduced to what the tests look at.
private struct Query: Sendable {
    let itemClass: String?
    let service: String?
    let account: String?
    let limit: String?
    let returnsData: Bool?
    let returnsAttributes: Bool?
    /// Whether the query holds anything that only a write would need.
    let holdsWriteKeys: Bool

    init(_ query: [String: Any]) {
        itemClass = query[kSecClass as String] as? String
        service = query[kSecAttrService as String] as? String
        account = query[kSecAttrAccount as String] as? String
        limit = query[kSecMatchLimit as String] as? String
        returnsData = query[kSecReturnData as String] as? Bool
        returnsAttributes = query[kSecReturnAttributes as String] as? Bool
        holdsWriteKeys = [kSecValueData, kSecAttrAccessible, kSecUseAuthenticationUI, kSecAttrAccessControl]
            .contains { query[$0 as String] != nil }
    }
}

/// A Keychain that answers from a table and keeps every query it was asked.
private final class KeychainSpy: KeychainClient {
    private struct State {
        var items: [String: Data] = [:]
        var failure: OSStatus?
        var queries: [Query] = []
    }

    private let state = Mutex(State())

    func put(_ secret: String, account: String) {
        state.withLock { $0.items[account] = Data(secret.utf8) }
    }

    func fail(with status: OSStatus?) {
        state.withLock { $0.failure = status }
    }

    var queries: [Query] { state.withLock { $0.queries } }

    func copyMatching(_ query: [String: Any]) -> KeychainAnswer {
        state.withLock { state in
            state.queries.append(Query(query))
            if let failure = state.failure { return KeychainAnswer(status: failure) }
            guard let account = query[kSecAttrAccount as String] as? String, let data = state.items[account] else {
                return KeychainAnswer(status: errSecItemNotFound)
            }
            let wantsData = (query[kSecReturnData as String] as? Bool) == true
            return KeychainAnswer(status: errSecSuccess, data: wantsData ? data : nil)
        }
    }
}

@Suite("Keychain secret store", .timeLimit(.minutes(1)))
struct KeychainSecretStoreTests {
    private let secret = "sentinel-secret-value-1234"

    @Test("it reads the service app.tuminuta, one account for each provider", arguments: SecretAccount.allCases)
    func readsTheAccount(account: SecretAccount) throws {
        let keychain = KeychainSpy()
        keychain.put(secret, account: account.rawValue)
        let store = KeychainSecretStore(client: keychain)

        #expect(try store.secret(for: account) == secret)

        let query = try #require(keychain.queries.first)
        #expect(query.itemClass == kSecClassGenericPassword as String)
        #expect(query.service == "app.tuminuta")
        #expect(query.account == account.rawValue)
        #expect(query.returnsData == true)
    }

    @Test("the accounts are deepgram, anthropic, and openai-compatible")
    func accountNames() {
        #expect(SecretAccount.allCases.map(\.rawValue) == ["deepgram", "anthropic", "openai-compatible"])
    }

    @Test("an item that is not there is nil, not an error")
    func missingItem() throws {
        let store = KeychainSecretStore(client: KeychainSpy())

        #expect(try store.secret(for: .deepgram) == nil)
        #expect(!store.hasSecret(for: .deepgram))
    }

    @Test("every call asks the Keychain, so nothing is cached and a change is seen at once")
    func nothingIsCached() throws {
        let keychain = KeychainSpy()
        let store = KeychainSecretStore(client: keychain)

        #expect(try store.secret(for: .anthropic) == nil)
        keychain.put("first", account: "anthropic")
        #expect(try store.secret(for: .anthropic) == "first")
        keychain.put("second", account: "anthropic")
        #expect(try store.secret(for: .anthropic) == "second")

        #expect(keychain.queries.count == 3)
    }

    @Test("the client can only look an item up, so the store has no way to add or update one")
    func onlyCopyMatching() throws {
        let keychain = KeychainSpy()
        keychain.put(secret, account: "deepgram")
        let store = KeychainSecretStore(client: keychain)
        _ = try store.secret(for: .deepgram)
        _ = store.hasSecret(for: .deepgram)

        // A write would need a value, a data to store, or an access control. None of them is ever in a query.
        for query in keychain.queries {
            #expect(!query.holdsWriteKeys)
            #expect(query.limit == kSecMatchLimitOne as String)
        }
    }

    @Test("checking whether a key exists asks for the attributes and never for the data")
    func presenceDoesNotReadTheKey() {
        let keychain = KeychainSpy()
        keychain.put(secret, account: "openai-compatible")
        let store = KeychainSecretStore(client: keychain)

        #expect(store.hasSecret(for: .openAICompatible))
        #expect(!store.hasSecret(for: .anthropic))

        for query in keychain.queries {
            #expect(query.returnsData == nil)
            #expect(query.returnsAttributes == true)
        }
    }

    @Test("a Keychain that cannot be read throws the status, and the log has the account and the status but no key")
    func unreadableKeychain() throws {
        let keychain = KeychainSpy()
        keychain.put(secret, account: "deepgram")
        keychain.fail(with: errSecInteractionNotAllowed)
        let log = RecordingDiagnostics()
        let store = KeychainSecretStore(client: keychain, diagnostics: log)

        #expect(throws: KeychainReadError(status: errSecInteractionNotAllowed)) { try store.secret(for: .deepgram) }
        #expect(log.events == [.secretUnreadable(account: .deepgram, status: errSecInteractionNotAllowed)])
        #expect(!String(describing: log.events).contains(secret))
        #expect(!store.hasSecret(for: .deepgram))
    }

    @Test("a successful read logs nothing at all")
    func readsAreSilent() throws {
        let keychain = KeychainSpy()
        keychain.put(secret, account: "deepgram")
        let log = RecordingDiagnostics()
        let store = KeychainSecretStore(client: keychain, diagnostics: log)

        _ = try store.secret(for: .deepgram)
        _ = try store.secret(for: .anthropic)

        #expect(log.events.isEmpty)
    }

    @Test("data that is not text reads as no key")
    func notText() throws {
        let answer = KeychainAnswer(status: errSecSuccess, data: Data([0xFF, 0xFE, 0xFD]))

        #expect(try KeychainSecretStore(client: FixedKeychain(answer)).secret(for: .deepgram) == nil)
    }
}

/// A Keychain that gives the same answer to every search.
private final class FixedKeychain: KeychainClient {
    private let answer: KeychainAnswer

    init(_ answer: KeychainAnswer) {
        self.answer = answer
    }

    func copyMatching(_ query: [String: Any]) -> KeychainAnswer { answer }
}
