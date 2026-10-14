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

Vocabulary terms MUST be passed to the provider. The Parakeet provider MUST rescore its transcript against the user's dictionary terms with CTC keyword spotting when the dictionary is not empty; the terms found around the cursor and on the screen (context and OCR terms) are not boosted. A provider without biasing support MUST ignore the terms without error.

The rescoring MUST run on this Mac, with a second model that is downloaded only once a dictation has dictionary terms, from a pinned revision into the app's own model folder. Terms shorter than 5 characters MUST NOT be boosted. A dictation MUST NOT wait for that model: until it is ready, and whenever the rescoring is unavailable or fails, the transcript is the one Parakeet wrote. A dictation with no dictionary terms MUST NOT download, load, or run it.

#### Scenario: Unsupported biasing

- GIVEN a provider that does not support vocabulary
- WHEN it is called with 5 terms
- THEN transcription succeeds and the terms are ignored

#### Scenario: Mangled name

- GIVEN the dictionary holds "Kaelthorn" and the rescoring model is ready
- WHEN the user says "Mañana tengo una reunión con Kaelthorn" and Parakeet alone writes "Kyle Thorn"
- THEN the transcript reads "Mañana tengo una reunión con Kaelthorn"

#### Scenario: Terms that are not in the speech

- GIVEN the dictionary holds "Kaelthorn" and "González" and the rescoring model is ready
- WHEN the user says a sentence that holds neither
- THEN the transcript is identical to the one without the dictionary

#### Scenario: Context terms are not boosted

- GIVEN the vocabulary holds a dictionary term and a name found around the cursor
- WHEN the recognizer is called
- THEN only the dictionary term is offered for rescoring

#### Scenario: No dictionary

- GIVEN the dictionary is empty
- WHEN a dictation is transcribed
- THEN the rescoring model is not downloaded, loaded, or run

#### Scenario: Model not ready

- GIVEN the dictionary holds a term and the rescoring model is still downloading, or failed to load
- WHEN a dictation is transcribed
- THEN the dictation completes with the transcript Parakeet wrote

### Requirement: Language mode

The user MUST choose a language mode in settings: `fast` (the provider detects the language) or
`guaranteedSpanish` (the default: the dictation is Spanish and the transcript is guaranteed to be in it). The
choice MUST persist across launches.

In `guaranteedSpanish` mode the system MUST pass "es" to the provider as a hint, MUST NOT rely on the provider
honoring it, and MUST run every transcript through a language guard. A transcript has drifted when it contains the
provider's unknown-token marker, when more than 30% of its letters are not Latin letters, or when the on-device
language detector is at least 60% sure of another language and gives Spanish less than 30%. A Spanish transcript
with isolated foreign words MUST NOT count as drifted.

When a transcript has drifted the system MUST transcribe the same clip again with a recognizer that honors the
requested language (the system speech framework, locale `es`), if it is ready, and MUST use its text when that text
is not blank and has not drifted; the record MUST name the recognizer that wrote the text and the reason
`language-drift`. Otherwise the system MUST keep the first transcript with the unknown-token markers removed and the
reason `language-drift-unresolved`; the attempt MUST NOT fail for this reason.

In `fast` mode no language MUST be passed and the guard MUST NOT run.

#### Scenario: Default mode

- GIVEN a fresh install
- WHEN the language mode is resolved
- THEN it is `guaranteedSpanish`

#### Scenario: Hint passed, not trusted

- GIVEN `guaranteedSpanish` and a spy provider that ignores the language
- WHEN a dictation is transcribed
- THEN the provider receives language "es"
- AND the transcript still goes through the language guard

#### Scenario: Drift resolved

- GIVEN `guaranteedSpanish`, the provider returns "We big." for a Spanish clip, and the language recognizer is
  ready and returns "Muy bien."
- WHEN the transcript is handled
- THEN the raw text is "Muy bien.", the record names the language recognizer, and the fallback reason is
  `language-drift`

#### Scenario: Drift unresolved

- GIVEN `guaranteedSpanish`, the provider returns "<unk>Ghazda.<unk>", and the language recognizer is not ready
- WHEN the transcript is handled
- THEN the raw text is "Ghazda.", the fallback reason is `language-drift-unresolved`, and the attempt does not fail

#### Scenario: Spanish with English words

- GIVEN `guaranteedSpanish` and the transcript "Hice el pull request y el deploy quedó listo"
- WHEN the guard runs
- THEN the transcript is left as it is and no second recognizer runs

#### Scenario: Fast mode

- GIVEN the mode is `fast`
- WHEN a dictation is transcribed
- THEN the provider receives no language and no guard runs

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
