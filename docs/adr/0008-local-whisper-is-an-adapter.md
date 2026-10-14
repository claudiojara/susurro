# 0008. Local Whisper is an adapter for the user's existing install

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

Some users already run Whisper on their Mac, as a server (whisper.cpp, an OpenAI-compatible server) or as a command line
tool. Susurro could manage Whisper models itself, or it could talk to what the user has.

## Considered Options

- Bundle or download Whisper models and run them in the app.
- An adapter to the user's own install, over HTTP or a command line tool, with no model management.

## Decision Outcome

`LocalWhisperRecognizer` is an adapter. It manages no model, downloads nothing, and has no readiness to load: it is `ready`
when the user's server answers or the configured program can be run, and `notInstalled` when it does not. Parakeet v3
stays the default recognizer.

Two modes, chosen in the settings:

- `http` (the default) sends a multipart WAV to an address on this Mac. The address is checked where the request is made
  (`LoopbackEndpoint`: `localhost`, `127.0.0.1`, or `::1`, over http or https, with no credentials), and a redirect to
  another host is refused, so the audio cannot leave the Mac through this provider. An OpenAI-compatible server
  (`/v1/audio/transcriptions`) gets the model, the language, and the vocabulary as the prompt, and a `whisper.cpp` server
  (`/inference`) the same without the model.
- `cli` runs a program at an absolute path that exists and is executable. There is no shell: the executable is given by
  its path and the arguments as an array, and the only argument is the path of a temporary WAV file the app made, which
  only the user can read and which is removed when the run is over. A pinned language is in the environment variable
  `SUSURRO_LANGUAGE`, so a script of the user's can turn it into the flags of its tool. The run has a 60 s limit on the
  injected clock, is killed when the task is cancelled, and its output is read as it comes and bounded. A non-zero exit
  or an empty output is an error, and the audio is kept for a retry. The error names the status and never the output.

### Consequences

- Good: no model downloads or storage in the app, and the threat of a subprocess is closed by construction (no shell, a
  checked path, a bounded and killable run).
- Bad: the user has to run their own server or write a wrapper script, and what Whisper hears is whatever their install
  does. A tool that starts children can keep its output open after it exits, which the 60 s limit ends.
