# Delta for Context Capture

## ADDED Requirements

### Requirement: Asynchronous capture at record start

A context snapshot MUST be requested when recording starts and MUST NOT delay recording. The pipeline MUST wait for it at most a bounded deadline after stop and then proceed with whatever is available. A snapshot MUST be discarded if its dictation was cancelled or superseded.

#### Scenario: Slow context

- GIVEN the context source takes 5 s
- WHEN a 2 s dictation ends
- THEN recording was never delayed and the pipeline proceeds with an empty context after the deadline

#### Scenario: Cancelled dictation

- GIVEN a dictation is cancelled before its snapshot arrives
- WHEN the snapshot arrives
- THEN it is dropped

### Requirement: Snapshot content

The snapshot MUST contain: app name, bundle id, window title, URL (browsers only, read via Accessibility), text before the cursor, text after the cursor, selected text, and a secure-field flag. Text before/after the cursor MUST be bounded to 500 characters nearest the cursor, and the selection to 1000 characters.

#### Scenario: Bounds

- GIVEN a field with 5000 characters and the cursor in the middle
- WHEN the snapshot is taken
- THEN before and after hold at most 500 characters each, nearest the cursor

#### Scenario: Browser URL

- GIVEN a known browser is frontmost with a web page loaded
- WHEN the snapshot is taken
- THEN the URL is present, and for a non-browser app it is absent

### Requirement: Secure fields

For secure text fields no field text, selection, or OCR MUST be captured and the secure flag MUST be set.

#### Scenario: Password field

- GIVEN the focused element is a secure text field
- WHEN the snapshot is taken
- THEN text fields are empty, the secure flag is set, and OCR is skipped

### Requirement: Graceful degradation

Missing Accessibility trust, unsupported elements, or errors MUST yield a partial snapshot (at least app name and bundle id when available) and MUST NOT surface an error or block the dictation.

#### Scenario: Electron app

- GIVEN the focused element exposes no text attributes
- WHEN the snapshot is taken
- THEN it contains app name, bundle id, and empty text fields, and the dictation proceeds

### Requirement: App-context toggle

A setting "use app context" (default on) MUST control field text and selection capture. When off, only app name, bundle id, window title, and URL MUST be captured.

#### Scenario: Toggle off

- GIVEN "use app context" is off
- WHEN the snapshot is taken
- THEN before, after, and selection are empty and the bundle id is present

### Requirement: Opt-in on-device OCR

OCR MUST be a separate setting, default off. When on and Screen Recording is granted, the frontmost window of the captured app MUST be OCR'd on device. Without the permission OCR MUST be skipped silently. The result MUST be discarded if the frontmost app or window changed. OCR text MUST feed only local vocabulary extraction.

#### Scenario: Permission missing

- GIVEN OCR is on and Screen Recording is not granted
- WHEN the snapshot is taken
- THEN OCR is skipped with no error

#### Scenario: Window changed

- GIVEN OCR started for app A
- WHEN the frontmost app becomes B before it finishes
- THEN the OCR result is discarded

### Requirement: Context privacy lifetime

Field text, selection, and OCR text MUST live in memory only for their dictation; they MUST NOT be persisted or logged. Only app name, bundle id, and URL host MAY be retained.

#### Scenario: After the dictation

- GIVEN a completed dictation with a captured snapshot
- WHEN history and logs are inspected
- THEN no field text, selection, or OCR text appears
