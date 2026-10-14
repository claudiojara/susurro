# Delta for Dictation History

## ADDED Requirements

### Requirement: Record per attempt

Every attempt whose audio is stored MUST have a history record created when the audio is committed (before recognition) with: timestamp, duration, status (processing, succeeded, no-speech, failed, cancelled), raw text, cleaned text (if any), final text, providers used, fallback reason, app name, bundle id, URL host, category, tone, and audio reference. Records MUST survive relaunch. A cancelled attempt MUST keep its record and audio but MUST NOT be inserted. A history write failure MUST be logged and MUST NOT block or fail the attempt.

#### Scenario: Crash mid-pipeline

- GIVEN audio was committed and the app quits during recognition
- WHEN the app relaunches
- THEN a record exists with the audio, and it can be retried

#### Scenario: Cleanup fell back

- GIVEN cleanup failed and the raw transcript was inserted
- WHEN the record is read
- THEN it holds raw text, no cleaned text, and the fallback reason

#### Scenario: History write fails

- GIVEN the history database rejects a write
- WHEN a dictation runs
- THEN the failure is logged and the text is still transcribed and inserted

### Requirement: Text kept indefinitely

Raw and cleaned text MUST be retained with no automatic expiry.

#### Scenario: Old record

- GIVEN a record 400 days old
- WHEN the retention job runs
- THEN its text is intact

### Requirement: Audio retention of 7 days

Audio MUST be deleted 7 days after record creation; the record MUST remain and expose an audio-expired state. The job MUST run at launch and at least daily while running, and MUST retry failed deletions.

#### Scenario: Expiry

- GIVEN an 8-day-old record with audio
- WHEN the retention job runs
- THEN the file is deleted and the record shows audio expired

#### Scenario: Not yet expired

- GIVEN a 6-day-old record
- WHEN the retention job runs
- THEN the audio file remains

#### Scenario: Deletion fails

- GIVEN the file cannot be deleted
- WHEN the job runs and later runs again
- THEN the second run retries the deletion

### Requirement: Retry from audio

The user MUST be able to retry a record that has audio: recognition and cleanup re-run with the stored category and tone, the record is updated, and nothing is pasted. Retry MUST be unavailable, with a reason, when the audio expired.

#### Scenario: Retry a failure

- GIVEN a failed record with audio
- WHEN retry succeeds
- THEN the record becomes succeeded with new text and no insertion occurs

#### Scenario: Expired audio

- GIVEN a record with audio expired
- WHEN retry is requested
- THEN it is refused with an audio-expired reason

### Requirement: Copy and delete

The user MUST be able to copy raw or cleaned text, delete one record (including its audio), and delete all records.

#### Scenario: Delete one

- GIVEN a record with audio
- WHEN the user deletes it
- THEN the record and its audio file are gone

### Requirement: No context text stored

Records MUST NOT store text around the cursor, selections, or OCR text.

#### Scenario: Stored fields

- GIVEN a dictation captured with field text
- WHEN its record is inspected
- THEN none of that text is present
