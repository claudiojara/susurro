# 0015. The cleanup budget follows the paste promise, and the model is prewarmed at key-down

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

The product promise is that the text is pasted in under 2 s after the release (proposal, success criteria). Speech
recognition takes 110 to 212 ms for a 5 s clip (4d.10), so the budget is the cleaner's. Cleanup is on by default, and the
on-device model is slow and uneven: the headless check of 4d.10 saw calls of 1 to 23 s on a busy Mac (load average 8 to
14), and the flat limit of 4 s sent the raw text in 3 of 4 runs while still making a short question wait the full 4 s.
Two questions followed. What should the limit be, and can the model be made ready before the key comes up?

## Considered Options

- Cleanup off by default. It removes the wait, and the point of the product: `CleanupSettings` says that cleanup is the
  point of the app and the raw transcript is only the fallback.
- Skip cleanup for short utterances. It saves the least where it matters, since a short question is where "¿…?" is lost.
- Paste the raw text at once and replace it with the cleaned one when it arrives. That is cleanup off, with a text that
  changes under the cursor.
- Keep cleanup on, size the limit by what was said, and warm the model while the person speaks.

## Decision Outcome

The last. Cleanup stays on by default.

**The limit.** For the on-device model, `ProviderBudget.timeout(forTranscriptCharacters:)` is **1.2 s plus 8 ms for each
character of transcript, up to 6 s**. 8 ms a character is the time to write a faithful reply: 0.23 tokens a character
(ADR 0008) at about 30 tokens a second. A 30-character question gets 1.44 s, the 79-character sentence of the real-model
checks 1.83 s, 300 characters 3.6 s, and 600 characters or more 6 s. Short utterances land near 2 s once the 110 to 212 ms
of recognition is added, and a long one waits in proportion to what was said, as `DictationLimits.transcriptionTimeout`
already does for the recognizer. A cloud cleaner keeps 6 s flat: its time is the network's, not the length's.

**The warm-up.** The SDK has `LanguageModelSession.prewarm(promptPrefix:)`. As the key goes down, the coordinator calls
`CleanupStage.prewarm()` in a task of its own, next to the vocabulary job, and it never delays the recording. The stage
does nothing while cleanup is off. `AppleIntelligenceCleaner.prewarm()` does nothing when the model is not available;
otherwise `LiveFoundationModelsEngine` makes the session with the fixed instructions, prewarms it, and keeps it in a
`WarmSlot`. The next `generate` with the same instructions takes it, once, and takes a new session if there is none. So a
dictation still never sees the one before it (ADR 0008), and a tap that is discarded costs one session that the next
prewarm replaces.

**Measured** on an M1 Max with 32 GB, macOS 26.6.2, and a desktop at a load average of 10 to 20 (Teams, OrbStack, and Mail
open), with the 79-character Spanish sentence:

| Check | Result |
| --- | --- |
| Isolated cleaner calls, back to back | 3.9 to 7.3 s |
| After 25 s idle, no prewarm | 8.2, 8.3, and 24.8 s |
| Prewarmed 3 s before the call | 3.9, 7.0, and 14.5 s |
| `RealPipelineTests.releaseToTextWithCleanup`, three runs of 6 with the prewarm | cleaned 0 of 6 each time (timeout 6 of 6); warm median 4.9, 2.1, and 5.0 s |
| The same, one run of 6 without the prewarm | cleaned 0 of 6 (timeout 6 of 6); warm median 2.1 s |

On this Mac in this state the model does not answer within 1.83 s with or without the warm-up, so the raw text is pasted
2.0 to 2.2 s after the release when recognition is fast (the 1.83 s of the limit plus recognition), and 3 to 5 s when
recognition is slowed (below). The prewarm was faster than the cold call in
all three pairs, but three pairs under that load are a direction and not a measurement. The check asserts the warm median
under 2 s and prints the hit rate, so that both numbers are tracked on a quiet machine instead of read once.

A second effect shows in the same runs: after a call that timed out, the model keeps running for a while and slows the
next recognition (Parakeet took 1.3 to 3.1 s instead of 0.1 to 0.2 s in about half of the runs, with or without the
warm-up).

### Consequences

- Good: a short question or sentence waits about as long as the promise allows, not a flat 4 s, and a long dictation is no
  longer cut at 4 s while its reply is still being written.
- Good: when the Mac is quiet, the model is warm by the time the key comes up.
- Bad: on a loaded Mac the cleaner often misses its limit and the raw text is pasted, with the reason `timeout` in the
  history. This is the price of keeping the 2 s promise, and the history shows how often it happens.
- Bad: a model call that was cut keeps running and can slow the next recognition. Cancelling the session on a timeout
  does not stop it at once. Revisit if it is reported.
- Bad: the prewarm loads the model for a tap that is then discarded.

## Addendum, 2026-10-14: cleanup is off by default, and the model is no longer prewarmed

This addendum supersedes two parts of the decision above: "Cleanup stays on by default" and the warm-up at key-down. The
limit that follows the length of the transcript (1.2 s plus 8 ms for each character, up to 6 s) stays, for the user who
turns cleanup on.

**Measured** under the user's normal load (Mail, Teams, and OrbStack open), after the decision above shipped:

| Check | Result |
| --- | --- |
| Release to text without cleanup | about 0.13 s |
| Release to text with cleanup | about 4.8 s |
| Cleanup succeeded | 0 of 12 dictations |
| Parakeet with the key-down prewarm | 2 to 6 s, instead of about 0.12 s |

The model did not answer within its limit in any dictation, so the user paid 4.8 s for the raw text. The prewarm made it
worse and not better: loading the on-device model while the person speaks slowed speech recognition by an order of
magnitude, which is the effect the "second effect" paragraph above saw after a call that timed out.

**Decision** (the user's): speed matters more than cleanup.

- `cleanup.enabled` defaults to false. Cleanup is opt-in, and the menu switch reads "Clean up text (adds a few seconds)".
  A user who already stored true keeps it, since a stored value wins over the default.
- The key-down prewarm is removed: `CleanupStage.prewarm()`, `TranscriptCleaner.prewarm()`, the coordinator's
  `prewarmCleaner`, and its wiring in `AppEnvironment`. So are `FoundationModelsEngine.prewarm(instructions:)` and
  `WarmSlot`, which only the prewarm used. Each call makes a session of its own and drops it when the call ends.
- The promise of 2 s after the release (success criteria, `tasks.md` 4d.10) is the promise with cleanup off, which is the
  default: a warm median of 125 to 142 ms. With cleanup on, the user pays for it in time, and the history still shows the
  fallback reason when the limit is missed.
- A model call that ran out of time is cancelled where it runs. `withDeadline` already cancelled the task of the call
  (`CleanupStageTests.timeoutCancelsTheCleaner`, and `TimeoutCancellationTests` for the engine behind
  `AppleIntelligenceCleaner`, with a fake engine that records `Task.isCancelled`). What the real model added: a `respond`
  that was cancelled in the middle of a long reply returned 3 to 6 s later, when the model had finished writing and the
  call threw `CancellationError`, so the call still held the cleaner's queue for seconds. `LiveFoundationModelsEngine` now
  reads the reply with `streamResponse`, which ends in under a millisecond when the task is cancelled, and then checks the
  cancellation so that the text written so far is never taken for an answer. `RealModelTests.cancelledCallLeavesAtOnce`
  measures it. The framework does not show whether the model stops writing once its stream is dropped, so a call that
  timed out can still load the machine for a moment; that part is not under the app's control.

### Consequences of the addendum

- Good: a fresh install pastes in about 0.13 s, and nothing loads the on-device model unless the user asked for cleanup.
- Good: a call that timed out frees the cleaner's queue at once, so the next cleanup does not wait behind it.
- Bad: the app no longer polishes text unless the user turns the switch on, and the Settings screen still describes the
  switch without the warning about time (its snapshots are recorded on the CI image).
- Bad: with cleanup on, a loaded Mac still misses the limit often (0 of 12 above) and the raw text is pasted after 2 s or
  more. Revisit the on-device model's speed, not the default, if that is to change.
