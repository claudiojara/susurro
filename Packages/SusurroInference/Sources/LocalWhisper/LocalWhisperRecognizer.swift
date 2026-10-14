import Domain
import Foundation

extension ASRProviderID {
    public static let localWhisper = ASRProviderID(ProviderID.localWhisper)
}

/// Transcribes with the Whisper install the user already has, on this Mac. The app manages no model: it is an adapter to
/// a server the user runs (`http` mode, the default) or to a command line tool of the user's (`cli` mode), chosen in the
/// settings with the address or the path.
///
/// Both modes keep the audio on this Mac: the address must be on it, and the command is the user's own program.
/// Readiness is `ready` when the server answers or the program can be run, and `notInstalled` when nothing answers or the
/// program is not there. A failure of either mode throws, and the pipeline keeps the audio for a retry.
public struct LocalWhisperRecognizer: SpeechRecognizer {
    // `id`, `locality`, and `maxClipDuration` are not requirements of `SpeechRecognizer` yet, and this recognizer
    // already answers them, as Parakeet does.
    public let id = ASRProviderID.localWhisper
    public let locality = Locality.local
    /// Nil: the server or the tool takes a whole recording.
    public let maxClipDuration: Duration? = nil

    private let settings: any SettingsStore
    private let session: URLSession
    private let clock: any Clock<Duration>
    private let timeout: Duration
    private let isAllowedEndpoint: @Sendable (URL) -> Bool
    private let temporaryDirectory: URL

    /// - Parameters:
    ///   - session: The session that sends a request in `http` mode. Tests pass one whose requests a stub answers.
    ///   - clock: Times the limit of a run of the command line tool. Tests pass a `ManualClock`.
    ///   - timeout: How long a request or a run may take before it fails.
    ///   - isAllowedEndpoint: Whether an address may be sent audio. The rule is `LoopbackEndpoint`.
    public init(
        settings: any SettingsStore, session: URLSession = .shared, clock: any Clock<Duration> = ContinuousClock(),
        timeout: Duration = .seconds(60),
        isAllowedEndpoint: @escaping @Sendable (URL) -> Bool = { LoopbackEndpoint.validated($0.absoluteString) != nil },
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.settings = settings
        self.session = session
        self.clock = clock
        self.timeout = timeout
        self.isAllowedEndpoint = isAllowedEndpoint
        self.temporaryDirectory = temporaryDirectory
    }

    public func readiness() async -> RecognizerReadiness {
        switch settings.value(for: SpeechSettings.localWhisperMode) {
        case .http:
            guard let http = try? makeHTTP() else {
                return .unavailable("The address of Local Whisper must be on this Mac.", retryable: false)
            }
            return await http.isReachable() ? .ready : .notInstalled
        case .cli:
            let path = settings.value(for: SpeechSettings.localWhisperExecutable)
            switch ExecutablePath.validate(path) {
            case nil: return .ready
            case .empty?, .missing?: return .notInstalled
            case .notAbsolute?:
                return .unavailable("The path of the Local Whisper command must start with a slash.", retryable: false)
            case .notExecutable?:
                return .unavailable("The Local Whisper command cannot be run.", retryable: false)
            }
        }
    }

    /// There is nothing to load: the server or the tool is the user's.
    public func prepare() async {}

    public func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
        do {
            switch settings.value(for: SpeechSettings.localWhisperMode) {
            case .http: return RawTranscript(text: try await makeHTTP().transcribe(clip, options: options))
            case .cli: return RawTranscript(text: try await transcribeWithCommand(clip, options: options))
            }
        } catch let error as LocalWhisperError {
            throw error.recognitionError
        }
    }

    // MARK: Modes

    private func makeHTTP() throws -> LocalWhisperHTTP {
        let text = settings.value(for: SpeechSettings.localWhisperEndpoint).trimmingCharacters(
            in: .whitespacesAndNewlines)
        // Whether the address is on this Mac is decided by `isAllowedEndpoint`, in the request.
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil
        else { throw LocalWhisperError.invalidEndpoint }
        return try LocalWhisperHTTP(
            endpoint: url, style: settings.value(for: SpeechSettings.localWhisperServerStyle),
            model: settings.value(for: SpeechSettings.localWhisperModel), timeout: timeout, session: session,
            isAllowed: isAllowedEndpoint)
    }

    private func transcribeWithCommand(_ clip: AudioClip, options: RecognitionOptions) async throws -> String {
        let cli = try LocalWhisperCLI(
            path: settings.value(for: SpeechSettings.localWhisperExecutable), timeout: timeout, clock: clock)
        // The file is the app's: a name nobody can guess, in the user's own temporary folder, that only the user can read,
        // and gone as soon as the run is over.
        let file = temporaryDirectory.appendingPathComponent("susurro-\(UUID().uuidString).wav")
        guard
            FileManager.default.createFile(
                atPath: file.path, contents: clip.wavData(), attributes: [.posixPermissions: 0o600])
        else { throw LocalWhisperError.couldNotStart }
        defer { try? FileManager.default.removeItem(at: file) }
        return try await cli.transcribe(wavPath: file.path, language: options.language)
    }
}
