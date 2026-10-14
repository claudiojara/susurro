import CoreTestSupport
import Domain
import Foundation
import InferenceTestSupport
import Testing
import TextShaping

@testable import CloudProviders

/// What the two cloud cleaners may send, and when they may send it.
@Suite("Cloud cleaner data boundary", .timeLimit(.minutes(1)))
struct CloudCleanerBoundaryTests {
    private static let key = "cleaner-sentinel-key-9876"
    private static let style = StyleProfile(category: .email, tone: .formal, source: .bundle)
    private static let anthropicReply = #"{"content":[{"type":"text","text":"Hola, equipo."}]}"#
    private static let openAIReply = #"{"choices":[{"message":{"role":"assistant","content":"Hola, equipo."}}]}"#

    private let cloud = CleanupPayload.cloud(
        CloudCleanupRequest(transcript: "hola equipo", style: style, vocabulary: ["Acme", "Maria Gonzalez"]))

    /// Context that must never be sent: each string is found nowhere in a request.
    private let sentinels = ["SENTINEL-BEFORE-CURSOR-7391", "SENTINEL-SELECTION-5528", "SENTINEL-OCR-TEXT-1046"]

    private var local: CleanupPayload {
        .local(
            LocalCleanupRequest(
                transcript: "hola equipo", style: Self.style, vocabulary: ["Acme"],
                beforeCursor: sentinels.joined(separator: " ")))
    }

    // MARK: Anthropic

    private struct AnthropicRig {
        let server: StubServer
        let settings: InMemorySettingsStore
        let secrets: InMemorySecretStore
        let log = RecordingDiagnostics()
        let cleaner: AnthropicCleaner

        init(
            enabled: Bool = true, key: String? = CloudCleanerBoundaryTests.key,
            reply: StubReply = .json(CloudCleanerBoundaryTests.anthropicReply)
        ) {
            let server = StubServer(reply: reply)
            let settings = InMemorySettingsStore()
            let secrets = InMemorySecretStore(key.map { [.anthropic: $0] } ?? [:])
            settings.set(enabled, for: CleanupSettings.anthropicEnabled)
            self.server = server
            self.settings = settings
            self.secrets = secrets
            cleaner = AnthropicCleaner(
                settings: settings, secrets: secrets, session: server.session,
                endpoint: server.url("/v1/messages"), diagnostics: log)
        }
    }

    @Test("a cleaner in the cloud says so")
    func locality() {
        #expect(AnthropicCleaner(settings: InMemorySettingsStore(), secrets: InMemorySecretStore()).locality == .cloud)
        #expect(
            OpenAICompatibleCleaner(settings: InMemorySettingsStore(), secrets: InMemorySecretStore()).locality
                == .cloud)
    }

    @Test("Anthropic throws a boundary violation on a local payload, and sends nothing")
    func anthropicRefusesLocal() async {
        let rig = AnthropicRig()

        await #expect(throws: CloudBoundaryViolation()) { try await rig.cleaner.clean(local) }
        #expect(rig.server.requests.isEmpty)
        #expect(rig.secrets.readCount(of: .anthropic) == 0)
    }

    @Test("the Anthropic request is built from the prompt of the cloud request, with no context")
    func anthropicBody() async throws {
        let rig = AnthropicRig()

        let text = try await rig.cleaner.clean(cloud)

        #expect(text == "Hola, equipo.")
        let request = try #require(rig.server.requests.first)
        #expect(rig.server.requests.count == 1)
        let json = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let prompt = PromptBuilder.build(try cloud.requireCloud())
        #expect(json["system"] as? String == prompt.system)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": prompt.user]])
        #expect(json["model"] as? String == "claude-haiku-4-5")
        #expect(json["temperature"] as? Double == 0)
        #expect(!request.bodyText.contains("<CONTEXT>"))
        #expect(!request.bodyText.contains("BEFORE_CURSOR"))
        #expect(request.bodyText.contains("Maria Gonzalez"))
    }

    @Test("a payload built from a context with sentinel text never carries a sentinel to the network")
    func anthropicSentinels() async throws {
        let rig = AnthropicRig()
        // What the factory does for a cloud cleaner: only the transcript, the style, and the vocabulary leave the context.
        guard case .local(let request) = local else { return }
        let payload = CleanupPayload.cloud(
            CloudCleanupRequest(transcript: request.transcript, style: request.style, vocabulary: request.vocabulary))

        _ = try await rig.cleaner.clean(payload)

        let body = try #require(rig.server.requests.first).bodyText
        for sentinel in sentinels { #expect(!body.contains(sentinel)) }
    }

    @Test("the key is in the x-api-key header, never in the body or the address, and the version is sent")
    func anthropicHeaders() async throws {
        let rig = AnthropicRig()

        _ = try await rig.cleaner.clean(cloud)

        let request = try #require(rig.server.requests.first)
        #expect(request.header("x-api-key") == Self.key)
        #expect(request.header("anthropic-version") == "2023-06-01")
        #expect(request.header("Content-Type") == "application/json")
        #expect(!request.bodyText.contains(Self.key))
        #expect(!request.url.absoluteString.contains(Self.key))
        #expect(request.url.path == "/v1/messages")
    }

    @Test("the model of the settings is the one sent")
    func anthropicModel() async throws {
        let rig = AnthropicRig()
        rig.settings.set("claude-sonnet-4-5", for: CleanupSettings.anthropicModel)

        _ = try await rig.cleaner.clean(cloud)

        let body = try #require(rig.server.requests.first).body
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-sonnet-4-5")
    }

    @Test("an HTTP error throws, and the error and the log say only the status")
    func anthropicHTTPError() async {
        let rig = AnthropicRig(reply: .json(#"{"error":"invalid x-api-key \#(Self.key)"}"#, status: 401))

        await #expect(throws: CloudCleanerError.requestFailed("http-401")) { try await rig.cleaner.clean(cloud) }
        #expect(rig.log.events == [.cloudRequestFailed(provider: "anthropic", reason: "http-401")])
        #expect(!String(describing: rig.log.events).contains(Self.key))
    }

    @Test("a timeout and an answer with no text throw")
    func anthropicOtherFailures() async {
        // A rig keeps its stub server alive, so it is held for as long as the request runs.
        let slow = AnthropicRig(reply: .failure(.timedOut))
        let empty = AnthropicRig(reply: .json(#"{"content":[]}"#))

        await #expect(throws: CloudCleanerError.requestFailed("timeout")) { try await slow.cleaner.clean(cloud) }
        await #expect(throws: CloudCleanerError.response) { try await empty.cleaner.clean(cloud) }
    }

    @Test("Anthropic is unusable until it is on and has a key, and then nothing is sent")
    func anthropicOptIn() async {
        let off = AnthropicRig(enabled: false)
        let noKey = AnthropicRig(enabled: true, key: nil)
        let ready = AnthropicRig()

        guard case .unavailable(let offReason) = await off.cleaner.availability() else { Issue.record("off"); return }
        guard case .unavailable(let keyReason) = await noKey.cleaner.availability() else {
            Issue.record("no key"); return
        }
        #expect(offReason.contains("off"))
        #expect(keyReason.contains("Keychain") && keyReason.contains("anthropic"))
        #expect(await ready.cleaner.availability() == .available)

        await #expect(throws: CloudCleanerError.unavailable) { try await off.cleaner.clean(cloud) }
        await #expect(throws: CloudCleanerError.unavailable) { try await noKey.cleaner.clean(cloud) }
        #expect(off.server.requests.isEmpty && noKey.server.requests.isEmpty)
    }

    @Test("availability checks for a key without reading it")
    func anthropicAvailabilityDoesNotReadTheKey() async {
        let rig = AnthropicRig()
        _ = await rig.cleaner.availability()
        #expect(rig.secrets.readCount(of: .anthropic) == 0)
        #expect(rig.server.requests.isEmpty)
    }

    // MARK: OpenAI-compatible

    private struct OpenAIRig {
        let server: StubServer
        let settings: InMemorySettingsStore
        let secrets: InMemorySecretStore
        let log = RecordingDiagnostics()
        let cleaner: OpenAICompatibleCleaner

        init(
            enabled: Bool = true, key: String? = CloudCleanerBoundaryTests.key, baseURL: String? = nil,
            reply: StubReply = .json(CloudCleanerBoundaryTests.openAIReply)
        ) {
            let server = StubServer(reply: reply)
            let settings = InMemorySettingsStore()
            let secrets = InMemorySecretStore(key.map { [.openAICompatible: $0] } ?? [:])
            settings.set(enabled, for: CleanupSettings.openAICompatibleEnabled)
            settings.set(baseURL ?? server.url("/v1").absoluteString, for: CleanupSettings.openAICompatibleBaseURL)
            settings.set("local-model", for: CleanupSettings.openAICompatibleModel)
            self.server = server
            self.settings = settings
            self.secrets = secrets
            cleaner = OpenAICompatibleCleaner(
                settings: settings, secrets: secrets, session: server.session, diagnostics: log)
        }
    }

    @Test("the OpenAI-compatible cleaner throws a boundary violation on a local payload, and sends nothing")
    func openAIRefusesLocal() async {
        let rig = OpenAIRig()

        await #expect(throws: CloudBoundaryViolation()) { try await rig.cleaner.clean(local) }
        #expect(rig.server.requests.isEmpty)
    }

    @Test("the request goes to the configured base URL and model, with the prompt of the cloud request")
    func openAIBody() async throws {
        let rig = OpenAIRig()

        let text = try await rig.cleaner.clean(cloud)

        #expect(text == "Hola, equipo.")
        let request = try #require(rig.server.requests.first)
        #expect(request.url.path == "/v1/chat/completions")
        let json = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let prompt = PromptBuilder.build(try cloud.requireCloud())
        #expect(json["model"] as? String == "local-model")
        #expect(json["temperature"] as? Double == 0)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": prompt.system], ["role": "user", "content": prompt.user]])
        #expect(!request.bodyText.contains("<CONTEXT>"))
        #expect(!request.bodyText.contains("BEFORE_CURSOR"))
    }

    @Test("the key is in the Authorization header and nowhere else")
    func openAIHeaders() async throws {
        let rig = OpenAIRig()

        _ = try await rig.cleaner.clean(cloud)

        let request = try #require(rig.server.requests.first)
        #expect(request.header("Authorization") == "Bearer \(Self.key)")
        #expect(!request.bodyText.contains(Self.key))
        #expect(!request.url.absoluteString.contains(Self.key))
    }

    @Test("a payload built from a context with sentinel text never carries a sentinel to the network")
    func openAISentinels() async throws {
        let rig = OpenAIRig()
        guard case .local(let request) = local else { return }
        let payload = CleanupPayload.cloud(
            CloudCleanupRequest(transcript: request.transcript, style: request.style, vocabulary: request.vocabulary))

        _ = try await rig.cleaner.clean(payload)

        let body = try #require(rig.server.requests.first).bodyText
        for sentinel in sentinels { #expect(!body.contains(sentinel)) }
    }

    @Test("a trailing slash in the base URL does not double the slash")
    func baseURLSlash() async throws {
        let server = StubServer(reply: .json(Self.openAIReply))
        let rig = OpenAIRig(baseURL: server.url("/v1/").absoluteString)
        rig.settings.set(server.url("/v1/").absoluteString, for: CleanupSettings.openAICompatibleBaseURL)
        let cleaner = OpenAICompatibleCleaner(settings: rig.settings, secrets: rig.secrets, session: server.session)

        _ = try await cleaner.clean(cloud)

        #expect(server.requests.first?.url.path == "/v1/chat/completions")
    }

    @Test("a base URL that is neither https nor on this Mac is unusable, and nothing is sent")
    func openAIBaseURLRule() async {
        let rig = OpenAIRig(baseURL: "http://api.example.com/v1")

        guard case .unavailable(let reason) = await rig.cleaner.availability() else {
            Issue.record("available"); return
        }
        #expect(reason.contains("https"))
        await #expect(throws: CloudCleanerError.unavailable) { try await rig.cleaner.clean(cloud) }
        #expect(rig.server.requests.isEmpty)
    }

    @Test("the OpenAI-compatible cleaner is unusable until it is on and has a key")
    func openAIOptIn() async {
        let off = OpenAIRig(enabled: false)
        let noKey = OpenAIRig(enabled: true, key: nil)

        guard case .unavailable = await off.cleaner.availability() else { Issue.record("off"); return }
        guard case .unavailable = await noKey.cleaner.availability() else { Issue.record("no key"); return }
        await #expect(throws: CloudCleanerError.unavailable) { try await off.cleaner.clean(cloud) }
        await #expect(throws: CloudCleanerError.unavailable) { try await noKey.cleaner.clean(cloud) }
        #expect(off.server.requests.isEmpty && noKey.server.requests.isEmpty)
        #expect(await OpenAIRig().cleaner.availability() == .available)
    }

    @Test("an HTTP error and a malformed answer throw")
    func openAIFailures() async {
        let rig = OpenAIRig(reply: .json("{}", status: 429))

        let empty = OpenAIRig(reply: .json(#"{"choices":[]}"#))

        await #expect(throws: CloudCleanerError.requestFailed("http-429")) { try await rig.cleaner.clean(cloud) }
        #expect(rig.log.events == [.cloudRequestFailed(provider: "openai-compatible", reason: "http-429")])
        await #expect(throws: CloudCleanerError.response) { try await empty.cleaner.clean(cloud) }
    }
}
