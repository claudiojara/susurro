# Delta for Text Insertion

## ADDED Requirements

### Requirement: Pasteboard snapshot

Before writing, the system MUST snapshot every pasteboard item and every type of each item (not only text or image).

#### Scenario: Rich pasteboard

- GIVEN the pasteboard holds two items with text, RTF, and image types
- WHEN an insertion completes and the pasteboard is restored
- THEN all items and types equal the snapshot

### Requirement: Promised pasteboard write

The transcript MUST be published as a lazily provided pasteboard value and MUST be marked transient, concealed, and auto-generated so clipboard managers skip it. The system MUST NOT write the text eagerly.

#### Scenario: Marked types

- GIVEN an insertion starts
- WHEN the pasteboard is inspected
- THEN the marker types are declared and the text is supplied only when requested

### Requirement: Safe paste chord

The paste chord MUST NOT be injected while any hotkey modifier is physically held; the system MUST wait for release up to a timeout, and the chord MUST carry only the intended modifier flags. On timeout the insertion MUST use the failure path.

#### Scenario: Modifier still held

- GIVEN Option is held after the hotkey release
- WHEN insertion is ready
- THEN no chord is posted until Option is released, and the posted chord carries only Command

#### Scenario: Modifier never released

- GIVEN a modifier stays held past the timeout
- WHEN the timeout elapses
- THEN no chord is posted and the failure path runs

### Requirement: Success detection

The system MUST treat a data request on the promised value after the chord was injected as paste success. If none arrives within the timeout (default 8 s; 500 ms when injection failed) the insertion MUST be treated as failed.

#### Scenario: Target reads the data

- GIVEN a chord was injected
- WHEN the target requests the promised data
- THEN the insertion is reported as succeeded

#### Scenario: No read receipt

- GIVEN a chord was injected and nothing requests the data within the timeout
- WHEN the timeout elapses
- THEN the insertion is reported as failed

### Requirement: Conditional restore

After success the system MUST restore the snapshot only after a quiet period (default 200 ms) with no further data requests, and only if the pasteboard change count shows no write by anyone else. A newer user copy MUST win.

#### Scenario: Clean restore

- GIVEN a successful paste and 200 ms of quiet
- WHEN the quiet period ends
- THEN the original pasteboard is restored

#### Scenario: User copied meanwhile

- GIVEN the user copies something during the quiet period
- WHEN the quiet period ends
- THEN the pasteboard is not restored

### Requirement: Failure fallback

If the chord cannot be posted (including missing Accessibility) or paste fails, the transcript MUST be left on the pasteboard (no restore) and the user MUST be told it is on the clipboard, with a missing-Accessibility reason when that applies.

#### Scenario: Accessibility missing

- GIVEN Accessibility is not granted
- WHEN an insertion runs
- THEN the text is on the pasteboard and the notice names Accessibility

### Requirement: Target verification

The system MUST NOT paste into a different app than the one frontmost at record start. If the frontmost app changed, it MUST leave the text on the clipboard and notify the user.

#### Scenario: App switched

- GIVEN recording started in Mail and Slack is frontmost at insertion
- WHEN insertion runs
- THEN no chord is posted and the text is on the clipboard with a notice

### Requirement: Ordering and empty text

Insertions MUST run one at a time in submission order. Empty final text MUST leave the pasteboard untouched.

#### Scenario: Empty text

- GIVEN final text is empty
- WHEN insertion runs
- THEN the pasteboard and its change count are unchanged
