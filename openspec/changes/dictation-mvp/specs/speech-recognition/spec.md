# Delta for Speech Recognition

## ADDED Requirements

### Requirement: Provider protocol

Each recognizer MUST implement one protocol: given audio and options (language, vocabulary terms) it returns a transcript, is cancellable, and reports its locality (local or cloud) and readiness (not installed, loading with progress, ready). The pipeline MUST depend only on this protocol.

#### Scenario: Swap providers

- GIVEN two fake providers registered under different ids
- WHEN the selected provider id changes
- THEN the next dictation uses the newly selected provider with identical pipeline code

### Requirement: Default and optional providers

FluidAudio Parakeet v3 MUST be the default provider. A local Whisper provider and Deepgram (cloud) MAY be selected in settings. Selection MUST persist across launches.

#### Scenario: Fresh install

- GIVEN no provider setting exists
- WHEN the selected provider is resolved
- THEN it is Parakeet v3

### Requirement: Cloud opt-in boundary

A cloud provider MUST be unusable until the user enables it and a key is stored. Audio MUST NOT be sent to a cloud provider unless it is the enabled, selected provider. Keys MUST live in Keychain (service `app.tuminuta`) and MUST NOT appear in settings, history, or logs. The only context a cloud recognizer MAY receive is the extracted vocabulary.

#### Scenario: Default sends nothing

- GIVEN default settings and a spy network
- WHEN a dictation completes
- THEN no audio bytes are sent over the network

#### Scenario: Enabled without key

- GIVEN Deepgram is enabled but no key is stored
- WHEN a dictation is started
- THEN the start preconditions fail with a message to add a key

### Requirement: Vocabulary biasing

Vocabulary terms MUST be passed to the provider. A provider without biasing support MUST ignore them without error.

#### Scenario: Unsupported biasing

- GIVEN a provider that does not support vocabulary
- WHEN it is called with 5 terms
- THEN transcription succeeds and the terms are ignored

### Requirement: Language

Language MUST default to automatic detection and MAY be pinned by the user; a pinned language MUST be passed to the provider.

#### Scenario: Pinned Spanish

- GIVEN the language is pinned to Spanish
- WHEN a dictation is transcribed
- THEN the provider receives language "es"

### Requirement: Long audio chunking

Audio longer than the provider's maximum duration MUST be split at silence boundaries into chunks within the limit, transcribed, and joined in order.

#### Scenario: Ten-minute audio

- GIVEN a 10-minute recording and a provider limit of 60 s
- WHEN it is transcribed
- THEN every chunk is at most 60 s and ends on a silence boundary
- AND the transcripts are concatenated in chunk order

### Requirement: Empty results

An empty or whitespace-only transcript MUST end the attempt as no-speech, not as an error.

#### Scenario: Blank transcript

- GIVEN the provider returns "   "
- WHEN the result is handled
- THEN the attempt ends as no-speech and nothing is inserted

### Requirement: Failure, timeout, and fallback

Each recognizer call MUST have a timeout. On error or timeout the attempt MUST be marked failed with its audio retained and retriable. When a cloud provider fails, the system SHOULD retry once with the local default provider.

#### Scenario: Cloud outage

- GIVEN Deepgram is selected and its request fails
- WHEN the failure is handled
- THEN Parakeet transcribes the stored audio
- AND the history entry records the provider actually used

#### Scenario: Local failure

- GIVEN the local provider times out
- WHEN the timeout is handled
- THEN the attempt is stored as failed with audio and an error notice

### Requirement: Model readiness

The default provider MUST preload at launch (SHOULD) and show load progress. A dictation recorded while the model is loading MUST wait for readiness, with progress visible, before transcription.

#### Scenario: Recording during load

- GIVEN the model is loading at 40%
- WHEN a dictation ends
- THEN transcription starts only after readiness and the overlay shows progress
