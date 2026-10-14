# Proposal: Dictation MVP

## Intent

Ship a clean-room, local-first macOS 26+ dictation app: solid baseline reliability plus context-aware "professional" output. Avoid known pitfalls: clipboard races, lost audio, empty LLM output, focus theft.

## Scope

### In Scope
- Hold-to-talk + double-tap hands-free; Escape cancels; non-activating overlay
- Mic capture (16 kHz mono) + Silero VAD; audio persisted before processing
- ASR protocol; FluidAudio Parakeet v3 default; optional local Whisper and Deepgram
- Context capture at record start: app/bundle id, browser URL (AX), text around cursor, selection
- Category x tone table (email, work chat, personal messaging, document, terminal, AI chat, other) by bundle id / URL host; manual override wins
- Vocabulary: proper nouns from context + optional Vision OCR + user dictionary
- Cleanup LLM: FoundationModels default; optional OpenAI-compatible/Anthropic; strict tagged prompt; safety net falls back to raw
- Cursor-aware spacing/capitalization
- Lazy-pasteboard paste, success detection, restore only if unchanged
- History (raw + cleaned + audio), permissions onboarding, settings, Keychain keys (service `app.tuminuta`)
- UI theming: the UI is expected to change heavily (screens, colors, overlay look), so all visuals are driven by an injected, JSON-loadable Theme with semantic tokens (light/dark), views hold no visual literals, the overlay style is a replaceable registered variant, and presentational views render deterministically from state (snapshot-testable)

### Out of Scope
- Command/agent mode, learning dictionary, meetings, in-app Whisper models, Sparkle

## Capabilities

### New Capabilities
- `dictation-activation`: hotkeys, activation state machine, cancel
- `recording-overlay`: non-activating status panel
- `audio-capture`: capture, VAD, durable audio
- `speech-recognition`: ASR provider protocol and providers
- `context-capture`: frontmost app, URL, cursor text, selection, OCR
- `style-resolution`: category/tone mapping and overrides
- `transcript-cleanup`: vocabulary, prompt, LLM, safety net, spacing
- `text-insertion`: reliable paste and pasteboard restore
- `dictation-history`: raw/cleaned/audio records, retry
- `permissions-onboarding`: Microphone, Accessibility, Input Monitoring, Screen Recording
- `ui-theming`: injected semantic Theme (tokens, light/dark, JSON loading), overlay variants, deterministic views

### Modified Capabilities
- None

## Approach

SPM-first: pure domain logic (state machine, style table, prompt builder, safety net, spacing) in local packages; every system boundary (audio, ASR, VAD, LLM, AX, pasteboard, hotkeys, Keychain) behind fakeable protocols; thin SwiftUI/AppKit app target. Raw transcript is always a valid output, so context and cleanup degrade gracefully.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `Packages/*` | New | Core + adapter packages (names in design) |
| `App/` | New | Menu bar app, overlay, settings, onboarding |

## Permissions

| Permission | Need |
|---|---|
| Microphone | Required |
| Accessibility | Paste events, AX context |
| Input Monitoring | Only for modifier-only/fn hotkeys |
| Screen Recording | Only for opt-in OCR |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| LLM rewrites/answers instead of cleaning | High | Tagged prompt, length-ratio safety net, raw fallback |
| AX context missing in Electron/web apps | Med | Treat context as optional; URL/bundle fallback |
| Parakeet first-load latency | Med | Preload, progress UI |
| Paste races / modifier leakage | Med | Promise pasteboard, wait for modifier release |
| Size exceeds review budget | High | Chained slices below |

## Slice Plan (chained PRs, each under 800 lines)

1. Package/app bootstrap, menu bar shell, permissions onboarding
2. Activation state machine, hotkeys, overlay
3. Audio capture, VAD, durable recording store
4. ASR protocol + Parakeet; raw dictation end to end
5. Reliable text insertion
6. Context capture + style resolution
7. Cleanup: prompt, FoundationModels, safety net, spacing
8. Vocabulary: dictionary, proper nouns, OCR
9. History UI, settings, optional providers

## Rollback Plan

Greenfield: revert the offending slice PR. Context and cleanup sit behind settings toggles; disabling them restores the raw-transcript path.

## Dependencies

- FluidAudio, KeyboardShortcuts, FoundationModels, Vision; Xcode 27 / macOS 26

## Success Criteria

- [ ] Spanish dictation pastes into the focused app in under 2 s after release (short utterances, with cleanup on)
- [ ] No dictation lost: audio saved for every attempt; raw shown when cleanup fails
- [ ] Output tone differs correctly between Mail, Slack, Terminal and an AI chat
- [ ] User clipboard intact after paste
- [ ] Core packages pass `swift test` with no model downloads

## Proposal question round (resolved by user)

1. **Hands-free stop**: hands-free mode stops only via the hotkey or Esc, with a 10-minute safety cap. There is NO silence-based auto-stop.
2. **History retention**: audio is kept for 7 days and then deleted. Raw and cleaned text are kept indefinitely.
3. **Cloud data boundary**: cloud providers (ASR or LLM) never receive the raw text around the cursor, the selection, or screenshots/OCR text. They receive only the extracted vocabulary (proper nouns) plus category and tone (and the transcript being processed). Audio goes to a cloud ASR only if the user explicitly enables that provider.
