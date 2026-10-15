# 0037. Cloud keys are kept for the session, and local builds sign with a stable identity

- Status: accepted
- Date: 2026-10-15
- Amends: [0003](0003-app-identity-and-external-keychain.md) (the "never caches" rule)

## Context and Problem Statement

With Deepgram selected, every dictation made macOS ask for the login keychain password ("Susurro wants to use your
confidential information stored in 'app.tuminuta'"). Two things combined. The recognizer read the key from the Keychain
for each request, as ADR 0003 asked, so each dictation was a Keychain read that macOS could ask about. And the builds
from a fresh checkout or a worktree were signed ad hoc, so each rebuild was a new identity to macOS: the "Always Allow"
answer of the Keychain item, and the Microphone and Accessibility grants, did not survive a rebuild.

## Considered Options

- Keep reading the key per request and only fix the signing.
- Keep the key in memory for the session, read it once, in the background, when a cloud provider is selected and on.
- Copy the keys into a Keychain item the app owns.

## Decision Outcome

Keep the key in memory for the session. `SessionSecretCache` (Domain) wraps the Keychain store: a found key is kept
until a provider setting changes or the app quits; a missing key and a failed read are not kept. Asking whether a key
exists still goes to the Keychain for the attributes only, which hands nothing over and prompts for nothing. At launch,
and after each change of the recognizer, the cleaner, or a cloud provider's settings, the keys in use
(`SecretAccount.inUse(by:)`: the selected recognizer when it is Deepgram and on, the selected cleaner when cleanup is on
and the cleaner is a cloud one that is on) are read in the background, so the first dictation does not wait on the
Keychain and an unused provider is never read. Copying keys into an app-owned item is rejected: ADR 0003 keeps the app
from writing the user's key store, and the service `app.tuminuta` is not renamed.

`make build` signs with the first Apple Development identity of the login keychain and its team (the certificate's OU),
found at make time, so no personal identity is committed. Without one (CI) it signs ad hoc as before.
`CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` override it, and `CODE_SIGN_IDENTITY=-` forces ad hoc.

### Consequences

- Good: one Keychain read per account per session at most, and none for a provider that is not in use. With a stable
  identity, one last "Always Allow" lasts across rebuilds, and so do the privacy grants.
- Bad: a key lives in the app's memory for the session. A key changed in the Keychain is picked up only after a provider
  setting changes or the app restarts.
