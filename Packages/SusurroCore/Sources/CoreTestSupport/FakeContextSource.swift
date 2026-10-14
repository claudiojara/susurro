import Domain
import Synchronization

/// A context source that a test scripts, one step per call, the last step repeating. A gated step suspends until
/// `release(call:)`, and ignores cancellation while it waits, as a source stuck in the accessibility API does, so its
/// context can arrive after the dictation it belongs to is over.
public final class FakeContextSource: ContextSource {
    public struct Step: Sendable {
        /// What the call returns. Nil returns the empty context of the app it was asked about.
        public var context: DictationContext?
        public var gated: Bool

        public init(context: DictationContext? = nil, gated: Bool = false) {
            self.context = context
            self.gated = gated
        }
    }

    private struct CallGates {
        let entered = Gate()
        let release = Gate()
        let finished = Gate()
    }

    private struct State {
        var calls = 0
        var gates: [Int: CallGates] = [:]
        var apps: [AppIdentity?] = []
    }

    private let steps: [Step]
    private let state = Mutex(State())

    public init(steps: [Step] = [Step()]) {
        self.steps = steps.isEmpty ? [Step()] : steps
    }

    public convenience init(context: DictationContext?, gated: Bool = false) {
        self.init(steps: [Step(context: context, gated: gated)])
    }

    /// How many times a context was asked for.
    public var callCount: Int { state.withLock { $0.calls } }
    /// The app each call was asked about, in order.
    public var apps: [AppIdentity?] { state.withLock { $0.apps } }

    /// Opens when the call begins. Calls are numbered from zero.
    public func entered(call: Int) -> Gate { gates(call).entered }
    /// Opens when the call returns its context.
    public func finished(call: Int) -> Gate { gates(call).finished }
    public func release(call: Int) { gates(call).release.open() }

    public func capture(app: AppIdentity?) async -> DictationContext {
        let call = state.withLock { state in
            defer { state.calls += 1 }
            state.apps.append(app)
            return state.calls
        }
        let step = steps[min(call, steps.count - 1)]
        let gates = gates(call)
        gates.entered.open()
        if step.gated {
            // An unstructured task is not cancelled with this one, so the wait outlives a cancelled dictation.
            await Task { await gates.release.wait() }.value
        }
        gates.finished.open()
        return step.context ?? .empty(app: app)
    }

    private func gates(_ call: Int) -> CallGates {
        state.withLock { state in
            if let gates = state.gates[call] { return gates }
            let gates = CallGates()
            state.gates[call] = gates
            return gates
        }
    }
}
