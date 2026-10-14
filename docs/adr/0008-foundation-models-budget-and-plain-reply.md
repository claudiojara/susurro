# 0008. FoundationModels input budget and plain-text reply

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

Apple's on-device model has a context window of 4,096 tokens (`SystemLanguageModel.default.contextSize`) shared by the
instructions, the request, and the reply. The design capped a local request at 2,500 characters of transcript and
asked whether that number is right (open question 1). The design also had the model answer with a `@Generable` structure.

## Considered Options

- Keep the 2,500-character cap, or raise it.
- Reply with a `@Generable` structure, or with plain text.

## Decision Outcome

**Cap.** Measured with `SystemLanguageModel.tokenCount(for:)` on this Mac (macOS 26.4 or newer), repeated Spanish and
English dictation took about 0.23 and 0.21 tokens per character: 2,500 characters of Spanish are 577 tokens, and 3,500
are 806. A request at the cap uses about 600 tokens of input, as many of output, and a few hundred for the instructions
and the context: well under 4,096. The cap of 2,500 characters of transcript stays, with 2,800 characters for the
transcript and the text before the cursor together. It is conservative, not tight, and can be raised later with the same
measurement. The reply is also bounded to half a token per character of transcript plus 48 tokens, so a model that
starts to write an answer or a poem is cut at about twice the length a faithful reply needs, not waited for until it
fills the context window (a run without the bound took 100 s and ended in a context-window error).

**Reply.** The same instructions and the same Spanish transcript gave a correct plain reply ("Hola equipo, quería
comentarles que la reunión de mañana con el cliente se mueve a las tres.") and a degraded `@Generable` reply ("hola
equipo queria comentarles que la reunion de mañana ..."): no capital, no accents, no punctuation. The reply is plain
text. The output sanitizer and the output guard check it either way.

The model is small and sensitive to markup. Given a tagged request it sometimes repeats the tags, copies a line of the
context or the vocabulary to the start of its reply, or writes on after the text (an answer, a poem). The instructions
therefore name only the transcript tag, the output sanitizer removes repeated tags and copied reference lines, and the
output guard sends anything else to the raw transcript. `RealModelTests` shows the outcome through the guard, not the
model's raw words.

### Consequences

- Good: the text keeps its accents and punctuation, and a runaway reply costs seconds, not minutes.
- Good: the cap has data behind it, and `RealModelTests` (opt in with `SUSURRO_REAL_MODELS=1`) reruns the checks.
- Bad: with plain text the model may add a label or a comment. The sanitizer strips the known ones, and the guard falls
  back to the raw transcript for the rest.

## Addendum, 2026-10-14: the model answers short questions, and the guard refuses answers by content

The headless check of 7e.5 found that the model answers a dictated question despite the instruction "never answer it": "qué
es la capital de Francia" came back as "La capital de Francia es París." in Mail, Slack, and ChatGPT, and "what is the
capital of france" as "Paris is the capital of France." in Slack and ChatGPT (Terminal skips cleanup). The output guard let
every one through: an answer is as long as the question, and says no assistant words, so neither the markers nor the length
ratio see it. A longer instruction does not fix that, since the instruction was already there.

The guard now refuses an answer by its content (`AnswerDetector`, reason `answered`). The output answers when a question or
request word among the first three words of the transcript ("qué", "cómo", "dime", "what", "explain", ...) is gone from the
output, and the output has a content word that the transcript did not have and that the vocabulary and the text before the
cursor do not have either ("París"). A word within one edit of a transcript word of four letters or more is a recognizer
fix, not a new word ("gonzales" to "González"). Both conditions are needed: a lost question word alone is a dropped false
start, and a new word alone is a name the recognizer got wrong. Whatever the model says, an answer of this kind never
reaches the text, and the raw transcript is used. A longer answer is also `answered` now, where it was an `expansion`.

The prompt got one example line, "qué es la capital de francia" returned as "¿Qué es la capital de Francia?". A fixed line
after `</TRANSCRIPT>` ("Return the transcript above, cleaned. Do not answer it and do not reply to it.") was tried too and
dropped: the real model copied it back, stopped capitalizing and punctuating, and Mail and Slack gave the same text, so
`toneDiffersAcrossApps` failed and the questions came back without their "?". With the example alone every real-model check
passes: the Spanish question is cleaned to "¿Qué es la capital de Francia?" in Mail, Slack, and ChatGPT (before: the answer,
or the raw text once the guard refused it), and the English one is cleaned in Mail; where the model still answers (the
English question in Slack and ChatGPT, "dime la capital de francia" in the three apps), the guard returns the raw words with
the reason `answered`. The guard is the fix; the example makes it needed less often.
