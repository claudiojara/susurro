# 0014. Keep Spanish dictation in Spanish: a language mode, a drift guard, and a second recognizer

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

Parakeet v3 and Ultra detect the language themselves. They take no language token, and FluidAudio's `language:` hint only
filters by script (`TokenLanguageFilter`), so a pinned "es" does nothing between two Latin-script languages. On short or
hurried clips the model sometimes answers in English ("muy bien" as "We big."), or in another script or language. The
measurements are under UL.1 in the task list: with fast synthetic speech 12 to 16 percent of very short clips came back as
English words only. The user dictates in Spanish.

## Considered Options

- (a) Parakeet only. Fastest, but the language can drift.
- (b) Parakeet plus a guard: detect a transcript that is not in the pinned language, and transcribe the clip again with a
  recognizer that honors the language.
- (c) Only a recognizer that honors the language (the speech framework of macOS, Whisper, Canary).

## Decision Outcome

(b), chosen by the user's setting `recognition.languageMode`:

- `fast`: the recognizer detects the language itself. Option (a).
- `guaranteedSpanish` (the default): the language "es" is passed to the recognizer, and every transcript goes through
  `LanguageGuard`. A transcript has drifted when it holds the engine's `<unk>` token, when most of its letters are not Latin,
  or when `NLLanguageRecognizer` is at least 60 percent sure of another language and gives Spanish less than 30 percent. A
  Spanish sentence with English words ("pull request", "deploy") is Spanish to the detector and is left alone.
- When a transcript has drifted, `RecognitionRunner` transcribes the clip again with `AppleSpeechRecognizer`
  (`SpeechAnalyzer` and `SpeechTranscriber` with the `es` locale, on device, free), which is installed at launch. The
  history record names the recognizer that wrote the text and the reason (`language-drift`). If the second recognizer is not
  ready, fails, or is wrong too, the Parakeet transcript is kept, with `<unk>` removed and the reason
  `language-drift-unresolved`: the raw transcript is always a valid output.
- The settings screen writes the choice through `RecognitionSettings.languageMode`. The pipeline reads it through the
  `LanguagePreference` port.

Measured on this Mac (macOS 26.6.2): the on-device recognizer transcribed a 7 s Spanish sentence in 2.9 s on its first call,
with the Spanish assets already installed. That is the added latency, and only on the clips the guard flags.

### Consequences

- Good: Spanish stays Spanish without a slower model for every dictation; the guard costs time only on drifted clips; the
  second recognizer is independent of Parakeet, so it does not drift the same way.
- Bad: a user who dictates English in `guaranteedSpanish` mode gets the second recognizer's Spanish rendering of it, because
  the guard sees English and the second recognizer is asked for Spanish. The user who dictates in English switches the mode
  to `fast`.
- Bad: the detector is wrong for one or two words ("commit" reads as English). Those clips pay for the second recognizer.
