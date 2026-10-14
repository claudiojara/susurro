import Activation
import Domain
import Testing

@Suite("Esc lifecycle in the activation machine")
struct EscapeLifecycleTests {
    private typealias Run = ActivationRun

    @Test("the last job to finish disarms Esc when the machine is idle or waiting for a second tap")
    func lastJobDisarms() {
        var idle = Run()
        idle.feed(.jobEnqueued)
        #expect(idle.feed(.jobFinished).effects == [.disarmEsc])

        var waiting = Run()
        waiting.feed(.jobEnqueued)
        waiting.down(0)
        waiting.up(80)
        #expect(waiting.feed(.jobFinished).effects == [.disarmEsc])
    }

    @Test("a job that finishes while another job is in flight does not disarm Esc")
    func anotherJobKeepsItArmed() {
        var run = Run()
        run.feed(.jobEnqueued)
        run.feed(.jobEnqueued)

        #expect(run.feed(.jobFinished).effects.isEmpty)
        #expect(run.state.jobsInFlight == 1)
        #expect(run.feed(.jobFinished).effects == [.disarmEsc])
    }

    @Test("a job that finishes during a recording does not disarm Esc", arguments: [false, true])
    func recordingKeepsItArmed(handsFree: Bool) {
        var run = handsFree ? Run.handsFree() : Run.pressed()
        run.feed(.jobEnqueued)

        #expect(run.feed(.jobFinished).effects.isEmpty)
    }

    @Test("a job cancelled by Esc still disarms when it is the last to finish")
    func cancelledJobDisarms() {
        var run = Run()
        run.feed(.jobEnqueued)
        run.feed(.escape)

        #expect(run.feed(.jobFinished).effects == [.disarmEsc])
    }

    @Test("a finish event nobody enqueued is ignored")
    func strayFinish() {
        var run = Run()

        #expect(run.feed(.jobFinished).effects.isEmpty)
        #expect(run.state.jobsInFlight == 0)
    }

    @Test("the job of a hold that was released is tracked until it finishes")
    func holdJobLifecycle() {
        var run = Run.pressed()
        run.up(1_200)
        run.feed(.jobEnqueued)

        #expect(run.state.jobsInFlight == 1)
        #expect(run.feed(.jobFinished).effects == [.disarmEsc])
    }
}
