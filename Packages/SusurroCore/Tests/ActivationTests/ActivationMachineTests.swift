import Activation
import Domain
import Testing

@Suite("Activation machine")
struct ActivationMachineTests {
    private typealias Run = ActivationRun

    @Test("a press starts a hold: the effects arm Esc, start the capture, read the context and schedule the cap")
    func holdStarts() {
        var run = Run()

        #expect(run.down(0) == [.armEsc, .startCapture(.hold), .captureContext, .scheduleCap(Run.cap)])
        #expect(run.state.phase == .pressed(at: .zero))
    }

    @Test("a held press is submitted on release")
    func heldPressIsSubmitted() {
        var run = Run.pressed()

        #expect(run.up(1_200) == [.cancelCap, .finish(.hold)])
        #expect(run.state.phase == .idle)
    }

    @Test("299 ms is a tap and 300 ms is a hold", arguments: [(299, false), (300, true)])
    func holdThreshold(milliseconds: Int, isHold: Bool) {
        var run = Run.pressed()

        let effects = run.up(milliseconds)

        #expect(effects.contains(.finish(.hold)) == isHold)
        #expect(effects.contains(.discardCapture) == !isHold)
    }

    @Test("a tap discards the recording, arms the double-tap window and disarms Esc when no job is in flight")
    func tapDiscards() {
        var run = Run.pressed()

        #expect(run.up(80) == [.cancelCap, .discardCapture, .scheduleDoubleTapTimeout(Run.window), .disarmEsc])
        #expect(run.state.phase == .awaitingSecondTap(releasedAt: .milliseconds(80)))
    }

    @Test("a tap leaves Esc armed while a job is in flight")
    func tapKeepsEscArmedForAJob() {
        var run = Run()
        run.feed(.jobEnqueued)
        run.down(0)

        #expect(run.up(80) == [.cancelCap, .discardCapture, .scheduleDoubleTapTimeout(Run.window)])
    }

    @Test("a second press inside the window starts hands-free, and its release is ignored")
    func doubleTapStartsHandsFree() {
        var run = Run.awaitingSecondTap()

        #expect(
            run.down(280) == [
                .cancelDoubleTapTimeout, .startCapture(.handsFree), .captureContext, .armEsc, .scheduleCap(Run.cap),
            ])
        #expect(run.state.phase == .handsFree(ignoreNextUp: true))
        #expect(run.up(330).isEmpty)
        #expect(run.state.phase == .handsFree(ignoreNextUp: false))
    }

    @Test("a press after the window, or after the timeout, is a new first press")
    func latePressIsAFirstPress() {
        var late = Run.awaitingSecondTap()
        #expect(late.down(580).contains(.startCapture(.hold)))
        #expect(late.state.phase == .pressed(at: .milliseconds(580)))

        var timedOut = Run.awaitingSecondTap()
        #expect(timedOut.feed(.doubleTapTimeout).effects == [.disarmEsc])
        #expect(timedOut.state.phase == .idle)
        #expect(timedOut.down(900).contains(.startCapture(.hold)))
    }

    @Test("the double-tap timeout leaves Esc armed while a job is in flight")
    func timeoutKeepsEscArmedForAJob() {
        var run = Run()
        run.feed(.jobEnqueued)
        run.down(0)
        run.up(80)

        #expect(run.feed(.doubleTapTimeout).effects.isEmpty)
    }

    @Test("a press during hands-free stops and submits it, and the following release is ignored")
    func handsFreeStops() {
        var run = Run.handsFree()

        #expect(run.down(5_000) == [.cancelCap, .finish(.handsFree)])
        #expect(run.state.phase == .stopping)
        #expect(run.up(5_100).isEmpty)
        #expect(run.state.phase == .idle)
    }

    @Test("silence produces no transition: only the key, Esc and the cap end a hands-free recording")
    func silenceDoesNotStop() {
        var run = Run.handsFree()
        let before = run.state

        #expect(run.feed(.doubleTapTimeout).effects.isEmpty)
        #expect(run.state == before)
    }

    @Test("the cap finishes a hold and a hands-free recording with a notice", arguments: [false, true])
    func capFinishes(handsFree: Bool) {
        var run = handsFree ? Run.handsFree() : Run.pressed()

        #expect(run.feed(.capReached).effects == [.finish(.cap), .notice(.capReached)])
        #expect(run.state.phase == .idle)
    }

    @Test("a cap that fires after the recording ended does nothing")
    func staleCapIsIgnored() {
        var run = Run.pressed()
        run.up(1_200)

        #expect(run.feed(.capReached).effects.isEmpty)
    }

    @Test("Esc while recording cancels it, keeps the audio, and disarms Esc when no job is in flight")
    func escapeCancelsRecording() {
        var hold = Run.pressed()
        var handsFree = Run.handsFree()

        let expected: [Run.Effect] = [.cancelCap, .cancelDoubleTapTimeout, .cancelCapture(keepAudio: true), .disarmEsc]
        let holdTransition = hold.feed(.escape)
        let handsFreeTransition = handsFree.feed(.escape)
        #expect(holdTransition.effects == expected)
        #expect(handsFreeTransition.effects == expected)
        #expect(holdTransition.consumed && handsFreeTransition.consumed)
        #expect(hold.state.phase == .idle && handsFree.state.phase == .idle)
    }

    @Test("Esc while recording leaves Esc armed when a job is in flight")
    func escapeKeepsEscArmedForAJob() {
        var run = Run()
        run.feed(.jobEnqueued)
        run.down(0)

        #expect(run.feed(.escape).effects == [.cancelCap, .cancelDoubleTapTimeout, .cancelCapture(keepAudio: true)])
    }

    @Test("Esc with a job in flight cancels the newest job and is consumed")
    func escapeCancelsJob() {
        var run = Run()
        run.feed(.jobEnqueued)

        let transition = run.feed(.escape)

        #expect(transition.effects == [.cancelNewestJob])
        #expect(transition.consumed)
    }

    @Test("Esc with nothing in flight, even in the double-tap window, does nothing and is not consumed")
    func escapeWhenIdle() {
        var idle = Run()
        var waiting = Run.awaitingSecondTap()

        for transition in [idle.feed(.escape), waiting.feed(.escape)] {
            #expect(transition.effects.isEmpty)
            #expect(!transition.consumed)
        }
        #expect(waiting.state.phase == .awaitingSecondTap(releasedAt: .milliseconds(80)))
    }

    @Test("a failed start stays idle and shows the error, with no capture")
    func failedStartShowsError() {
        var run = Run()

        #expect(run.down(0, startFailure: .microphoneNotGranted) == [.showError(.microphoneNotGranted)])
        #expect(run.state.phase == .idle)
    }

    @Test("a failed start in the double-tap window cancels the window and disarms Esc")
    func failedSecondStart() {
        var run = Run.awaitingSecondTap()

        #expect(
            run.down(280, startFailure: .recognizerNotInstalled)
                == [.cancelDoubleTapTimeout, .showError(.recognizerNotInstalled), .disarmEsc])
        #expect(run.state.phase == .idle)
    }

    @Test("a capture that could not start returns to idle, stops the cap timer and disarms Esc")
    func captureFailedToStart() {
        var run = Run.pressed()

        #expect(run.feed(.captureFailed).effects == [.cancelCap, .disarmEsc])
        #expect(run.state.phase == .idle)
    }

    @Test("a press while recording never starts a second capture")
    func noSecondCapture() {
        var hold = Run.pressed()
        var handsFree = Run.handsFree()

        #expect(hold.down(500).isEmpty)
        #expect(!handsFree.down(5_000).contains(.startCapture(.hold)))
        #expect(!handsFree.state.phase.isRecording)
    }

    @Test("a press with a job in flight starts a new recording")
    func pressDuringProcessing() {
        var run = Run()
        run.feed(.jobEnqueued)

        #expect(run.down(0).contains(.startCapture(.hold)))
    }
}
