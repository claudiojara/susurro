import Domain
import Foundation

extension ASRProviderID {
    public static let deepgram = ASRProviderID(ProviderID.deepgram)
}

/// Transcribes with Deepgram, a cloud service: the one provider that sends the audio off this Mac.
///
/// It is unusable until the user turned it on (`SpeechSettings.deepgramEnabled`) and a key is in the Keychain, and it
/// asks for nothing else before that: `readiness()` says why, and `transcribe` refuses without sending anything. The
/// audio is sent only when this is the selected recognizer, which the registry decides, and it is the clip the pipeline
/// hands over, already cut to the speech.
///
/// The key travels in the `Authorization` header and nowhere else: not in the address, not in a log, not in an error. It
/// is read from the key store for each request and dropped after it. The only thing besides the audio that goes with a
/// request is the vocabulary, as Deepgram's key terms: no app, no text around the cursor, no selection.
///
/// A failure of any kind throws, and the pipeline then tries Parakeet once (4a); the error says only what kind of failure
/// it was.
public struct DeepgramRecognizer: SpeechRecognizer {
    /// The pre-recorded speech to text endpoint.
    public static let endpoint = URL(string: "https://api.deepgram.com/v1/listen")!
    /// The model. Nova-3 takes key terms for monolingual and multilingual speech.
    static let model = "nova-3"
    /// The most key terms sent, so that a long vocabulary cannot push the request past Deepgram's limit for them.
    static let keyTermLimit = 100

    // `id`, `locality`, and `maxClipDuration` are not requirements of `SpeechRecognizer` yet, and this recognizer
    // already answers them, as Parakeet does.
    public let id = ASRProviderID.deepgram
    public let locality = Locality.cloud
    /// Nil: Deepgram takes a whole recording in one request.
    public let maxClipDuration: Duration? = nil

    private let settings: any SettingsStore
    private let secrets: any SecretStore
    private let session: URLSession
    private let endpoint: URL
    private let timeout: Duration
    private let diagnostics: any DiagnosticsLog

    /// - Parameters:
    ///   - session: The session that sends the request. Tests pass one whose requests a stub answers.
    ///   - endpoint: Where the request goes. Tests pass a made-up host.
    ///   - timeout: How long a request may take before it fails.
    public init(
        settings: any SettingsStore, secrets: any SecretStore, session: URLSession = .shared,
        endpoint: URL = DeepgramRecognizer.endpoint, timeout: Duration = .seconds(30),
        diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        self.settings = settings
        self.secrets = secrets
        self.session = session
        self.endpoint = endpoint
        self.timeout = timeout
        self.diagnostics = diagnostics
    }

    public func readiness() async -> RecognizerReadiness {
        guard settings.value(for: SpeechSettings.deepgramEnabled) else {
            return .unavailable("Deepgram is off. Turn it on in the settings to use it.", retryable: false)
        }
        guard secrets.hasSecret(for: .deepgram) else {
            return .unavailable(
                "Add your Deepgram key to the Keychain (service app.tuminuta, account deepgram).", retryable: false)
        }
        return .ready
    }

    /// A cloud service needs no loading.
    public func prepare() async {}

    public func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
        // Off, or no key: nothing is sent, and the audio never leaves this Mac.
        guard settings.value(for: SpeechSettings.deepgramEnabled), let key = try secrets.secret(for: .deepgram),
            !key.isEmpty
        else { throw RecognitionError.notReady }
        try Task.checkCancellation()

        var request = URLRequest(url: requestURL(for: options))
        request.httpMethod = "POST"
        request.timeoutInterval = Double(timeout.components.seconds)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = clip.wavData()

        let data: Data
        do {
            data = try await CloudHTTP.send(request, using: session)
        } catch let failure as CloudRequestFailure {
            diagnostics.record(.cloudRequestFailed(provider: ProviderID.deepgram, reason: failure.reason))
            throw RecognitionError.engineFailed("Deepgram: \(failure.reason)")
        }
        guard let transcript = Self.transcript(in: data) else {
            diagnostics.record(.cloudRequestFailed(provider: ProviderID.deepgram, reason: "response"))
            throw RecognitionError.engineFailed("Deepgram: response")
        }
        return RawTranscript(text: transcript)
    }

    /// The address with what Deepgram is asked for: the model, the language, and the vocabulary. A pinned language is
    /// sent as it is, and none is asked to be detected.
    func requestURL(for options: RecognitionOptions) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var items = [("model", Self.model), ("smart_format", "true")]
        if let language = options.language {
            items.append(("language", language))
        } else {
            items.append(("detect_language", "true"))
        }
        for term in options.vocabulary.prefix(Self.keyTermLimit) where !term.isEmpty { items.append(("keyterm", term)) }
        components.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.0, value: Self.encoded($0.1))
        }
        return components.url!
    }

    /// A value of the query with everything but letters, digits, and `-._~` encoded. The usual encoding of a query leaves
    /// `+` and `&` as they are, which would turn the term "C++" into "C" and a space.
    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(
                charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
    }

    private struct Response: Decodable {
        struct Results: Decodable {
            struct Channel: Decodable {
                struct Alternative: Decodable { let transcript: String }
                let alternatives: [Alternative]
            }
            let channels: [Channel]
        }
        let results: Results
    }

    private static func transcript(in data: Data) -> String? {
        (try? JSONDecoder().decode(Response.self, from: data))?.results.channels.first?.alternatives.first?.transcript
    }
}
