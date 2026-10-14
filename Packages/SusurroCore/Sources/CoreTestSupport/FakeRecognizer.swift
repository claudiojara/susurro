import Domain
import Foundation
import Synchronization

/// A recognizer with scripted readiness and a fixed result. It logs every call in order.
public final class FakeRecognizer: SpeechRecognizer {
    public enum Call: Sendable, Equatable {
        case readiness
        case prepare
        case transcribe(AudioClip)
    }

    private struct State {
        var script: [RecognizerReadiness]
        var calls: [Call] = []
        var options: [RecognitionOptions] = []
        var transcribed = 0
    }

    /// Opened when `transcribe` is entered.
    public let transcribeEntered = Gate()
    public let id: ASRProviderID
    public let locality: Locality
    public let maxClipDuration: Duration?
    private let transport: (any NetworkTransport)?
    private let state: Mutex<State>
    private let transcripts: [String]
    private let failure: (any Error)?
    private let gate: Gate?
    private let prepareGate: Gate?
    private let readyAfterPrepare: Bool

    /// `readiness` has one value per call and the last one repeats. A `failure` makes `transcribe` throw. A `gated`
    /// recognizer suspends in `transcribe` until `releaseTranscription()`. A recognizer that is `readyAfterPrepare`
    /// reads as ready from the first `prepare()` on, and one with a `gatedPrepare` never returns from it.
    ///
    /// A cloud recognizer (`locality`) sends a request through `transport` for each transcription, as a real one would,
    /// so a test can show that a local one sent nothing.
    public init(
        readiness: [RecognizerReadiness] = [.ready],
        transcript: String = "hello",
        transcripts: [String]? = nil,
        failure: (any Error)? = nil,
        gated: Bool = false,
        readyAfterPrepare: Bool = false,
        gatedPrepare: Bool = false,
        id: ASRProviderID = ASRProviderID("fake"),
        locality: Locality = .local,
        maxClipDuration: Duration? = nil,
        transport: (any NetworkTransport)? = nil
    ) {
        self.id = id
        self.locality = locality
        self.maxClipDuration = maxClipDuration
        self.transport = transport
        state = Mutex(State(script: readiness))
        self.transcripts = transcripts ?? [transcript]
        self.failure = failure
        gate = gated ? Gate() : nil
        prepareGate = gatedPrepare ? Gate() : nil
        self.readyAfterPrepare = readyAfterPrepare
    }

    public var calls: [Call] { state.withLock { $0.calls } }

    public var transcribedClips: [AudioClip] {
        calls.compactMap { call in
            if case .transcribe(let clip) = call { clip } else { nil }
        }
    }

    /// The options of each transcription, in order.
    public var receivedOptions: [RecognitionOptions] { state.withLock { $0.options } }

    public func releaseTranscription() { gate?.open() }

    /// Replaces the readiness script with a single value that repeats.
    public func setReadiness(_ readiness: RecognizerReadiness) {
        state.withLock { $0.script = [readiness] }
    }

    public func readiness() async -> RecognizerReadiness {
        state.withLock { state in
            state.calls.append(.readiness)
            return state.script.count > 1 ? state.script.removeFirst() : state.script[0]
        }
    }

    public func prepare() async {
        state.withLock { state in
            state.calls.append(.prepare)
            if readyAfterPrepare { state.script = [.ready] }
        }
        await prepareGate?.wait()
    }

    public func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
        state.withLock { state in
            state.calls.append(.transcribe(clip))
            state.options.append(options)
        }
        transcribeEntered.open()
        if locality == .cloud, let transport {
            _ = try await transport.send(URLRequest(url: URL(string: "https://speech.example.invalid/transcribe")!))
        }
        await gate?.wait()
        if let failure { throw failure }
        let index = state.withLock { state in
            defer { state.transcribed += 1 }
            return min(state.transcribed, transcripts.count - 1)
        }
        return RawTranscript(text: transcripts[index])
    }
}
