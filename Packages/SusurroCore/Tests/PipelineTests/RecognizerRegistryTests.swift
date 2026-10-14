import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Recognizer registry", .timeLimit(.minutes(1)))
struct RecognizerRegistryTests {
    private static let cloud = ASRProviderID("cloud-fake")
    private static let other = ASRProviderID("other-fake")

    private struct Keys: ProviderCredentials {
        let present: Set<ASRProviderID>

        func hasKey(for provider: ASRProviderID) -> Bool { present.contains(provider) }
    }

    private static func registry(
        settings: InMemorySettingsStore = InMemorySettingsStore(),
        keys: Set<ASRProviderID> = [],
        transport: SpyNetworkTransport = SpyNetworkTransport()
    ) -> RecognizerRegistry {
        RecognizerRegistry(
            providers: [
                FakeRecognizer(transcript: "parakeet", id: .parakeetV3),
                FakeRecognizer(transcript: "other", id: other),
                FakeRecognizer(transcript: "cloud", id: cloud, locality: .cloud, transport: transport),
            ],
            settings: settings,
            credentials: Keys(present: keys)
        )
    }

    @Test("a fresh install resolves Parakeet v3")
    func freshInstall() {
        #expect(Self.registry().selected().id == .parakeetV3)
    }

    @Test("swapping the selected id gives the next dictation the new provider, with the same pipeline code")
    func swapProviders() async throws {
        let settings = InMemorySettingsStore()
        let registry = Self.registry(settings: settings)
        let clip = AudioClip(samples: [0.1])

        let first = try await registry.selected().transcribe(clip, options: RecognitionOptions())
        settings.set(Self.other.rawValue, for: RecognitionSettings.provider)
        let second = try await registry.selected().transcribe(clip, options: RecognitionOptions())

        #expect(first.text == "parakeet")
        #expect(second.text == "other")
    }

    @Test("the selection persists across a relaunch, which builds a new registry over the same settings")
    func selectionPersists() {
        let settings = InMemorySettingsStore()
        settings.set(Self.other.rawValue, for: RecognitionSettings.provider)

        #expect(Self.registry(settings: settings).selected().id == Self.other)
    }

    @Test("a selection that names no provider the app has resolves to the default")
    func unknownSelection() {
        let settings = InMemorySettingsStore()
        settings.set("removed-provider", for: RecognitionSettings.provider)

        #expect(Self.registry(settings: settings).selected().id == .parakeetV3)
    }

    @Test("a cloud provider is unusable until it is enabled and has a key, and the reason says which is missing")
    func cloudOptIn() throws {
        let settings = InMemorySettingsStore()
        let cloud = try #require(Self.registry().provider(Self.cloud))

        #expect(Self.registry(settings: settings).blocker(of: cloud) == .notEnabled)
        settings.set(true, for: RecognitionSettings.cloudEnabled(for: Self.cloud))
        #expect(Self.registry(settings: settings).blocker(of: cloud) == .missingKey)
        #expect(Self.registry(settings: settings, keys: [Self.cloud]).blocker(of: cloud) == nil)
        // A key alone does not turn a provider on.
        #expect(Self.registry(keys: [Self.cloud]).blocker(of: cloud) == .notEnabled)
    }

    @Test("a local provider is always usable")
    func localIsUsable() throws {
        let registry = Self.registry()

        #expect(try registry.blocker(of: #require(registry.provider(.parakeetV3))) == nil)
        #expect(try registry.blocker(of: #require(registry.provider(Self.other))) == nil)
    }

    @Test("with default settings the resolved provider is local, and a dictation sends nothing over the network")
    func defaultSendsNothing() async throws {
        let transport = SpyNetworkTransport()
        let registry = Self.registry(transport: transport)
        let recognizer = registry.selected()

        _ = try await recognizer.transcribe(AudioClip(samples: [0.1]), options: RecognitionOptions())

        #expect(recognizer.locality == .local)
        #expect(registry.blocker(of: recognizer) == nil)
        #expect(transport.sent.isEmpty)
    }

    @Test("the fallback of a cloud provider is the default provider, and the default has none")
    func fallback() throws {
        let registry = Self.registry()
        let cloud = try #require(registry.provider(Self.cloud))
        let parakeet = try #require(registry.provider(.parakeetV3))

        #expect(registry.fallback(from: cloud)?.id == .parakeetV3)
        #expect(registry.fallback(from: parakeet) == nil)
    }
}
