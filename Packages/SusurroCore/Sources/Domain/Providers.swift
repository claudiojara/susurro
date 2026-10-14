import Foundation

/// Whether a recognizer in the cloud has the key it needs. The keys live in the Keychain, and the pipeline asks only
/// whether one is there: it never reads one.
public protocol ProviderCredentials: Sendable {
    func hasKey(for provider: ASRProviderID) -> Bool
}

/// No provider has a key.
public struct NoProviderCredentials: ProviderCredentials {
    public init() {}

    public func hasKey(for provider: ASRProviderID) -> Bool { false }
}

/// Why a provider cannot be used now.
public enum ProviderBlocker: Sendable, Equatable {
    /// A cloud provider is selected but the user has not turned it on.
    case notEnabled
    /// A cloud provider is turned on but has no key.
    case missingKey
}

/// Sends requests for the adapters that talk to a service. Nothing in the pipeline uses the network unless a cloud
/// provider is enabled, selected, and has a key; tests hand adapters a spy and see that no request was made.
public protocol NetworkTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}
