# Delta for Audio Capture

## ADDED Requirements

### Requirement: Capture format

Captured audio MUST be delivered as 16 kHz mono Float32 regardless of the input device's native format.

#### Scenario: Device at 48 kHz stereo

- GIVEN an input device producing 48 kHz stereo
- WHEN one second of audio is captured
- THEN the delivered audio is 16000 mono samples

### Requirement: Readiness signal

The capture MUST signal ready only on the first real input buffer, not when start is requested.

#### Scenario: Slow device

- GIVEN a device that delivers its first buffer 300 ms after start
- WHEN capture is started
- THEN ready is signaled at the first buffer, not before

### Requirement: Durable audio before processing

Every recording MUST be written to the recording store, incrementally while capturing. Recognition MUST NOT start until the audio is fully written and verified (readable, non-empty, duration within tolerance). If persistence fails the attempt MUST fail with an explicit error.

#### Scenario: Stored before recognition

- GIVEN a recording is stopped
- WHEN the pipeline proceeds
- THEN the recognizer is invoked only after the store confirms the verified file

#### Scenario: Store failure

- GIVEN the store rejects writes
- WHEN a recording ends
- THEN the attempt ends with an error and the recognizer is never invoked

### Requirement: Bounded memory

In-memory audio MUST be bounded independently of recording length (10-minute recordings supported).

#### Scenario: Long recording

- GIVEN a 10-minute recording at 16 kHz
- WHEN it is captured with a fake store
- THEN no more than 30 seconds of audio is held in memory at once

### Requirement: Voice activity detection

Voice activity detection MUST find speech segments in the persisted audio. The recognizer input MUST be trimmed to the speech span with 450 ms of pre-roll and 450 ms of hangover so word onsets are not clipped. The persisted file MUST remain untrimmed.

#### Scenario: Pre-roll kept

- GIVEN a recording with speech from 2.0 s to 5.0 s
- WHEN the recognizer input is prepared
- THEN it spans 1.55 s to 5.45 s
- AND the stored file still spans the whole recording

### Requirement: No-speech and silent-mic handling

If no speech is found, the attempt MUST end as no-speech: the recognizer is not invoked, nothing is inserted, and a notice is shown. If the signal is digital silence (RMS near zero) the notice MUST say the microphone appears silent. Audio is still stored.

#### Scenario: Silent room

- GIVEN a recording with only low noise and no speech
- WHEN the VAD finds no segments
- THEN the attempt ends as no-speech with a notice and no insertion

#### Scenario: Muted microphone

- GIVEN a recording of all-zero samples
- WHEN it is evaluated
- THEN the notice reports a silent microphone

### Requirement: Minimum duration

A hold shorter than 300 ms, measured by the timestamps of its key events, MUST be discarded without a history entry. A recording that was submitted MUST be processed whatever the length of its audio: the capture takes up to about 150 ms to deliver its first buffer, so the audio is always shorter than the hold, and a clip too short to hold speech ends as a no-speech notice. A recording that the user cancelled with Esc and that holds less than 300 ms of audio MUST be discarded without a history entry.

#### Scenario: Accidental blip

- GIVEN the key is held for 200 ms
- WHEN it is released
- THEN nothing is stored or processed

#### Scenario: Short word

- GIVEN the key is held for 400 ms and 250 ms of audio were captured
- WHEN it is released
- THEN the clip is processed, and if no speech is found the attempt ends as no-speech with a notice

### Requirement: Device failures

If no input device exists the capture MUST fail before recording. If the device disappears mid-recording, audio captured so far MUST be preserved and submitted with a notice.

#### Scenario: Disconnect mid-recording

- GIVEN 4 s have been captured
- WHEN the input device is removed
- THEN the 4 s are stored and processed, and the overlay shows a notice
