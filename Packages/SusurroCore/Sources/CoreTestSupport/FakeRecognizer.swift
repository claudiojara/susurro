import Domain
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
    }

    private let state: Mutex<State>
    private let result: Result<String, any Error>
    private let gate: Gate?
    private let prepareGate: Gate?
    private let readyAfterPrepare: Bool

    /// `readiness` has one value per call and the last one repeats. A `failure` makes `transcribe` throw. A `gated`
    /// recognizer suspends in `transcribe` until `releaseTranscription()`. A recognizer that is `readyAfterPrepare`
    /// reads as ready from the first `prepare()` on, and one with a `gatedPrepare` never returns from it.
    public init(
        readiness: [RecognizerReadiness] = [.ready],
        transcript: String = "hello",
        failure: (any Error)? = nil,
        gated: Bool = false,
        readyAfterPrepare: Bool = false,
        gatedPrepare: Bool = false
    ) {
        state = Mutex(State(script: readiness))
        result = failure.map { .failure($0) } ?? .success(transcript)
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
        state.withLock { $0.calls.append(.transcribe(clip)) }
        await gate?.wait()
        return RawTranscript(text: try result.get())
    }
}
