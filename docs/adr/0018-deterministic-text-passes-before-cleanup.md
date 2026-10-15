# 0018. Snippets, filler removal, and replacements are deterministic passes before cleanup

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

Cleanup by a model is off by default (ADR 0015), so a dictation is the recognizer's text with spacing and capitalization
for the field. Users still want three things that need no model: their own spellings ("jira" written as "Jira"), stored
texts inserted by a phrase (a signature, an address), and hesitations ("eh", "erm") and simple self-corrections ("a las 2,
no, a las 3") taken out. These have to be predictable, fast, and safe when the model is on too.

## Considered Options

- Ask the cleaner to do it, with the rules in the prompt.
- Deterministic passes in `TextShaping`, run by the cleanup stage before the cleaner, whether or not the cleaner runs.

## Decision Outcome

Deterministic passes, in this order, in `CleanupStage.run`:

1. A snippet whose trigger is the whole dictation (words compared without case, accents, or punctuation) replaces it.
   No other pass and no cleaner touch it, and the insertion shaper adds the spacing the field needs but keeps its case.
2. A trigger of two words or more said inside a dictation, as that exact phrase (no punctuation between its words), is
   expanded in place. A one-word trigger is not: a single word is said for other reasons too. A dictation with an inline
   snippet is not sent to the cleaner, which would rewrite the user's own text; the other passes skip the snippet text.
3. Filler removal (setting `cleanup.removeFillers`, on by default), skipped for the verbatim tone. Only spellings that are
   not words are removed: "eh", "em", "mmm", "hmm", "erm", "umm", "uhh", "uhm" and their stretched forms, and "este"
   before an ellipsis. "um", "uh", "like", "o sea", "bueno" stay, and so does an acronym in capitals ("ERM", "HM"). A
   self-correction is "X, marker, Y" with the marker between commas ("no", "digo", "mejor dicho"; apologies and asides
   such as "perdón", "sorry", "I mean" join clauses more often than they retract one, so they are not markers), where Y
   starts with the word X starts with, X is two to six words of the same clause, and Y starts with neither "no", "sí",
   "yes", "not" nor a personal pronoun ("I can't come, no, I have a meeting" is two statements). A text where nothing
   matched is returned unchanged, byte for byte.
4. Replacement rules (`dictionary.replacements`): whole words, case and accents ignored but ñ kept apart from n, longest
   rule first, one pass so a written form is never matched again.

The cleaner, when it runs, receives the text after the passes, and a cleaner fallback inserts that text, not the raw one.
The history keeps the recognizer's raw text. The written forms of the replacement rules that contain a letter join the
dictionary terms in the vocabulary, so the recognizer boosts them and the cleaner is told to keep them.

### Consequences

- Good: predictable output with cleanup off, rules the user can reason about, and well under 5 ms for a 200-word
  dictation (`TranscriptRulesTests`).
- Good: the snippet text reaches the field exactly as stored.
- Bad: conservative rules miss real fillers ("um", "o sea") and corrections without a shared first word ("Juan, no,
  Pedro"). The model, when on, can still remove them.
- Bad: a dictation with an inline snippet is never cleaned by the model.
