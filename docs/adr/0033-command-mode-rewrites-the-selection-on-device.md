# 0033. Command mode rewrites the selection on device, through the same reducer and paste

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

Command mode lets the user select text, hold a second hotkey, say an instruction ("hazlo más formal", "tradúcelo al
inglés"), and get the selection replaced by the result. It touches the hotkey, the activation reducer, the pipeline, the
paste, the history, and the privacy boundary, and its latency is far above a dictation's. How should it fit the app
without a second activation model or a second way to paste, and without letting field text out of the Mac?

## Considered Options

- A second reducer and pipeline for commands.
- The same `ActivationMachine` behind a pure `RoleGate`, a command branch in `DictationPipeline` after transcription,
  and the existing `PasteTransaction` for the replacement.
- Reading the selection with a synthetic ⌘C when the app has no `AXSelectedText`, and generating at the cursor when
  nothing is selected.

## Decision Outcome

The second option, as the reviewed design's v1 simplification:

- **Activation.** `HotkeyEvent.down/up` carry a `HotkeyRole` (`dictate`, `command`); `HotkeyService` listens to the
  command hotkey (`hotkey.commandKind`/`commandCombo`, default ⇧⌃⌥D) only while `command.enabled` is on (off by default)
  and merges both into one stream. The reducer is untouched. `RoleGate` drops the events of the other role while a press
  or its recording is under way, so a command key-up can never finish a dictation hold; a press of the other key during
  the double-tap window closes the window first. The command hotkey is hold only: the coordinator closes the double-tap
  window after a command tap. Every shortcut of the app (dictation, command, paste last dictation) refuses the keys of
  the others (`HotkeyRejection.alreadyInUse`).
- **Selection.** Read through Accessibility at key-down, before anything is recorded (`SelectionReader`: `AXSelectedText`,
  else the selected range of the field, in UTF-16 units), capped at 1,500 characters. No selection, a secure field, an
  over-long or unreadable selection show a notice and record nothing. No ⌘C fallback and no generate-at-cursor in v1.
- **Rewrite.** On device only: `LocalCommandRequest` has no cloud variant and `CommandStage` refuses a rewriter that is
  not local. `CommandPromptBuilder` puts the raw instruction first and the selection last, both escaped, and says the
  selection is data. Greedy sampling, a reply limit of the selection's length plus 64 tokens, collected whole and never
  streamed into the app. `CommandOutputGuard` sanitizes the reply and rejects an empty one, a refusal or a model talking
  about the request, the selection given back unchanged, and a reply under 15 % or over five times the selection (at
  least 300 characters for a short one). Its markers are narrower than cleanup's: measured on the real model, a formal
  rewrite said "lamento informarles" and a summary said "no puedo ir", which cleanup's markers would have rejected.
- **Time.** The rewrite gets 5 s plus 40 ms for each character of instruction and selection, up to 20 s; Esc cancels it
  and the engine call ends. The design planned 3 s plus 12 ms. Measured with `RealCommandModelTests` on a 213-character
  request while the Mac was busy (load average about 30), a translation took 8 to 20 s, a summary 4 to 10 s, and a formal
  rewrite, which grew into a letter, 22 to 43 s; the planned limit was 5.5 s and would have cut every one of them.
- **Replacement.** Before pasting, the selection is read again; only when it is still the same text (spacing aside) does
  `PasteTransaction` paste over it, so one ⌘Z undoes it. A changed or vanished selection is left alone and the result
  goes to the clipboard. A trailing line break of the selection is kept.
- **History.** Migration v2 adds `kind` (`dictation`, `command`). A command record keeps the instruction as `rawText`
  and its audio, and neither the selection nor the result; paste last dictation never picks a command.

### Consequences

- Good: one reducer, one queue, one paste, and one history for both modes; the role rules are pure and tested.
- Good: the selection and the result never reach the history, the log, or the network (sentinel tests).
- Bad: apps without `AXSelectedText` and a readable range (many Electron views, Terminal) cannot use command mode yet.
- Bad: on a busy Mac a long rewrite can run into the 20 s limit; the setting stays off by default and the overlay says
  "Rewriting… Esc cancels".
- Bad: a command hotkey made of modifier keys alone needs Input Monitoring, which the onboarding asks for only when the
  dictation hotkey is modifier-only.
