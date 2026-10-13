# Running Susurro

Susurro is a menu bar app. Hold a key anywhere, speak, release, and the text is pasted at the cursor. Everything runs
on this Mac: the speech model is local, and nothing is sent to a service.

## Requirements

- An Apple silicon Mac with macOS 26 or later.
- Xcode 27 and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- About 650 MB of free disk space and a network connection for the first run, which downloads the speech model.

## Build and run

```sh
make bootstrap   # generates App/Susurro.xcodeproj
make run         # builds the app, quits a copy that is already running, and opens it
```

`make run` builds into `build/`. The app has no Dock icon: look for the waveform icon in the menu bar.

`make build` resolves the packages with SwiftPM first and then tells `xcodebuild` to use them as they are. This is on
purpose. `xcodebuild` resolves FluidAudio's binary artifact by itself, and on a Mac with several `github.com` entries in
the keychain it stalls on the keychain lookup, which waits for a prompt that nobody sees. SwiftPM can skip the keychain
(`--disable-keychain`); `xcodebuild` cannot. The pins are in `Packages/SusurroFeatures/Package.resolved`.

### Keeping the permissions between builds

A build signed ad hoc gets a new identity every time, and macOS then forgets the Microphone and Accessibility grants.
To keep them, sign with your own team: copy `App/Config/Local.xcconfig.example` to `App/Config/Local.xcconfig` (it is
ignored by git) and set `DEVELOPMENT_TEAM`.

## First run

1. **Microphone.** The system asks first. Allow it.
2. **Accessibility.** The system asks next, and sends you to System Settings > Privacy & Security > Accessibility.
   Turn Susurro on. Without it, the text is copied to the clipboard and not pasted, and the overlay says so.
3. **The speech model.** The first run downloads the Parakeet v3 model (about 600 MB, once) and compiles it for the
   Neural Engine. The download takes about a minute on a fast connection, and the compile about 25 seconds more. The
   compile is cached for the app's identity, so later launches load the model in under a second, until a macOS update or
   a cleared cache. The menu line and the overlay show the progress; you can already record meanwhile, and the
   transcription waits for the model.
   The model files live in `~/Library/Application Support/Susurro/Models`, pinned to one reviewed revision.

The menu bar menu shows the hotkey, one row for each permission (with an "Open System Settings" item while one is
missing), the state of the speech model, and Quit. It re-reads the permissions when the app becomes active and every
two seconds, so a permission you grant in System Settings shows without a relaunch.

## Dictate

Focus a text field in any app, **hold Control+Option+D**, speak, and release. The overlay at the bottom of the screen
shows what is happening and never takes focus. The text is pasted at the cursor, and the clipboard you had is put back.

Quitting from the menu waits a moment for a paste to finish and puts the clipboard back.

## Reading the log

The app logs to the unified log under the subsystem `dev.claudiojara.susurro`. It never logs what you said or any audio.

```sh
/usr/bin/log show --predicate 'subsystem == "dev.claudiojara.susurro"' --last 5m
```

(In zsh, `log` alone is a shell builtin: use `/usr/bin/log`.) A healthy launch reads `app launched`, `speech model:
prepare requested`, `speech model: loading`, `speech model: ready`, and, once the permission prompts are answered,
`permissions at launch: ...`. The first dictation adds `first tap buffer: N frames at R Hz`. Failures are logged as
errors, for example `dictation failed: timedOut.readiness` or `paste not completed: noRead`.

## Known limits

These are known and each has a later change:

- No cancel and no hands-free mode.
- One dictation at a time: a press while one is being processed is refused with a notice.
- The whole processing of a dictation (waiting for the model, transcribing, pasting) is capped at 200 seconds.
- Audio is not saved, so a dictation that fails is lost.
- A recording is capped at 60 seconds.
- No voice activity detection, so silence or noise can produce odd text, and silence gives "No speech heard".
- The paste is promised under clipboard markers and the old clipboard comes back after a quiet period of 200 ms with no
  new read, and not sooner than 1 s after the paste. An app that reads the text more than 1 s later can get the old
  clipboard. A clipboard manager that ignores the markers can look like an app that read the text.
- Keyboard layouts where V is not the key with code 9, such as Dvorak, paste the wrong key.
- The text is pasted as transcribed: no cleanup, no capitalization, no spacing.
- The hotkey is fixed.
- The overlay is unthemed, and there is no onboarding window.

## What still needs a person

The launch, the log lines, the model load, and the build are checked by script. These need a person at the keyboard (the
macOS permission prompts cannot and must not be answered by a script):

- [ ] Release Left Control and Left Option before the check; on one Mac they read as held at rest, and then the paste
      falls back to the clipboard.
- [ ] The Microphone prompt appears once and the Accessibility prompt appears once, in that order.
- [ ] The menu bar icon opens the menu, and a permission row turns to "allowed" within two seconds of granting it.
- [ ] Hold Control+Option+D in Notes, a text field in a browser, and Terminal, speak Spanish, and release: the text
      pastes in under 2 seconds, and what you had on the clipboard is back afterwards, rich content included.
- [ ] The overlay never steals focus: keep the caret in the field while it shows.
- [ ] A hold longer than 60 seconds shows the limit notice for a few seconds and still pastes what was said.
- [ ] A second press while a dictation is still processing shows "Still working on the last dictation".
- [ ] With another Apple device signed in to the same account and Universal Clipboard on, a dictation does not reach
      that device's clipboard (the app writes with the current-host-only option).
- [ ] Quit from the menu while a paste is under way: the clipboard you had comes back.
- [ ] `first tap buffer: N frames` in the log after the first dictation: write N in `tasks.md` (WS5.8).
