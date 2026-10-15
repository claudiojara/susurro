# 0038. Pause only scriptable players, by their own state

- Status: accepted
- Date: 2026-10-15
- Supersedes: [0031](0031-pause-media-with-the-media-key-and-coreaudio-process-output.md)

## Context and Problem Statement

ADR 0031 paused media by sending the play/pause media key whenever CoreAudio said that another process was outputting
sound. On a real Mac that started music the user had paused: the key is a toggle delivered to the system's "Now
Playing" app, and "some process outputs sound" was true without any music. Audio routing tools (Background Music, which
proxies all system output through its own process, BlackHole), apps that keep their output open while silent (Teams,
Mail, OrbStack), and AirPods switching to the hands-free profile when the microphone opens all make it true. When no
app is Now Playing, the key can even launch Music. Any false positive in the detection therefore starts playback, which
is worse than not pausing at all.

## Considered Options

- Keep the key and tighten the detection: count only known media apps (browsers, VLC, IINA) whose own process outputs,
  and exclude virtual devices, `coreaudiod`, our own process and system sounds.
- Ask each known player for its state through its scripting dictionary and send it its own `pause` and `play`; drop
  the key entirely.

## Decision Outcome

Ask the players. `MediaPauser` (core) takes a list of `MediaPlayerControlling` players. When a recording passes the
hold threshold and the setting is on, it asks each one for its state and pauses only those that answer `playing`,
remembering which. When the recording ends it sends `play` to exactly those. A player that is not open, is paused or
stopped, or cannot be asked (Automation denied, no answer in 2 s) gets no command.

`ScriptedMediaPlayer` (platform) supports Apple Music (`com.apple.Music`) and Spotify (`com.spotify.client`). It reads
`player state` (`pPlS`) and sends `pause` and `play` (`hookPaus`/`hookPlay`, `spfyPaus`/`spfyPlay`) as raw Apple Events
addressed to the running process by its PID, so no event can launch the app. Podcasts has no scripting dictionary, so
it is not supported.

The key fallback is dropped. Even a strict per-process check cannot tell which app the key reaches: a browser that
outputs sound for a call or a notification would make the key start a paused Music, or launch it. Videos in a browser
and other players are not paused, and the setting's description says which players are.

### Consequences

- Good: media the user had paused is never started, and an app that is not open is never launched.
- Good: `play` is not a toggle, so media the user resumed by hand during a long dictation stays playing.
- Good: no CoreAudio process scan and no posted events, so the feature no longer needs Accessibility.
- Bad: only Music and Spotify are paused.
- Bad: the first dictation that finds each player open shows the macOS Automation prompt ("Susurro wants access to
  control Music"). The app needs `NSAppleEventsUsageDescription` and, under the hardened runtime, the
  `com.apple.security.automation.apple-events` entitlement. A denied prompt only skips that player; the user can change
  it in System Settings > Privacy & Security > Automation.
