import Domain

/// The state machine behind the hotkey: hold to talk, tap to discard, double tap for hands-free, Esc to cancel. It is a
/// pure reducer, `reduce(state, event) -> Transition`. Time comes from the payloads of the events, and the timers are
/// effects: the coordinator runs them on its clock and sends their firing back as events.
///
/// ```
/// idle --down [start ok]--> pressed(t0)             [armEsc, startCapture(.hold), captureContext, scheduleCap]
/// idle --down [start fails]--> idle                 [showError]
/// pressed --up, held >= 300 ms--> idle              [cancelCap, finish(.hold)]
/// pressed --up, held < 300 ms--> awaitingSecondTap  [cancelCap, discardCapture, scheduleDoubleTapTimeout, disarmEsc*]
/// awaitingSecondTap --down inside the window--> handsFree(ignoreNextUp)
///                                                   [cancelDoubleTapTimeout, startCapture(.handsFree), captureContext,
///                                                    armEsc, scheduleCap]
/// awaitingSecondTap --down after the window--> pressed (a new first press, with cancelDoubleTapTimeout first)
/// awaitingSecondTap --doubleTapTimeout--> idle      [disarmEsc*]
/// handsFree(ignoreNextUp) --up--> handsFree         []
/// handsFree --down--> stopping                      [cancelCap, finish(.handsFree)]
/// stopping --up--> idle                             []
/// pressed | handsFree --capReached--> idle          [finish(.cap), notice(.capReached)]
/// pressed | handsFree --esc--> idle                 [cancelCap, cancelDoubleTapTimeout, cancelCapture(keepAudio), disarmEsc*]
/// anything else --esc, job in flight--> same        [cancelNewestJob]
/// ```
///
/// `*` marks an effect that is emitted only when no job is in flight.
///
/// **Esc.** Esc is armed exactly while a recording or a job is in flight. `armEsc` comes with every `startCapture`.
/// `disarmEsc` comes with whatever ends the last of the two: the end of a recording that no job follows (a tap, an Esc,
/// a capture that could not start, the end of the double-tap window) and the finish of the last job. The coordinator
/// sends `jobEnqueued` as it executes `finish`, and `jobFinished` when the dictation ends however it ends.
///
/// **Effect order.** Effects are executed in the order they are listed. A timer is cancelled before the capture it
/// belonged to ends, `startCapture` comes before `scheduleCap`, and a `notice` comes after the `finish` that it
/// announces, so the notice is on screen before the transcription that follows it.
public struct ActivationMachine: Sendable {
    /// The thresholds. The defaults are the ones of the specs.
    public struct Timing: Sendable, Equatable {
        /// A press this long, or longer, is a hold. A shorter one is a tap.
        public var holdThreshold: Duration
        /// How long after a tap a second press makes the recording hands-free.
        public var doubleTapWindow: Duration
        /// The longest a recording of any mode lasts.
        public var cap: Duration

        public init(holdThreshold: Duration, doubleTapWindow: Duration, cap: Duration) {
            self.holdThreshold = holdThreshold
            self.doubleTapWindow = doubleTapWindow
            self.cap = cap
        }

        public static let standard = Timing(
            holdThreshold: .milliseconds(300), doubleTapWindow: .milliseconds(350), cap: .seconds(600))
    }

    public struct State: Sendable, Equatable {
        public enum Phase: Sendable, Equatable {
            case idle
            /// The key went down at `at` and is still down. A capture is running.
            case pressed(at: Duration)
            /// A tap was released at `releasedAt`. Its recording is discarded, and a press inside the window starts
            /// hands-free.
            case awaitingSecondTap(releasedAt: Duration)
            /// Recording until the next press. `ignoreNextUp` is on until the release of the press that started it.
            case handsFree(ignoreNextUp: Bool)
            /// The press that stopped a hands-free recording is still down, and its release is ignored.
            case stopping

            /// Whether a capture is running.
            public var isRecording: Bool {
                switch self {
                case .pressed, .handsFree: true
                case .idle, .awaitingSecondTap, .stopping: false
                }
            }
        }

        public var phase = Phase.idle
        /// The recordings that have been submitted and have not finished, whatever their stage.
        public var jobsInFlight = 0

        public init(phase: Phase = .idle, jobsInFlight: Int = 0) {
            self.phase = phase
            self.jobsInFlight = jobsInFlight
        }

        /// Whether a press now would start a capture, and so is worth checking the start preconditions for.
        public var startsCaptureOnPress: Bool {
            switch phase {
            case .idle, .awaitingSecondTap: true
            case .pressed, .handsFree, .stopping: false
            }
        }

        /// Whether a press now changes anything. A repeated press during a hold, and one that stops hands-free for the
        /// second time, change nothing.
        public var acceptsPress: Bool {
            switch phase {
            case .idle, .awaitingSecondTap, .handsFree: true
            case .pressed, .stopping: false
            }
        }
    }

    public enum Event: Sendable, Equatable {
        /// The key went down. `startFailure` is what `StartPreconditions` found, read before the event; only a press
        /// that would start a capture looks at it.
        case down(at: Duration, startFailure: PipelineError? = nil)
        case up(at: Duration)
        case escape
        case doubleTapTimeout
        /// The cap timer fired, or the clip reached its size limit.
        case capReached
        /// The capture of the running recording could not start.
        case captureFailed
        case jobEnqueued
        case jobFinished
    }

    public enum Effect: Sendable, Equatable {
        public enum FinishMode: Sendable, Equatable {
            case hold
            case handsFree
            case cap
        }

        case armEsc
        case disarmEsc
        case startCapture(RecordingMode)
        /// Read the context of the focused app for the recording that started.
        case captureContext
        case scheduleCap(Duration)
        case cancelCap
        case scheduleDoubleTapTimeout(Duration)
        case cancelDoubleTapTimeout
        /// Stop the capture and submit the recording.
        case finish(FinishMode)
        /// Stop the capture of a tap and throw it away: no job, no history.
        case discardCapture
        /// Stop the capture on the user's request. `keepAudio` says the audio is kept, as a cancelled recording.
        case cancelCapture(keepAudio: Bool)
        /// Stop the newest job that is in flight. It inserts nothing, whatever stage it was in.
        case cancelNewestJob
        case notice(NoticeKind)
        case showError(PipelineError)
    }

    public struct Transition: Sendable, Equatable {
        public let state: State
        public let effects: [Effect]
        /// For Esc: whether it was used. It is not while nothing is in flight, and then it belongs to the app in front.
        public let consumed: Bool
    }

    public let timing: Timing

    public init(timing: Timing = .standard) {
        self.timing = timing
    }

    public func reduce(_ state: State, _ event: Event) -> Transition {
        var next = state
        var effects: [Effect] = []
        var consumed = false
        let noJob = state.jobsInFlight == 0

        switch event {
        case .down(let time, let failure):
            press(at: time, failure: failure, from: state, to: &next, effects: &effects)

        case .up(let time):
            switch state.phase {
            case .pressed(let pressedAt):
                if time - pressedAt >= timing.holdThreshold {
                    next.phase = .idle
                    effects = [.cancelCap, .finish(.hold)]
                } else {
                    next.phase = .awaitingSecondTap(releasedAt: time)
                    effects = [.cancelCap, .discardCapture, .scheduleDoubleTapTimeout(timing.doubleTapWindow)]
                    if noJob { effects.append(.disarmEsc) }
                }
            case .handsFree(ignoreNextUp: true):
                next.phase = .handsFree(ignoreNextUp: false)
            case .stopping:
                next.phase = .idle
            case .idle, .awaitingSecondTap, .handsFree(ignoreNextUp: false):
                break
            }

        case .escape:
            if state.phase.isRecording {
                next.phase = .idle
                effects = [.cancelCap, .cancelDoubleTapTimeout, .cancelCapture(keepAudio: true)]
                if noJob { effects.append(.disarmEsc) }
                consumed = true
            } else if !noJob {
                effects = [.cancelNewestJob]
                consumed = true
            }

        case .doubleTapTimeout:
            if case .awaitingSecondTap = state.phase {
                next.phase = .idle
                if noJob { effects = [.disarmEsc] }
            }

        case .capReached:
            if state.phase.isRecording {
                next.phase = .idle
                effects = [.finish(.cap), .notice(.capReached)]
            }

        case .captureFailed:
            if state.phase.isRecording {
                next.phase = .idle
                effects = [.cancelCap]
                if noJob { effects.append(.disarmEsc) }
            }

        case .jobEnqueued:
            next.jobsInFlight += 1

        case .jobFinished:
            guard state.jobsInFlight > 0 else { break }
            next.jobsInFlight -= 1
            if next.jobsInFlight == 0, !state.phase.isRecording { effects = [.disarmEsc] }
        }
        return Transition(state: next, effects: effects, consumed: consumed)
    }

    private func press(
        at time: Duration, failure: PipelineError?, from state: State, to next: inout State, effects: inout [Effect]
    ) {
        let noJob = state.jobsInFlight == 0
        switch state.phase {
        case .idle:
            if let failure {
                effects = [.showError(failure)]
            } else {
                next.phase = .pressed(at: time)
                effects = firstPress()
            }

        case .awaitingSecondTap(let releasedAt):
            if let failure {
                next.phase = .idle
                effects = [.cancelDoubleTapTimeout, .showError(failure)]
                if noJob { effects.append(.disarmEsc) }
            } else if time - releasedAt < timing.doubleTapWindow {
                next.phase = .handsFree(ignoreNextUp: true)
                effects = [
                    .cancelDoubleTapTimeout, .startCapture(.handsFree), .captureContext, .armEsc,
                    .scheduleCap(timing.cap),
                ]
            } else {
                // The window is over, whether or not its timeout has been delivered yet: this is a first press.
                next.phase = .pressed(at: time)
                effects = [.cancelDoubleTapTimeout] + firstPress()
            }

        case .handsFree:
            next.phase = .stopping
            effects = [.cancelCap, .finish(.handsFree)]

        case .pressed, .stopping:
            break
        }
    }

    private func firstPress() -> [Effect] {
        [.armEsc, .startCapture(.hold), .captureContext, .scheduleCap(timing.cap)]
    }
}
