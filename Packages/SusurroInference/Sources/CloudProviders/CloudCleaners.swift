import Domain
import Foundation
import TextShaping

/// Why a cloud cleaner gave no text. The pipeline falls back to the raw transcript for any of them.
public enum CloudCleanerError: Error, Sendable, Equatable {
    /// The cleaner is off, has no key, or has no usable address. Nothing was sent.
    case unavailable
    /// The request failed. The word says how, and never what was sent or answered.
    case requestFailed(String)
    /// The answer holds no text.
    case response
}

/// What the two cloud cleaners have in common: they take only a cloud payload, are unusable until they are turned on and
/// have a key, send one request, and read the text of the answer. The key is asked from the key store for each request
/// (which may keep it for the session, ADR 0037), goes in a header, and is dropped.
struct CloudCleanerCore: Sendable {
    let provider: String
    let account: SecretAccount
    let enabled: SettingKey<Bool>
    let settings: any SettingsStore
    let secrets: any SecretStore
    let session: URLSession
    let timeout: Duration
    let diagnostics: any DiagnosticsLog

    func availability() -> CleanerAvailability {
        guard settings.value(for: enabled) else {
            return .unavailable("\(provider) is off. Turn it on in the settings.")
        }
        guard secrets.hasSecret(for: account) else {
            return .unavailable(
                "Add your \(provider) key to the Keychain (service app.tuminuta, account \(account.rawValue)).")
        }
        return .available
    }

    /// The cloud request of a payload, and the key. A local payload is a violation of the data boundary and nothing is
    /// read or sent; a cleaner that is off or has no key throws `unavailable`.
    func credentials(for payload: CleanupPayload) throws -> (request: CloudCleanupRequest, key: String) {
        let request = try payload.requireCloud()
        guard settings.value(for: enabled), let key = try secrets.secret(for: account), !key.isEmpty else {
            throw CloudCleanerError.unavailable
        }
        return (request, key)
    }

    /// Sends the request, with the key in `headers`, and returns the body of the answer.
    func send(url: URL, headers: [String: String], body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Double(timeout.components.seconds)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        do {
            return try await CloudHTTP.send(request, using: session)
        } catch let failure as CloudRequestFailure {
            diagnostics.record(.cloudRequestFailed(provider: self.provider.lowercased(), reason: failure.reason))
            throw CloudCleanerError.requestFailed(failure.reason)
        }
    }
}

// MARK: Anthropic

/// Cleans with Anthropic's Messages API. A cloud cleaner: it takes only a cloud payload, so the text around the cursor, the
/// selection, and the screen can never be in a request, and it is unusable until the user turned it on and a key is in the
/// Keychain (account `anthropic`).
public struct AnthropicCleaner: TranscriptCleaner {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2023-06-01"
    /// The most the answer may have. The cloud input is capped at 6,000 characters and the answer is about as long.
    static let maxTokens = 4_096

    public let id = CleanerProviderID(ProviderID.anthropic)
    public let locality = Locality.cloud
    public let budget = ProviderBudget.cloud
    private let core: CloudCleanerCore
    private let endpoint: URL

    public init(
        settings: any SettingsStore, secrets: any SecretStore, session: URLSession = .shared,
        endpoint: URL = AnthropicCleaner.endpoint, timeout: Duration = .seconds(10),
        diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        core = CloudCleanerCore(
            provider: "Anthropic", account: .anthropic, enabled: CleanupSettings.anthropicEnabled, settings: settings,
            secrets: secrets, session: session, timeout: timeout, diagnostics: diagnostics)
        self.endpoint = endpoint
    }

    public func availability() async -> CleanerAvailability { core.availability() }

    public func clean(_ payload: CleanupPayload) async throws -> String {
        let (request, key) = try core.credentials(for: payload)
        let prompt = PromptBuilder.build(request)
        let model = core.settings.value(for: CleanupSettings.anthropicModel)
        let body = try JSONEncoder().encode(
            Body(
                model: model.isEmpty ? CleanupSettings.anthropicModel.defaultValue : model, maxTokens: Self.maxTokens,
                temperature: 0, system: prompt.system, messages: [Message(role: "user", content: prompt.user)]))
        let data = try await core.send(
            url: endpoint, headers: ["x-api-key": key, "anthropic-version": Self.version], body: body)
        guard
            let text = (try? JSONDecoder().decode(Answer.self, from: data))?.content.first(where: { $0.type == "text" }
            )?.text
        else { throw CloudCleanerError.response }
        return text
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Body: Encodable {
        let model: String
        let maxTokens: Int
        let temperature: Double
        let system: String
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, system, messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct Answer: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }
}

// MARK: OpenAI-compatible

/// Cleans with any service that speaks OpenAI's chat completions API, at the base URL the user configured, with the model
/// the user chose. A cloud cleaner, with the same boundary and the same opt-in as the Anthropic one (account
/// `openai-compatible`). The address must use https, unless the service is on this Mac, so that the transcript is never
/// sent in the clear.
public struct OpenAICompatibleCleaner: TranscriptCleaner {
    public let id = CleanerProviderID(ProviderID.openAICompatible)
    public let locality = Locality.cloud
    public let budget = ProviderBudget.cloud
    private let core: CloudCleanerCore

    public init(
        settings: any SettingsStore, secrets: any SecretStore, session: URLSession = .shared,
        timeout: Duration = .seconds(10), diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        core = CloudCleanerCore(
            provider: "OpenAI-compatible", account: .openAICompatible, enabled: CleanupSettings.openAICompatibleEnabled,
            settings: settings, secrets: secrets, session: session, timeout: timeout, diagnostics: diagnostics)
    }

    public func availability() async -> CleanerAvailability {
        let base = core.availability()
        guard base == .available else { return base }
        return baseURL == nil ? .unavailable("The base URL must use https, or http on this Mac.") : .available
    }

    /// The address of the chat completions endpoint, or nil when the base URL is not one the transcript may be sent to.
    private var baseURL: URL? {
        CloudEndpoint.validated(core.settings.value(for: CleanupSettings.openAICompatibleBaseURL))
    }

    public func clean(_ payload: CleanupPayload) async throws -> String {
        let (request, key) = try core.credentials(for: payload)
        guard let baseURL else { throw CloudCleanerError.unavailable }
        let prompt = PromptBuilder.build(request)
        let model = core.settings.value(for: CleanupSettings.openAICompatibleModel)
        let body = try JSONEncoder().encode(
            Body(
                model: model.isEmpty ? CleanupSettings.openAICompatibleModel.defaultValue : model, temperature: 0,
                messages: [
                    Message(role: "system", content: prompt.system), Message(role: "user", content: prompt.user),
                ]))
        let url = baseURL.appendingPathComponent("chat").appendingPathComponent("completions")
        let data = try await core.send(url: url, headers: ["Authorization": "Bearer \(key)"], body: body)
        guard let text = (try? JSONDecoder().decode(Answer.self, from: data))?.choices.first?.message.content
        else { throw CloudCleanerError.response }
        return text
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Body: Encodable {
        let model: String
        let temperature: Double
        let messages: [Message]
    }

    private struct Answer: Decodable {
        struct Choice: Decodable {
            struct Reply: Decodable { let content: String }
            let message: Reply
        }
        let choices: [Choice]
    }
}
