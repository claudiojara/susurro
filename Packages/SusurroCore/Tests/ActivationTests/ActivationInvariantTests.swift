import Activation
import Domain
import Testing

/// A small deterministic generator (SplitMix64), so that a failing sequence can be replayed from its seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Plays the part of the coordinator: it executes the effects of the reducer on a model of the world (captures, the Esc
/// registration, the jobs) and reports the state of the model, so that a test can compare the two.
private struct World {
    var captures = 0
    var maxCaptures = 0
    var escapeArmed = false
    var jobs = 0
}

@Suite("Activation invariants")
struct ActivationInvariantTests {
    private typealias Event = ActivationMachine.Event

    private static let steps = 400
    private static let sequences = 1_000

    /// Applies one event and then every effect, as the coordinator does: a `finish` enqueues its job at once.
    private static func apply(_ event: Event, to run: inout ActivationRun, in world: inout World) {
        if case .captureFailed = event, run.state.phase.isRecording { world.captures -= 1 }
        let transition = run.feed(event)
        if case .jobFinished = event, world.jobs > 0 { world.jobs -= 1 }
        for effect in transition.effects {
            switch effect {
            case .startCapture:
                world.captures += 1
                world.maxCaptures = max(world.maxCaptures, world.captures)
            case .discardCapture, .cancelCapture:
                world.captures -= 1
            case .finish:
                world.captures -= 1
                world.jobs += 1
                run.feed(.jobEnqueued)
            case .armEsc:
                world.escapeArmed = true
            case .disarmEsc:
                world.escapeArmed = false
            case .cancelCap, .scheduleCap, .cancelDoubleTapTimeout, .scheduleDoubleTapTimeout, .captureContext,
                .notice, .showError, .cancelNewestJob:
                break
            }
        }
    }

    private static func randomEvent(_ random: inout SeededGenerator, clock: inout Int, jobs: Int) -> Event {
        clock += Int.random(in: 0...600, using: &random)
        switch Int.random(in: 0..<10, using: &random) {
        case 0, 1, 2:
            let failure: PipelineError? = Int.random(in: 0..<5, using: &random) == 0 ? .microphoneNotGranted : nil
            return .down(at: .milliseconds(clock), startFailure: failure)
        case 3, 4, 5: return .up(at: .milliseconds(clock))
        case 6: return .escape
        case 7: return Bool.random(using: &random) ? .doubleTapTimeout : .capReached
        case 8: return jobs > 0 ? .jobFinished : .escape
        default: return .captureFailed
        }
    }

    @Test("over 1,000 seeded random sequences there is at most one capture, and Esc is armed exactly when needed")
    func invariantsHold() {
        for seed in 0..<UInt64(Self.sequences) {
            var random = SeededGenerator(seed: seed)
            var run = ActivationRun()
            var world = World()
            var clock = 0
            for step in 0..<Self.steps {
                let event = Self.randomEvent(&random, clock: &clock, jobs: world.jobs)
                Self.apply(event, to: &run, in: &world)

                let recording = run.state.phase.isRecording
                let context = "seed \(seed), step \(step), after \(event)"
                #expect(world.captures == (recording ? 1 : 0), "captures out of step: \(context)")
                #expect(world.escapeArmed == (recording || world.jobs > 0), "Esc out of step: \(context)")
                #expect(run.state.jobsInFlight == world.jobs, "jobs out of step: \(context)")
                if world.captures != (recording ? 1 : 0) || world.escapeArmed != (recording || world.jobs > 0) {
                    return
                }
            }
            #expect(world.maxCaptures <= 1, "two captures at once in seed \(seed)")
        }
    }
}
