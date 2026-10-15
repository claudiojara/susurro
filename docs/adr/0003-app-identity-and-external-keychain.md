# 0003. Bundle ID and the external Keychain service

- Status: accepted
- Date: 2026-10-13

## Context and Problem Statement

Privacy grants (microphone, accessibility) attach to the app's signing identity and bundle ID. Separately, the user already
keeps provider API keys in a Keychain service created by another tool, and Susurro should not ask for them again.

## Considered Options

- Reuse the existing Keychain service name as the bundle ID.
- Use a separate bundle ID and read the existing Keychain service as an external source.

## Decision Outcome

The bundle ID is `dev.claudiojara.susurro` and never changes. The Keychain service `app.tuminuta` is an external,
pre-existing key source: the app reads accounts from it on demand (`deepgram`, `anthropic`, `openai-compatible`) and never
creates, writes, or logs a secret. ADR 0037 amends the caching rule: a key that was read is kept in memory for the
session.

### Consequences

- Good: the app identity is independent of the key store, and privacy grants survive updates.
- Bad: the app depends on a service it does not own. A missing key is a normal state that the UI must explain.
