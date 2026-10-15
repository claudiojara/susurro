import CoreTestSupport
import Testing

@testable import Domain

private struct LockedKeychain: Error {}

@Suite("The session cache of the cloud keys")
struct SessionSecretCacheTests {
    @Test("A key is read from the store once and then served from memory")
    func readsOnce() throws {
        let store = InMemorySecretStore([.anthropic: "sk-1"])
        let cache = SessionSecretCache(store)

        #expect(try cache.secret(for: .anthropic) == "sk-1")
        #expect(try cache.secret(for: .anthropic) == "sk-1")
        #expect(try cache.secret(for: .anthropic) == "sk-1")

        #expect(store.readCount(of: .anthropic) == 1)
    }

    @Test("Each account is read on its own, and an account nobody asks for is never read")
    func readsOnlyTheAskedAccount() throws {
        let store = InMemorySecretStore([.anthropic: "sk-1", .deepgram: "dg-1", .openAICompatible: "oa-1"])
        let cache = SessionSecretCache(store)

        _ = try cache.secret(for: .deepgram)

        #expect(store.readCount(of: .deepgram) == 1)
        #expect(store.readCount(of: .anthropic) == 0)
        #expect(store.readCount(of: .openAICompatible) == 0)
    }

    @Test("Asking whether a key exists never reads it")
    func hasSecretDoesNotRead() {
        let store = InMemorySecretStore([.anthropic: "sk-1"])
        let cache = SessionSecretCache(store)

        #expect(cache.hasSecret(for: .anthropic))
        #expect(!cache.hasSecret(for: .deepgram))

        #expect(store.readCount(of: .anthropic) == 0)
        #expect(store.readCount(of: .deepgram) == 0)
    }

    @Test("A missing key is not remembered, so one added later is found without a relaunch")
    func missingKeyIsNotCached() throws {
        let store = InMemorySecretStore()
        let cache = SessionSecretCache(store)

        #expect(try cache.secret(for: .anthropic) == nil)
        store.set("sk-2", for: .anthropic)

        #expect(try cache.secret(for: .anthropic) == "sk-2")
    }

    @Test("A failed read is not remembered: it throws, and the next call asks the store again")
    func failureIsNotCached() throws {
        let store = InMemorySecretStore([.anthropic: "sk-1"])
        let cache = SessionSecretCache(store)
        store.failReads(with: LockedKeychain())

        #expect(throws: LockedKeychain.self) { try cache.secret(for: .anthropic) }
        store.failReads(with: nil)

        #expect(try cache.secret(for: .anthropic) == "sk-1")
        #expect(store.readCount(of: .anthropic) == 2)
    }

    @Test("Invalidating drops the remembered keys, so the next call reads the store again")
    func invalidateDropsKeys() throws {
        let store = InMemorySecretStore([.anthropic: "sk-1"])
        let cache = SessionSecretCache(store)
        _ = try cache.secret(for: .anthropic)
        store.set("sk-2", for: .anthropic)

        cache.invalidate()

        #expect(try cache.secret(for: .anthropic) == "sk-2")
        #expect(store.readCount(of: .anthropic) == 2)
    }

    @Test("A key nobody needs is never prefetched; the ones in use are read once, before the first dictation")
    func prefetchReadsOnlyKeysInUse() async {
        let store = InMemorySecretStore([.anthropic: "sk-1", .deepgram: "dg-1", .openAICompatible: "oa-1"])
        let cache = SessionSecretCache(store)
        let settings = InMemorySettingsStore()

        await cache.prefetch(SecretAccount.inUse(by: settings))
        #expect(store.readCount(of: .deepgram) == 0)
        #expect(store.readCount(of: .anthropic) == 0)
        #expect(store.readCount(of: .openAICompatible) == 0)

        settings.set(ProviderID.deepgram, for: SpeechSettings.provider)
        settings.set(true, for: SpeechSettings.deepgramEnabled)
        await cache.prefetch(SecretAccount.inUse(by: settings))
        #expect(store.readCount(of: .deepgram) == 1)
        #expect(store.readCount(of: .anthropic) == 0)
    }

    @Test("A failed prefetch is silent and leaves the read to the first use")
    func failedPrefetchIsSilent() async throws {
        let store = InMemorySecretStore([.deepgram: "dg-1"])
        let cache = SessionSecretCache(store)
        store.failReads(with: LockedKeychain())

        await cache.prefetch([.deepgram])
        store.failReads(with: nil)

        #expect(try cache.secret(for: .deepgram) == "dg-1")
    }

    @Test("The accounts in use: the selected cloud recognizer and the selected cloud cleaner, each only when it is on")
    func accountsInUse() {
        let settings = InMemorySettingsStore()
        #expect(SecretAccount.inUse(by: settings).isEmpty)

        settings.set(true, for: SpeechSettings.deepgramEnabled)
        #expect(SecretAccount.inUse(by: settings).isEmpty, "on but not selected")
        settings.set(ProviderID.deepgram, for: SpeechSettings.provider)
        #expect(SecretAccount.inUse(by: settings) == [.deepgram])

        settings.set(ProviderID.anthropic, for: CleanupSettings.provider)
        settings.set(true, for: CleanupSettings.anthropicEnabled)
        #expect(SecretAccount.inUse(by: settings) == [.deepgram], "cleanup is off")
        settings.set(true, for: CleanupSettings.enabled)
        #expect(SecretAccount.inUse(by: settings) == [.deepgram, .anthropic])

        settings.set(ProviderID.openAICompatible, for: CleanupSettings.provider)
        #expect(SecretAccount.inUse(by: settings) == [.deepgram], "OpenAI-compatible is off")
        settings.set(true, for: CleanupSettings.openAICompatibleEnabled)
        #expect(SecretAccount.inUse(by: settings) == [.deepgram, .openAICompatible])
    }

    @Test("Following the settings prefetches at once, and a change of a watched setting drops and reads the keys again")
    func followingSettings() async throws {
        let store = InMemorySecretStore([.deepgram: "dg-1"])
        let cache = SessionSecretCache(store)
        let settings = InMemorySettingsStore()
        settings.set(ProviderID.deepgram, for: SpeechSettings.provider)
        settings.set(true, for: SpeechSettings.deepgramEnabled)
        let watched = SpeechSettings.deepgramEnabled
        let refreshes = AsyncStream<String?>.makeStream()
        let following = Task {
            await cache.following(settings, names: [watched.storageName]) { refreshes.continuation.yield($0) }
        }
        defer { following.cancel() }
        var signals = refreshes.stream.makeAsyncIterator()

        // The first refresh is the prefetch at the start.
        #expect(await signals.next() == .some(nil))
        #expect(store.readCount(of: .deepgram) == 1)

        settings.set("another-model", for: CleanupSettings.anthropicModel)
        store.set("dg-2", for: .deepgram)
        settings.set(false, for: watched)
        // The next refresh is the watched key: the model change before it was skipped. Deepgram is off now, so its key
        // is dropped and not read again.
        #expect(await signals.next() == .some(watched.storageName))
        #expect(store.readCount(of: .deepgram) == 1)
        #expect(try cache.secret(for: .deepgram) == "dg-2")
        #expect(store.readCount(of: .deepgram) == 2)
    }
}
