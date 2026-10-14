# 0016. Dictionary terms bias Parakeet through CTC rescoring

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

The user's dictionary reached only the cleaner. `ParakeetRecognizer` dropped `RecognitionOptions.vocabulary`, which the
speech spec allows ("Unsupported biasing"), so a spoken "Kaelthorn" came out as "Kyle Thorn" with or without the term, and
among fifty terms (`RealPipelineTests`, task 8a.9). The cleaner did not fix it either: it turned "maría gonzales" into
"María González" given the term, and left "Kyle Thorn" and "Akme" alone. A string-only post-pass cannot fix "Kyle Thorn"
for "Kaelthorn" either: their similarity is about 0.7, below any threshold that does not also rewrite common words.

FluidAudio 0.17.7 can rescore a Parakeet transcript against known terms: a second, smaller CTC model listens to the same
audio, and a word of the transcript is replaced by a term only when the audio fits the term better and the two look alike.
Parakeet v3 has no CTC head of its own, so this needs the separate `FluidInference/parakeet-ctc-110m-coreml` model. The
documentation of that model says it is English-only and warns that short terms that collide with common words over-fire,
so Spanish recall was unmeasured.

## Considered Options

- Leave the dictionary to the cleaner (the position before this decision).
- A string-similarity post-pass over the transcript, without audio.
- CTC rescoring with the separate CTC 110M model, for the dictionary terms only, behind a real-model gate.
- Replace Parakeet v3 with the hybrid TDT-CTC 110M model, which has a CTC head built in. It is English-only as a
  transcriber, which is not an option for Spanish dictation.

## Decision Outcome

CTC rescoring with the separate model, for the dictionary terms only. The gate had to pass on Spanish before the adapter
could merge, and it did.

**What runs.** `RecognitionOptions.boostTerms` carries the dictionary alone (as the vocabulary holds it: trimmed, without
repeats, within the limits). The names found around the cursor and on the screen stay in `vocabulary` for the cleaner: a
name that merely sits near the cursor is not one the user said. `LiveParakeetEngine` rescores `ASRResult.text` with its
token timings through `VocabularyBooster`, and returns Parakeet's text unchanged when the term list is empty (zero cost),
shorter than 5 characters per term, the clip is over 120 s, the model is not ready, or anything fails.

**The model.** `FluidInference/parakeet-ctc-110m-coreml`, pinned to the commit `accdafd8cf8a2ff1cabe3c11e54416b405d409aa`
(the head of `main` on 2026-10-14, files from 2026-03-28) through the same `ModelPinning` as the speech model, in the
app's own folder `~/Library/Application Support/Susurro/Models/parakeet-ctc-110m-coreml`. It is downloaded and loaded in
the background by the first dictation that has terms; that dictation and the ones before the model is ready are not
boosted, and a failed load is retried at most every five minutes. A folder that holds another commit is emptied before the
download, because FluidAudio's check for models on disk looks only for the files.

**No exception to the app-owned folder rule.** `VocabularyBoostingSession.init` reads the tokenizer from FluidAudio's
shared folder, which an app that pins revisions must not use. Its pieces are public, so `LiveBoostingModel` builds the
spotter, the tokenizer and the rescorer over the app's folder and repeats the one step of `rescore` that matters
(`ctcTokenRescore` with the size-aware thresholds of `ContextBiasingConstants`, default configuration).

**Cost.**

| | Cost |
| --- | --- |
| Download | 97.5 MB (99 MB on disk), once, only for a user who has dictionary terms |
| First load | 43 s here: the download and the Core ML compile; 0.3 s once compiled |
| Memory | about 130 MB while loaded (FluidAudio's figure, not measured here); kept until the app quits |
| Added time per dictation | a median 0.37 s on a 4.8 s clip (0.10 s without terms, 0.47 s with); the CTC model reads one 15 s window per call, so a short clip pays about the same |
| A user without a dictionary | nothing: no download, no load, no run |

**Gate** (`RealModelTests`, M1 Max, macOS 26.6.2, FluidAudio 0.17.7, voices Paulina and Mónica of the system `say`):

| Check | Result |
| --- | --- |
| Recall: "Kaelthorn" is in the text with the term and not without, 5 runs (both voices, with and without 1.5 s of lead silence, and a second sentence) | 5 of 5 (needed 4). Parakeet alone wrote "Kyle Thorn", "Kyel Thorn", "Caelton", "Kael Torn" |
| False replacements: the 5 s sentence with the dictionary `Kaelthorn`, `Acme`, `González`, both voices | 0 of 2 |
| False replacements: 5 more sentences with a wider dictionary (`Kaelthorn`, `González`, `Fernández`, `Susurro`, `Mapfre`, `Acme Corp`), both voices | 0 of 10 |
| Added time on the 5 s clip (median of 7 runs, models warm) | 0.37 s (needed under 0.5 s) |
| Term among 50 (`RealPipelineTests`) | recovered |

The English-only caveat did not show on Spanish speech for an invented name and for names with accents. It is not
proven for every Spanish word: a term with letters outside the tokenizer's alphabet may be spelled differently by the
tokenizer than it is said. The gate is the evidence; `RealModelTests` should be run again on every FluidAudio bump.

### Consequences

- Good: the dictionary fixes the case the cleaner could not, a name Parakeet splits or mishears, and it does so before the
  cleaner, which then sees the right spelling. It is local, and a dictation with no dictionary is unchanged.
- Bad: a first name that sounds like a dictionary surname is replaced by it. With `González` and `Fernández` in the
  dictionary, "Gonzalo" and "Fernando" became "González" and "Fernández" in 4 of 4 clips. That is the known limit of
  keyword spotting; the dictionary is the user's own list, and the replacement is as plausible to the audio as the word
  that was said. `RealModelTests.unrelatedSentencesAreLeftAlone` measures it and prints the count.
- Bad: the first dictation after a term is added is not boosted while the model downloads, and neither are the dictations
  during the download. Loading the model when the dictionary changes would remove that wait; it needs a way for the app to
  tell the recognizer, which the recognizer port does not have.
- Bad: 99 MB on disk and about 130 MB of memory for a user who keeps terms; 0.37 s on every dictation that has them.
- Bad: FluidAudio rebuilds a rescored transcript from its word timings, with single spaces. In the gate the rescored text
  kept its punctuation and accents, but the shape of a rescored transcript is FluidAudio's, not ours.
- Bounded: a clip over 120 s is not rescored, because the CTC model costs about 0.4 s per 13 s of audio (4 s for the longest
  clip it takes) and the time comes out of the transcription timeout, which a failure of the rescoring must not use up.
