# 0006. Cloud requests cannot carry context

- Status: accepted
- Date: 2026-10-13

## Context and Problem Statement

Local cleanup may use text around the cursor and other app context. Cloud providers must receive only the transcript, the
style, and vocabulary. A runtime filter can be forgotten or regress silently.

## Considered Options

- One cleanup request type with fields removed at runtime for cloud providers.
- Two request types, where the cloud type has no field that can hold context.

## Decision Outcome

`CloudCleanupRequest` is a separate type with exactly the fields transcript, style, and vocabulary. Cleaners receive a
payload that is either `.local(LocalCleanupRequest)` or `.cloud(CloudCleanupRequest)`. A factory builds `.cloud` for every
cleaner whose locality is cloud, and cloud adapters throw if given `.local`. A reflection test pins the exact stored fields,
and a sentinel test proves that context text never reaches a cloud payload.

### Consequences

- Good: the boundary is enforced by the type system and by tests, not by discipline.
- Bad: a second request type and a small factory to keep in step with the local one.
