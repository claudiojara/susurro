# 0012. VAD placement: post-pass on the persisted file; the file stays untrimmed

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

Voice activity detection decides what the recognizer hears: where the speech starts and ends, whether anyone spoke at all,
and whether the microphone is silent. It can run while the audio is captured, dropping frames that hold no speech, or after
the recording is complete, on the file that was written.

## Considered Options

- Drop frames during capture, so only speech is written and held in memory.
- Write everything during capture, and run the detector once on the persisted file.

## Decision Outcome

The detector runs as a post-pass on the persisted file (`AudioRecordingStore.load`, then `VoiceActivityDetector.analyze`).
The recognizer input is the clip cropped to the speech span with 450 ms of pre-roll and 450 ms of hangover, clamped to the
recording (`SpeechSpan`). The file on disk is never trimmed.

- The durable audio stays complete, so a retry from the history can run again with a different detector, language, or
  provider, and a user can listen to what was really recorded.
- Detection on the whole file sees the context before and after each utterance, which a streaming detector working frame by
  frame does not.
- The capture path stays simple: it converts, writes, and measures levels. It cannot lose a word onset through a detector
  that decided too late.
- A recording with no speech is still stored (the audio is the evidence for "no speech" and "silent microphone"), and ends as
  a no-speech notice without calling the recognizer.

### Consequences

- Good: nothing the user said is ever dropped before it is stored; detection can improve without touching old recordings.
- Bad: the detector runs after the key is released, so its time (a few tens of milliseconds for Silero on a minute of audio)
  adds to the wait; a ten-minute recording is read back into memory once for analysis.
