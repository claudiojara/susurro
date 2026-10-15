import Domain
import Synchronization

/// A recognizer of partial transcripts with scripted answers. It logs the clip and the language of every call.
public final class FakePartialRecognizer: PartialSpeechRecognizing {
    public struct Call: Sendable, Equatable {
        public let clip: AudioClip
        public let language: String?

        public init(clip: AudioClip, language: String?) {
            self.clip = clip
            self.language = language
        }
    }

    private struct State {
        var answers: [String?]
        var calls: [Call] = []
    }

    /// Opened once for every call that is entered.
    public let entered = Gate()
    private let state: Mutex<State>
    private let gate: Gate?

    /// `answers` has one value per call and the last one repeats; nil is an engine that is busy. A `gated` recognizer
    /// suspends in each call until `release()`, and throws `CancellationError` if its task is cancelled meanwhile, as an
    /// engine that finishes the work and has its result dropped would.
    public init(answers: [String?] = ["hello"], gated: Bool = false) {
        state = Mutex(State(answers: answers))
        gate = gated ? Gate() : nil
    }

    public var calls: [Call] { state.withLock { $0.calls } }

    public func release() { gate?.open() }

    public func transcribePartial(_ clip: AudioClip, language: String?) async throws -> String? {
        let answer = state.withLock { state -> String? in
            state.calls.append(Call(clip: clip, language: language))
            return state.answers.count > 1 ? state.answers.removeFirst() : state.answers[0]
        }
        entered.open()
        if let gate {
            await gate.wait()
            try Task.checkCancellation()
        }
        return answer
    }
}
