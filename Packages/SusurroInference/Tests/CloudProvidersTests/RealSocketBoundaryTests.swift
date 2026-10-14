import CoreTestSupport
import Domain
import Foundation
import InferenceTestSupport
import Pipeline
import Testing
import TextShaping

@testable import CloudProviders

/// What the two cloud cleaners put on the wire, read from a real TCP connection to a server on this Mac that stands in for
/// a local proxy. The request goes through the cleanup stage and the request factory, as in the app, with sentinel text
/// around the cursor, and a made-up key. They are off unless `SUSURRO_REAL_MODELS=1`, like the other checks that need
/// something real:
///
///     SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealSocketBoundaryTests
@Suite(
    "Cloud cleaners on a real socket",
    .enabled(
        if: ProcessInfo.processInfo.environment["SUSURRO_REAL_MODELS"] == "1",
        "Set SUSURRO_REAL_MODELS=1 to run the checks that open a real socket."),
    .serialized,
    .timeLimit(.minutes(2))
)
struct RealSocketBoundaryTests {
    private static let key = "fake-key-for-the-wire-check-4821"
    private static let transcript = "hola equipo la reunión con acme es mañana"
    private static let vocabulary = ["Acme", "Maria Gonzalez"]
    private static let style = StyleProfile(category: .email, tone: .formal, source: .bundle)

    /// Text the app has but must never send: around the cursor, in the field, selected, or read from the screen.
    private static let sentinels = [
        "SENTINEL-BEFORE-CURSOR-7391", "SENTINEL-AFTER-CURSOR-2204", "SENTINEL-SELECTION-5528",
        "SENTINEL-OCR-TEXT-1046", "SENTINEL-WINDOW-TITLE-8830", "com.apple.mail",
    ]

    /// What the user message holds, and nothing else: the style, the vocabulary, and the transcript.
    private static let expectedUserMessage = """
        <STYLE category="email" tone="formal"/>
        <VOCABULARY>
        Acme
        Maria Gonzalez
        </VOCABULARY>
        <TRANSCRIPT>hola equipo la reunión con acme es mañana</TRANSCRIPT>
        """

    /// Headers that a URLSession adds to any request, whatever it carries.
    private static let transportHeaders: Set<String> = [
        "host", "content-type", "content-length", "accept", "accept-language", "accept-encoding", "user-agent",
        "connection",
    ]

    /// The dictation of the app: the input of the cleanup stage has the cursor text, which a cloud request must drop.
    private static var input: CleanupInput {
        CleanupInput(
            transcript: transcript, style: style, vocabulary: vocabulary,
            cursor: CursorContext(
                before: "SENTINEL-BEFORE-CURSOR-7391 com.apple.mail SENTINEL-SELECTION-5528",
                after: "SENTINEL-AFTER-CURSOR-2204 SENTINEL-OCR-TEXT-1046 SENTINEL-WINDOW-TITLE-8830"))
    }

    private static func tags(in text: String) -> [String] {
        text.matches(of: /<([A-Z_]+)[ >\/]/).map { String($0.output.1) }
    }

    private static func sleep(_ duration: Duration) async throws { try await Task.sleep(for: duration) }

    /// Runs the cleanup stage with a registry that holds the one cloud cleaner, selected and enabled, and returns what the
    /// server received.
    private static func dictate(
        through server: LoopbackServer, provider: String,
        makeCleaner: (InMemorySettingsStore, InMemorySecretStore) -> any TranscriptCleaner,
        enable: (InMemorySettingsStore) -> Void, account: SecretAccount, enabled: SettingKey<Bool>
    ) async throws -> (request: CapturedRequest, result: CleanupResult) {
        let settings = InMemorySettingsStore()
        let secrets = InMemorySecretStore([account: key])
        enable(settings)
        settings.set(provider, for: CleanupSettings.provider)
        let cleaner = makeCleaner(settings, secrets)
        let registry = CleanerRegistry(
            settings: settings,
            entries: [
                .cloud(
                    cleaner, isEnabled: { settings.value(for: enabled) }, hasKey: { secrets.hasSecret(for: account) })
            ])
        let stage = CleanupStage(settings: settings, registry: registry, sleep: { try await sleep($0) })

        let result = try await stage.run(input)
        let requests = server.requests
        try #require(requests.count == 1, "the server saw \(requests.count) requests")
        return (requests[0], result)
    }

    private static func report(_ label: String, _ request: CapturedRequest) {
        print(
            "REAL-WORLD 9g.6 \(label): \(request.requestLine); headers \(request.headerNames.joined(separator: ", ")); body \(String(decoding: request.body, as: UTF8.self))"
        )
    }

    private func expectNothingElseLeaves(_ request: CapturedRequest) {
        let raw = request.rawText
        for sentinel in Self.sentinels { #expect(!raw.contains(sentinel), "\(sentinel) is in the request") }
        #expect(!raw.contains("<CONTEXT>") && !raw.contains("BEFORE_CURSOR"))
        #expect(request.header("Cookie") == nil && request.header("Referer") == nil && request.header("Origin") == nil)
    }

    // MARK: Anthropic

    @Test(
        "an Anthropic request holds the transcript, the vocabulary, the category, and the tone, and the key only in its header"
    )
    func anthropic() async throws {
        let server = try await LoopbackServer.start(
            reply: #"{"content":[{"type":"text","text":"Hola, equipo, la reunión con Acme es mañana."}]}"#)
        let (request, result) = try await Self.dictate(
            through: server, provider: ProviderID.anthropic,
            makeCleaner: { settings, secrets in
                AnthropicCleaner(settings: settings, secrets: secrets, endpoint: server.url("/v1/messages"))
            },
            enable: { $0.set(true, for: CleanupSettings.anthropicEnabled) }, account: .anthropic,
            enabled: CleanupSettings.anthropicEnabled)
        Self.report("Anthropic", request)

        #expect(request.requestLine == "POST /v1/messages HTTP/1.1")
        #expect(result.provider == CleanerProviderID(ProviderID.anthropic) && result.cleaned != nil)
        let json = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(Set(json.keys) == ["model", "max_tokens", "temperature", "system", "messages"])
        #expect(json["system"] as? String == PromptBuilder.systemPrompt)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": Self.expectedUserMessage]])
        #expect(Self.tags(in: Self.expectedUserMessage) == ["STYLE", "VOCABULARY", "TRANSCRIPT"])

        #expect(request.header("x-api-key") == Self.key)
        #expect(request.header("anthropic-version") == "2023-06-01")
        let extra = Set(request.headerNames.map { $0.lowercased() }).subtracting(Self.transportHeaders)
        #expect(extra == ["x-api-key", "anthropic-version"])
        #expect(!request.rawText.replacing(Self.key, with: "").contains("fake-key"))
        #expect(request.headers.filter { $0.value.contains(Self.key) }.map(\.name) == ["x-api-key"])
        #expect(
            !request.requestLine.contains(Self.key) && !String(decoding: request.body, as: UTF8.self).contains(Self.key)
        )
        expectNothingElseLeaves(request)
    }

    // MARK: OpenAI-compatible

    @Test(
        "an OpenAI-compatible request holds the transcript, the vocabulary, the category, and the tone, and the key only in its header"
    )
    func openAICompatible() async throws {
        let server = try await LoopbackServer.start(
            reply:
                #"{"choices":[{"message":{"role":"assistant","content":"Hola, equipo, la reunión con Acme es mañana."}}]}"#
        )
        let (request, result) = try await Self.dictate(
            through: server, provider: ProviderID.openAICompatible,
            makeCleaner: { settings, secrets in
                OpenAICompatibleCleaner(settings: settings, secrets: secrets)
            },
            enable: {
                $0.set(true, for: CleanupSettings.openAICompatibleEnabled)
                $0.set(server.url("/v1").absoluteString, for: CleanupSettings.openAICompatibleBaseURL)
                $0.set("local-model", for: CleanupSettings.openAICompatibleModel)
            }, account: .openAICompatible, enabled: CleanupSettings.openAICompatibleEnabled)
        Self.report("OpenAI-compatible", request)

        #expect(request.requestLine == "POST /v1/chat/completions HTTP/1.1")
        #expect(result.provider == CleanerProviderID(ProviderID.openAICompatible) && result.cleaned != nil)
        let json = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(Set(json.keys) == ["model", "temperature", "messages"])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(
            messages == [
                ["role": "system", "content": PromptBuilder.systemPrompt],
                ["role": "user", "content": Self.expectedUserMessage],
            ])

        #expect(request.header("Authorization") == "Bearer \(Self.key)")
        let extra = Set(request.headerNames.map { $0.lowercased() }).subtracting(Self.transportHeaders)
        #expect(extra == ["authorization"])
        #expect(request.headers.filter { $0.value.contains(Self.key) }.map(\.name) == ["Authorization"])
        #expect(
            !request.requestLine.contains(Self.key) && !String(decoding: request.body, as: UTF8.self).contains(Self.key)
        )
        expectNothingElseLeaves(request)
    }

    // MARK: Nothing is sent

    @Test("a cleaner that is off, or has no key, sends nothing to the server")
    func offSendsNothing() async throws {
        let server = try await LoopbackServer.start(reply: "{}")
        let settings = InMemorySettingsStore()
        settings.set(ProviderID.anthropic, for: CleanupSettings.provider)
        let cleaner = AnthropicCleaner(
            settings: settings, secrets: InMemorySecretStore(), endpoint: server.url("/v1/messages"))
        let registry = CleanerRegistry(
            settings: settings,
            entries: [
                .cloud(cleaner, isEnabled: { settings.value(for: CleanupSettings.anthropicEnabled) }, hasKey: { false })
            ])
        let stage = CleanupStage(settings: settings, registry: registry, sleep: { try await Self.sleep($0) })

        let result = try await stage.run(Self.input)

        #expect(result.cleaned == nil && result.fallbackReason == .providerUnavailable)
        #expect(server.requests.isEmpty)
    }
}
