# 0032. Live text partials are throttled, run only on an idle engine, and are dropped at key-up

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

The "Live text" overlay style shows the words while the user speaks. Parakeet v3 in FluidAudio 0.17.7 has no cheap
streaming mode for this model: `SlidingWindowAsrManager` re-runs the same offline encoder over overlapping 15 s windows
and needs an `AsrManager` of its own, and the encoder takes a fixed 15 s input, so a short clip costs about as much as a
full window. Whatever produces partials competes with the transcription that is pasted for the one engine. The pasted
text must stay the transcript of the whole recording, and partials must not make it slower.

## Considered Options

- FluidAudio's `SlidingWindowAsrManager` fed with the live audio.
- Re-transcribing the newest audio every second or so through the recognizer the app already has, throttled and
  cancelled at key-up.

## Decision Outcome

The second. `LiveTranscriptPreview` (Pipeline) transcribes the newest 12 s of the recording on a `.utility` task, one
partial at a time, 1 s after the previous one ended, and only once 0.5 s of new audio has arrived. It runs only when the
selected overlay style asks for the words (`OverlayStyle.showsLiveTranscript`) and the selected recognizer runs on this
Mac and can give partials (`PartialSpeechRecognizing`, which only Parakeet adopts); every other style and provider pays
nothing. `ParakeetRecognizer.transcribePartial` takes the engine only when no transcription runs or waits, and never
queues. The coordinator ends the preview as the recording ends, before the transcript is asked for: a partial that waits
is dropped, and the text of one already inside the engine is thrown away. The sliding-window manager would have loaded the
model a second time and run its own windows on top of the dictation's, for the same quality.

Measured with `RealModelTests.partialLatency` on an M1 Max, macOS 26.6.2, FluidAudio 0.17.7, Spanish synthetic speech:

| What | Median | Range |
| --- | --- | --- |
| One partial over a 12 s window | 309 ms | 234 to 485 ms |
| Transcript of a 15 s dictation, engine idle | 225 ms | 200 to 357 ms |
| The same, with the key up while a partial is in the engine | 431 ms | 378 to 740 ms |

### Consequences

- Good: the pasted text never depends on a partial. With the default style nothing changes: no partial runs, no audio
  is kept twice.
- Good: the throttle bounds the cost: at most one partial in flight, so the engine is busy about a quarter of the time
  while recording with Live text.
- Bad: a key-up that lands while a partial runs waits for it, which adds about 0.2 s (up to 0.5 s) to that dictation,
  because a Core ML prediction cannot be stopped once it started. Only users who pick Live text pay it.
- Bad: a partial sees only the last 12 s, so the panel shows the end of a long dictation, and the first word of the
  window is dropped because it may be cut in two.
