import Activation
import Domain

/// Feeds events to the reducer one after another, keeping the state, so a test reads as the sequence it checks.
struct ActivationRun {
    typealias Effect = ActivationMachine.Effect
    typealias Event = ActivationMachine.Event

    static let cap = Duration.seconds(600)
    static let window = Duration.milliseconds(350)

    let machine = ActivationMachine()
    private(set) var state = ActivationMachine.State()

    init(_ state: ActivationMachine.State = .init()) {
        self.state = state
    }

    /// Applies the event and returns what the reducer asked for.
    @discardableResult
    mutating func feed(_ event: Event) -> ActivationMachine.Transition {
        let transition = machine.reduce(state, event)
        state = transition.state
        return transition
    }

    /// The effects of a press at `milliseconds`.
    @discardableResult
    mutating func down(_ milliseconds: Int, startFailure: PipelineError? = nil) -> [Effect] {
        feed(.down(at: .milliseconds(milliseconds), startFailure: startFailure)).effects
    }

    @discardableResult
    mutating func up(_ milliseconds: Int) -> [Effect] {
        feed(.up(at: .milliseconds(milliseconds))).effects
    }

    /// A first press at 0 that starts a hold, with the effects of its start thrown away.
    static func pressed() -> ActivationRun {
        var run = ActivationRun()
        run.down(0)
        return run
    }

    /// A tap (down at 0, up at 80 ms) that is waiting for a second press.
    static func awaitingSecondTap() -> ActivationRun {
        var run = pressed()
        run.up(80)
        return run
    }

    /// A hands-free recording whose second tap has been released.
    static func handsFree() -> ActivationRun {
        var run = awaitingSecondTap()
        run.down(280)
        run.up(330)
        return run
    }
}
