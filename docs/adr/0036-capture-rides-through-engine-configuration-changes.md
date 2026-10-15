# 0036. The capture rides through engine configuration changes

- Status: accepted
- Date: 2026-10-15

## Context and Problem Statement

With AirPods as the input, every dictation failed with "Could not record". The unified log showed why: the capture read
the headset's format (24 kHz mono, its call mode) and started the engine, and about 100 ms later, before the first
buffer, CoreAudio rebuilt the input route and `AVAudioEngine` posted `AVAudioEngineConfigurationChange`. The capture
source treated every configuration change as a removed device, so the stream ended with no audio. A Bluetooth headset
does this as its microphone opens, and an engine started right after such a route change can also refuse to start.

## Considered Options

- Keep ending the capture on a configuration change, and let the user hold the key again.
- Restart the engine in the device's new format and keep feeding the same stream; retry a failed start once.
- Hold off reading the format until the route settles (a fixed delay before every capture).

## Decision Outcome

Restart. On a configuration change `AVAudioEngineCaptureSource` removes the tap, stops the engine (the live engine is
replaced by a fresh one), flushes what the old converter held, then selects the chosen microphone again, reads the
format right before installing the tap, makes a new converter, and starts again, into the same stream. The capture ends
as `CaptureError.deviceRemoved` only when no input device is left, when a restart fails twice, or after four restarts in
one capture. A start that throws, of a new capture or of a restart, is tried once more after 250 ms; a stop during that
pause wins. Every engine failure is logged at error level with its domain and code only (`captureEngineFailed`), each
restart with the new rate and channel count (`captureReconfigured`), and a capture that gives up with a fixed reason
(`captureLost`).

The converter also stopped passing a mono buffer that differs from its format only in channel layout metadata straight
to `AVAudioConverter`, which refuses it; it is wrapped in the converter's format over the same memory.

### Consequences

- Good: dictation works with Bluetooth headsets, and a device plugged in or out mid-recording no longer loses the rest of
  the recording.
- Good: the log now says what the engine did, so a capture failure can be diagnosed from `log show`.
- Bad: a headset that switches modes adds the time of one restart to the start of the recording.
- Neutral: audio across a restart is joined from two converters, so a few samples at the seam are not filtered as one.
