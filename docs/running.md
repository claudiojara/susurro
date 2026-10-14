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

1. **The onboarding window.** It opens by itself while Microphone or Accessibility is missing, and not again once both
   are allowed. Each permission is a row with the reason Susurro needs it and one button:
   - **Microphone:** "Allow Microphone" shows the system prompt. Allow it.
   - **Accessibility:** "Allow Accessibility" shows the system prompt, which sends you to System Settings > Privacy &
     Security > Accessibility. Turn Susurro on. Without it, the text is copied to the clipboard and not pasted, and the
     overlay says so.
   A row turns to "Allowed" within a second of the permission being granted, and Done enables once both are allowed.
   If a permission stays "Waiting" or "Not allowed" 30 seconds after you came back from System Settings, the row shows the
   steps for it (switch it off and on, remove and add the app again). While Microphone is missing dictation is off, and
   while only Accessibility is missing it still records and the text goes to the clipboard; the menu and the window say
   which. The menu has a "Set up Susurro…" item that opens the window again, and a permission that is revoked later
   opens it again by itself. On a display too short for the window, the checklist scrolls and the buttons stay in view.
2. **The speech model.** The first run downloads the Parakeet v3 model (about 600 MB, once) and compiles it for the
   Neural Engine. The download takes about a minute on a fast connection, and the compile about 25 seconds more. The
   compile is cached for the app's identity, so later launches load the model in under a second, until a macOS update or
   a cleared cache. The menu line and the overlay show the progress; you can already record meanwhile, and the
   transcription waits for the model.
   The model files live in `~/Library/Application Support/Susurro/Models`, pinned to one reviewed revision.

The menu bar menu says what a missing required permission costs (dictation is off, or the text goes to the
clipboard), the hotkey, one row for each permission (with the item for the step that fits while one is missing: "Allow
Microphone…" when it was never asked, "Open System Settings for Microphone…" when it was refused, "Allow
Accessibility…" first for Accessibility), the state of the speech model, and Quit. The app reads the permissions when it becomes active and every second, so a
permission you grant or revoke in System Settings shows within a second, without a relaunch.

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
prepare requested`, `speech model: loading`, `speech model: ready`, and a line for each permission the first time it is
read (`permission microphone: unread -> granted`). A change later reads `permission accessibility revoked: granted ->
denied`. The first dictation adds `first tap buffer: N frames at R Hz`. Failures are logged as errors, for example `dictation failed: timedOut.readiness` or `paste not completed: noRead`.

## Known limits

These are known and each has a later change:

- No cancel and no hands-free mode.
- One dictation at a time: a press while one is being processed is refused with a notice.
- The whole processing of a dictation (waiting for the model, transcribing, pasting) is capped at 200 seconds.
- Audio is not saved, so a dictation that fails is lost.
- A recording is capped at 60 seconds. The hold stops listening there, and the text is pasted once the keys are
  released, or after 12 seconds if they never are (it then lands on the clipboard if the keys are still down).
- No voice activity detection, so silence or noise can produce odd text, and silence gives "No speech heard".
- The paste is promised under clipboard markers and the old clipboard comes back after a quiet period of 200 ms with no
  new read, and not sooner than 1 s after the paste. An app that reads the text more than 1 s later can get the old
  clipboard. A clipboard manager that ignores the markers can look like an app that read the text.
- Keyboard layouts where V is not the key with code 9, such as Dvorak, paste the wrong key.
- The text is pasted as transcribed: no cleanup, no capitalization, no spacing.
- The hotkey is fixed.
- The overlay is unthemed. The onboarding window grows with its rows and can run past the bottom of a small display.

## Checks that need no person

Some of the manual checks run without a keyboard, a microphone, or a prompt, against the real models and a speech
voice (`say -v Paulina`). They are off unless `SUSURRO_REAL_MODELS=1`, so `make test` and CI skip them. The first run
downloads the speech models (about 600 MB) into the app's model folder; Apple Intelligence must be on for the cleaner
checks, and `whisper-server`, `whisper-cli`, and a `ggml-*.bin` model in `~/.local/share/whisper-cpp/models` (or
`SUSURRO_WHISPER_MODEL`) must be installed for the Local Whisper ones. A check whose model or tool is missing is skipped.

    SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroFeatures --filter RealModelPipelineTests
    SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealModelTests
    SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealSocketBoundaryTests

The first one runs Silero on a CAF written by the recording store, the time from the release of the key to the text with
the real VAD and Parakeet, the dictionary term, and Local Whisper over HTTP and through a wrapper script. The second
holds the Parakeet and Apple Intelligence checks, including the tone of the same dictation in Mail, Slack, Terminal, and
ChatGPT. The third reads what the cloud cleaners send from a real socket. Each prints its numbers on lines that start
with `REAL-WORLD` or `REAL-MODEL`.

## What still needs a person

The launch, the log lines, the model load, and the build are checked by script. These need a person at the keyboard (the
macOS permission prompts cannot and must not be answered by a script):

- [ ] Release Left Control and Left Option before the check; on one Mac they read as held at rest, and then the paste
      falls back to the clipboard.
- [ ] The onboarding window opens at launch when a permission is missing (reset them with `tccutil reset Microphone
      dev.claudiojara.susurro` and `tccutil reset Accessibility dev.claudiojara.susurro`). "Allow Microphone" shows the
      system prompt once, "Allow Accessibility" shows the prompt that leads to System Settings, each row turns to
      "Allowed" within a second of the grant, Done enables when both are allowed, and the window is not there at the
      next launch. Before Microphone is answered, the menu item says "Allow Microphone…" and shows the same prompt.
- [ ] Revoke Accessibility in System Settings while the app runs: within about a second the menu says dictated text goes
      to the clipboard, the onboarding window opens with that banner, and the next dictation still records and leaves the
      text on the clipboard with the overlay notice.
- [ ] Revoke Microphone while the app runs: the menu and the banner say dictation is off, and the hotkey records nothing.
- [ ] Open System Settings from a row, leave Accessibility off for 30 seconds after coming back: the row shows the
      troubleshooting steps (and, with the toggle on but not read, the steps are the way out).
- [ ] On a small display, or at a low resolution (System Settings > Displays), open the window with the optional rows
      showing and troubleshooting steps open: the window fits the visible area, the checklist scrolls between the title
      and the buttons, and Check again and Done stay in view.
- [ ] The menu bar icon opens the menu, the "Set up Susurro…" item opens the window again, and a permission row turns to
      "allowed" within a second of granting it.
- [ ] Hold Control+Option+D in Notes, a text field in a browser, and Terminal, speak Spanish, and release: the text
      pastes in under 2 seconds, and what you had on the clipboard is back afterwards, rich content included.
- [ ] The overlay never steals focus: keep the caret in the field while it shows.
- [ ] A hold longer than 60 seconds stops listening at the limit, shows the limit notice, and pastes what was said
      once you release the keys (not before, and not to the clipboard).
- [ ] A second press while a dictation is still processing starts a new recording at once, and the first text is
      pasted before the second.
- [ ] With another Apple device signed in to the same account and Universal Clipboard on, a dictation does not reach
      that device's clipboard (the app writes with the current-host-only option).
- [ ] Quit from the menu while a paste is under way: the clipboard you had comes back.
- [ ] `first tap buffer: N frames` in the log after the first dictation: write N in `tasks.md` (WS5.8).
