# Delta for Dictation Activation

## ADDED Requirements

### Requirement: Hold-to-talk

The system MUST start recording on hotkey key-down. When the key is released after being held for at least the hold threshold (default 300 ms), the system MUST stop recording and submit the dictation for processing.

#### Scenario: Held press is submitted

- GIVEN the state is idle and the hold threshold is 300 ms
- WHEN the hotkey goes down at t=0 and up at t=1200 ms
- THEN recording starts at t=0
- AND at t=1200 ms recording stops and the dictation is submitted

### Requirement: Tap discard and double-tap hands-free

A release before the hold threshold MUST be treated as a tap: the recording is discarded (no processing job, no history entry) and a double-tap window (default 350 ms) is armed. A second key-down inside the window MUST start a hands-free recording; the key-up of that second press MUST be ignored.

#### Scenario: Double tap starts hands-free

- GIVEN the state is idle
- WHEN the hotkey is tapped (down 80 ms, up) and pressed again 200 ms after the release
- THEN the first recording is discarded
- AND a hands-free recording starts and survives the second key-up

#### Scenario: Late second press is a new first press

- GIVEN a tap was released 500 ms ago
- WHEN the hotkey goes down
- THEN the press is evaluated as a first press (hold or tap), not as hands-free

### Requirement: Hands-free stop

A hands-free recording MUST end only by (a) the next hotkey key-down, which stops and submits; (b) Escape, which cancels; or (c) the 10-minute safety cap, which stops and submits and shows a notice. The system MUST NOT end a recording because of silence. The cap MUST apply to recordings of any mode.

#### Scenario: Hotkey stops hands-free

- GIVEN a hands-free recording is active
- WHEN the hotkey goes down
- THEN recording stops and the dictation is submitted
- AND the following key-up is ignored

#### Scenario: Long silence does not stop

- GIVEN a hands-free recording is active and no speech is detected
- WHEN 5 minutes pass
- THEN the recording is still active

#### Scenario: Safety cap

- GIVEN a hands-free recording started at t=0
- WHEN the clock reaches 10 minutes
- THEN recording stops, the dictation is submitted, and the overlay shows a cap-reached notice

### Requirement: Escape cancels

Escape MUST cancel the newest in-flight dictation (recording or processing), and a cancelled dictation MUST NOT insert text even if a later stage completes. Escape MUST be consumed only while a dictation is in flight; otherwise it MUST pass through to the frontmost app.

#### Scenario: Cancel while recording

- GIVEN a recording is active
- WHEN Escape is pressed
- THEN recording stops and nothing is inserted

#### Scenario: Cancel during transcription

- GIVEN a dictation is awaiting a recognizer result
- WHEN Escape is pressed and the recognizer then returns text
- THEN the text is discarded and no insertion occurs

#### Scenario: Escape when idle

- GIVEN no dictation is in flight
- WHEN Escape is pressed
- THEN the event is not consumed

### Requirement: Overlapping dictations

A hotkey press while an earlier dictation is still processing MUST NOT be dropped: a new recording starts. At most one recording MAY be active at a time, and processing and insertion MUST run in the order dictations were submitted.

#### Scenario: Press during processing

- GIVEN dictation A was submitted and is still processing
- WHEN the hotkey goes down
- THEN dictation B starts recording
- AND A's text is inserted before B's text

### Requirement: Start preconditions

Before opening the microphone the system MUST verify that Microphone permission is granted and that the selected recognizer is installed and, for a cloud provider, enabled with a key. On failure it MUST NOT record, MUST show an error with a remedy, and MUST stay idle. A recognizer that is installed but still loading MUST NOT block recording.

#### Scenario: Permission denied

- GIVEN Microphone permission is denied
- WHEN the hotkey goes down
- THEN no recording starts and the overlay shows an error pointing to permissions

#### Scenario: Model missing vs loading

- GIVEN the selected model is not installed
- WHEN the hotkey goes down
- THEN no recording starts and the error points to settings
- AND if the model is installed but loading, recording starts normally

### Requirement: Hotkey configuration

The default hotkey MUST be a keyed combination that works without Input Monitoring. Modifier-only or fn hotkeys MAY be offered and MUST stay inactive until Input Monitoring is granted. The system SHOULD show a status warning while Secure Event Input is active.

#### Scenario: Modifier-only without permission

- GIVEN the user selects a modifier-only hotkey and Input Monitoring is not granted
- WHEN the selection is applied
- THEN the hotkey is not armed and the settings state reports the missing permission

#### Scenario: Secure input active

- GIVEN Secure Event Input becomes enabled
- WHEN the status is evaluated
- THEN a warning that keyed shortcuts may not respond is exposed
