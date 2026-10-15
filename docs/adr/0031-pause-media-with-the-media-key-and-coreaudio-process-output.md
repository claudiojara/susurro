# 0031. Pause media with the media key, detected through CoreAudio process output

- Status: superseded by [0038](0038-pause-only-scriptable-players-by-their-own-state.md)
- Date: 2026-10-14

## Context and Problem Statement

The user can ask Susurro to pause music or video while they dictate, and to resume it after. Doing that needs two
things: knowing whether something plays, and pausing exactly that. macOS has no public API for the system's "Now
Playing" state. MediaRemote, the private framework behind it, is undocumented, and since macOS 15.4 it refuses
`MRMediaRemoteGetNowPlayingInfo` and its siblings to processes that are not Apple's. Sending the play/pause media key
blindly would start playback when nothing was playing.

## Considered Options

- MediaRemote (private framework): reads Now Playing state and sends commands to the Now Playing app.
- AppleScript to known players (Music, Spotify): exact state, but one Automation prompt per app and only those apps.
- CoreAudio process objects (`kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunningOutput`, public
  since macOS 14.2) to tell whether another process outputs sound, plus the `NX_KEYTYPE_PLAY` media key posted as a
  system-defined event.

## Decision Outcome

CoreAudio process output plus the media key. It uses public APIs only, needs no permission beyond Accessibility, which
the app already has for pasting, and works with any player that answers the keyboard's play key.

`MediaPauser` (core, tested with fakes) owns the policy: when a recording starts and the setting is on, it asks whether
another process outputs sound and, only then, sends the key and remembers that it did. When the recording ends (finish,
cancel, or error) it sends the key again only if it paused, so media the user had paused stays paused. The setting
(`media.pauseWhileDictating`) is off by default.

### Consequences

- Good: no private framework, no entitlement, no Automation prompts; nothing is sent when nothing plays.
- Bad: "something outputs sound" is not "the Now Playing app plays". During a call, or with an app that keeps its
  output running while silent, the key goes to the Now Playing app, which may be paused, so it can start playback. The
  setting's description says the key may reach another app, and the feature stays opt-in.
- Bad: resuming is not re-checked. If the user resumes the media by hand during a long dictation, the second key pauses
  it again.
