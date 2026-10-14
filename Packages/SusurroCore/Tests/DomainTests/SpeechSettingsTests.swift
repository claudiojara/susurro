import CoreTestSupport
import Foundation
import Testing

@testable import Domain

@Suite("Speech and provider settings")
struct SpeechSettingsTests {
    @Test("the language is guaranteed Spanish until the user picks the fast mode, and Spanish is pinned")
    func languageDefault() {
        let store = InMemorySettingsStore()
        #expect(store.value(for: SpeechSettings.languageMode) == .guaranteedSpanish)
        #expect(SettingsLanguagePreference(settings: store).mode().pinnedLanguage == "es")
        store.set(.fast, for: SpeechSettings.languageMode)
        #expect(SettingsLanguagePreference(settings: store).mode().pinnedLanguage == nil)
    }

    @Test("a fresh install selects Parakeet v3 and keeps every cloud provider off")
    func freshInstall() {
        let store = InMemorySettingsStore()
        #expect(store.value(for: SpeechSettings.provider) == "parakeet-v3")
        #expect(store.value(for: SpeechSettings.deepgramEnabled) == false)
        #expect(store.value(for: CleanupSettings.anthropicEnabled) == false)
        #expect(store.value(for: CleanupSettings.openAICompatibleEnabled) == false)
        #expect(store.value(for: CleanupSettings.provider) == "apple-intelligence")
    }

    @Test("the toggles of the General screen have the defaults of the spec")
    func generalDefaults() {
        let store = InMemorySettingsStore()
        #expect(store.value(for: GeneralSettings.appContextEnabled))
        #expect(store.value(for: GeneralSettings.ocrEnabled) == false)
        #expect(store.value(for: CleanupSettings.enabled))
        #expect(store.value(for: GeneralSettings.overlayEdge) == .bottom)
    }

    @Test("no two settings share a storage name")
    func uniqueNames() throws {
        try requireUniqueStorageNames(SpeechSettings.all + CleanupSettings.all + GeneralSettings.all)
    }

    @Test("an account is named as the Keychain item the user fills in")
    func accounts() {
        #expect(SecretAccount.deepgram.rawValue == "deepgram")
        #expect(SecretAccount.anthropic.rawValue == "anthropic")
        #expect(SecretAccount.openAICompatible.rawValue == "openai-compatible")
    }

    @Test("a key that is empty or unreadable counts as no key")
    func hasSecret() {
        let store = InMemorySecretStore([.deepgram: "k", .anthropic: ""])
        #expect(store.hasSecret(for: .deepgram))
        #expect(!store.hasSecret(for: .anthropic))
        #expect(!store.hasSecret(for: .openAICompatible))
        store.failReads(with: CancellationError())
        #expect(!store.hasSecret(for: .deepgram))
    }
}

@Suite("Endpoint and executable validation")
struct EndpointValidationTests {
    @Test(
        "addresses on this Mac are accepted",
        arguments: [
            "http://localhost:8080/v1/audio/transcriptions", "http://127.0.0.1:9000/inference", "https://localhost/x",
            "http://[::1]:8080/inference", " http://LOCALHOST:8080 ",
        ])
    func accepted(text: String) {
        #expect(LoopbackEndpoint.validated(text) != nil)
    }

    @Test(
        "other hosts, look-alikes, credentials, and other schemes are refused",
        arguments: [
            "http://example.com/v1", "http://localhost.example.com/", "http://127.0.0.1.evil.test/",
            "http://user:pw@localhost/", "ftp://localhost/", "file:///etc/passwd", "localhost:8080", "", "not a url",
            "http://192.168.1.10:8080/",
        ])
    func refused(text: String) {
        #expect(LoopbackEndpoint.validated(text) == nil)
    }

    @Test("a path must be absolute, exist, and be executable")
    func executable() {
        func check(_ path: String, exists: Bool = true, executable: Bool = true, directory: Bool = false)
            -> ExecutablePath.Problem?
        {
            ExecutablePath.validate(
                path, exists: { _ in exists }, isExecutable: { _ in executable }, isDirectory: { _ in directory })
        }
        #expect(check("/usr/local/bin/whisper") == nil)
        #expect(check("") == .empty)
        #expect(check("   ") == .empty)
        #expect(check("whisper") == .notAbsolute)
        #expect(check("./whisper") == .notAbsolute)
        #expect(check("/usr/local/bin/whisper", exists: false) == .missing)
        #expect(check("/usr/local/bin", directory: true) == .missing)
        #expect(check("/usr/local/bin/whisper", executable: false) == .notExecutable)
    }

    @Test("the real file system answers for a real program and a missing one")
    func realFileSystem() {
        #expect(ExecutablePath.validate("/bin/echo") == nil)
        #expect(ExecutablePath.validate("/definitely/not/here") == .missing)
    }
}

@Suite("WAV encoding")
struct WAVEncodingTests {
    @Test("the header describes 16 kHz mono 16-bit audio and the data follows")
    func header() {
        let clip = AudioClip(samples: [0, 1, -1, 0.5, 2, -2])
        let data = clip.wavData()
        #expect(data.count == 44 + 12)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        func word(_ offset: Int) -> UInt32 {
            data[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        }
        #expect(word(4) == 36 + 12)
        #expect(word(24) == 16_000)
        #expect(word(28) == 32_000)
        #expect(word(40) == 12)
    }

    @Test("samples are 16-bit little endian and out-of-range values are clamped")
    func samples() {
        let data = AudioClip(samples: [0, 1, -1, 2]).wavData()
        func sample(_ index: Int) -> Int16 {
            let offset = 44 + index * 2
            return Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
        }
        #expect(sample(0) == 0)
        #expect(sample(1) == Int16.max)
        #expect(sample(2) == -Int16.max)
        #expect(sample(3) == Int16.max)
    }
}
