# 0034. The learning dictionary suggests corrected words, and never stores field text

- Status: accepted
- Date: 2026-10-15

## Context and Problem Statement

A name the recognizer mishears ("Kyle Thorn" for "Kaelthorn") is fixed by hand in the target app, again and again, until
the user adds it to the dictionary. Susurro already reads the focused field through Accessibility for its context, so it
can notice such a fix and offer the word. The risks are privacy (the field holds text the user never dictated) and
noise (rewordings, typo fixes, and common words offered as terms). How should corrections be found, filtered, and kept?

## Considered Options

- Auto-add corrected words to the dictionary.
- Suggest only, with re-reads at +5 s and +20 s, the next dictation's context, and a system-lexicon check
  (`NSSpellChecker`) to keep known words out.
- Suggest only, v1: one re-read at +5 s, the next dictation's context as the last chance, and no lexicon port.
- Watch with an `AXObserver`, or diff the history's raw and cleaned text.

## Decision Outcome

Suggest only, v1. After a dictation that was pasted (`InsertionOutcome.inserted`), `DictationPipeline` hands a
`CorrectionWatch` (actor, Pipeline) an `InsertionReceipt`: the final text, 80 characters on each side of the cursor as
anchors, the app, the category, and whether the field is secure. The watch re-reads the field once after 5 s on the
injected clock, only while the same process is in front. A correction found there ends the watch; otherwise the next
dictation's context, captured in the same app, is diffed as a last chance. Only the latest dictation is watched.

`CorrectionDiff` (TextShaping, pure) finds the dictation between its anchors (nearest the cursor when an anchor
repeats; gives up on a missing anchor or a field over 50,000 UTF-16 units), aligns the words with an LCS on a
case-folded key that keeps accents, and keeps only replacements of 1 to 3 words on each side. `SuggestionFilter`
accepts a corrected side of 5 to 40 characters, made of words of letters, digits, hyphens and apostrophes, not all
digits, not a stopword (the list is shared with `AnswerDetector` in `Stopwords`), not in the dictionary or the dismissed
list, within a normalized edit distance of 0.5 of what was heard, and that looks like a name: a capital letter, or the
`EntityTagger` calls it a proper noun. Without the lexicon, the capital letter is what keeps "recieve" → "receive" out;
a capitalized common word fixed at the start of a sentence can still be offered, and the user dismisses it once.
Multi-word terms ("Mary Anne") are allowed, since the dictionary accepts them.

Suggestions are a setting (`dictionary.suggestions`, at most 20, oldest evicted, repeats counted) beside
`dictionary.dismissed` and `dictionary.learnFromCorrections` (default on), behind a `DictionarySuggestionStore` port.
A suggestion keeps the corrected word, what the dictation wrote (already in the history), a count, and a date. The field
text and the anchors live in memory for the diff only; the diagnostics line says only why the watch ended. Nothing is
watched when learning or "use app context" is off, in a secure field, or in a terminal. The Settings › Dictionary tab
shows a "Suggested" card above the terms; Add goes through `DictionaryStore.add`, so the term feeds the recognizer's
boosting and the cleaner's vocabulary like any other.

Auto-adding was rejected: a wrong term biases every later dictation. The +20 s read and the lexicon port were left out
of v1 to keep the change small; they can be added behind the same watch and filter. `AXObserver` would watch every edit
of the field; diffing raw against cleaned text measures the cleaner, not the user.

### Consequences

- Good: names the user fixes by hand become one click to add, with no text of the field kept anywhere. Sentinel tests
  check that field text never reaches the settings store, the diagnostics, or the history.
- Good: the pure diff and filter are tested apart from the watch, and the watch runs on a fake clock and reader.
- Bad: a chat message sent before the 5 s read, and apps with no `AXValue` (Terminal, many Electron views), give no
  suggestion. The menu bar items for suggestions are left for a later change.
