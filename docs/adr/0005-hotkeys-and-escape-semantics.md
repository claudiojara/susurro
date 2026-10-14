# 0005. Hotkey strategy and Esc semantics

- Status: accepted
- Date: 2026-10-13

## Context and Problem Statement

Dictation is driven by a global hotkey. Each extra permission raises onboarding friction, and a global Esc handler can break
other apps if it always swallows the key.

## Considered Options

- A broad event tap for every key.
- Carbon hotkeys through KeyboardShortcuts for keyed combos, plus a listen-only monitor for modifier-only keys.

## Decision Outcome

Keyed combos use KeyboardShortcuts (Carbon). They need no permission and work during Secure Event Input. A listen-only
`flagsChanged` monitor is added only for modifier-only or fn hotkeys, and only after Input Monitoring is granted. Until then
the hotkey stays unarmed and settings report the missing permission.

Esc is registered only while a recording or processing job is in flight, so it passes through to other apps when idle.
Esc cancels: the recording is kept as `cancelled` with its audio retained for retry, and nothing is inserted.

### Consequences

- Good: the default setup needs only Microphone and Accessibility.
- Bad: modifier-only hotkeys carry an extra permission and cannot work while Secure Event Input is active.

## Default hotkey: Control+Option+D

Hold-to-talk is the fixed keyed combo Control+Option+D until the hotkey becomes configurable. It was checked for collisions
on macOS 26.6.2:

- None of the 181 enabled system symbolic hotkeys (read with `CopySymbolicHotKeys`) uses key D with the Control and Option
  modifiers. The two entries on D are Option+Command+D (show or hide the Dock) and Control+Command+D (look up a word).
- AppKit's standard text key bindings have no Control+Option entries.
- Control+Option is the VoiceOver modifier, so VoiceOver's own VO+D command takes the key while VoiceOver is running.
  VoiceOver is off by default, and the configurable hotkey is the way out for those users.

Re-run this check before changing the default.

KeyboardShortcuts is pinned exactly at 3.1.0 (the latest release; it needs Swift tools 6.2 and macOS 10.15, so macOS 26 and Swift 6.4 are fine). Its 3.x API registers a combo defined in code by value, which is how the fixed default is registered: nothing is written to UserDefaults, so an earlier run cannot override the constant and no write can re-register the key while it is held. The configurable hotkey (2c) is read from the settings `hotkey.kind` and `hotkey.combo` and is still registered by value, so the same reasoning holds: the settings are the one place the combination lives, and a change of them re-registers the hotkey without a relaunch.
