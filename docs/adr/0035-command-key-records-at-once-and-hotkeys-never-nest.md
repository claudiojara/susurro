# 0035. The command key records at once, and modifier-only hotkeys never nest with another

- Status: accepted
- Date: 2026-10-15

## Context and Problem Statement

A review of command mode (ADR 0033) found two defects in how its hotkey starts a recording.

First, the command key-down awaited its preconditions and an Accessibility snapshot of the whole field (value, window
title, up to 12 parents for the page address) before the capture started. `RecordingSession` has no pre-roll, so the
first words of the instruction, said while that ran, were lost.

Second, a modifier-only hotkey is pressed as soon as its exact modifiers are down. Two hotkeys whose modifiers nest
(Control+Option for one role, Control+Option+Shift or Control+Option+D for another) fire the wrong role on the way to the
other one, and the validation refused only identical hotkeys.

## Considered Options

- Keep the read before the capture and make it faster.
- Start the capture at once and read the selection alongside it, deciding before the recording is queued.
- For the hotkeys: refuse nesting only between hotkeys that are listened to together (the command one only while
  command mode is on), or refuse it against every hotkey of the app, as duplicates already are.

## Decision Outcome

The command key-down starts the capture at once. Only the switch (`command.enabled`) is checked first, since it costs
nothing. Accessibility, the model's availability, and the selection run in a task alongside the capture, with the
reader's lighter `selectionSnapshot()` (secure flag, `AXSelectedText`, and the field with its range only when no selected
text is given; no window title, no page address). As soon as that task says the command cannot run, the recording ends
(`captureFailed` to the reducer, the file is thrown away) and the notice or error shows. Otherwise the coordinator waits
for it before the recording is queued, so a command never reaches the pipeline without its selection. A tap, or Esc on
a command with nothing to rewrite, keeps nothing.

A modifier-only hotkey whose modifiers are a subset of another hotkey's, or a hotkey that contains a modifier-only one's
modifiers, is refused (`HotkeyRejection.overlapsAnotherHotkey`), against every hotkey of the app, like duplicates. Two
keyed hotkeys never overlap. `HotkeyService` drops a command hotkey that overlaps the dictation one, as it drops an equal
one, so a pair stored before this rule keeps dictation working.

### Consequences

- Good: no words are lost at the start of an instruction; the Accessibility work at key-down is smaller.
- Good: no hotkey can start the wrong role.
- Bad: a command with nothing selected opens the microphone briefly before its notice shows.
- Bad: a modifier-only dictation hotkey such as Control+Option is refused while the command hotkey (default
  Control+Option+Shift+D) contains it, even with command mode off; the user changes the command hotkey first.
