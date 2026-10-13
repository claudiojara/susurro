# 0001. SPM-first hexagonal architecture, five packages

- Status: accepted
- Date: 2026-10-13

## Context and Problem Statement

Almost all behavior (activation, pipeline, text shaping, paste policy) must be testable with `swift test`, without a signed
app, permissions, models, or a network. Every system edge (audio, speech recognition, accessibility, pasteboard, hotkeys)
must be replaceable by a fake.

## Considered Options

- One package for everything.
- One package per module.
- Five packages split by dependency weight.

## Decision Outcome

Five local Swift packages with dependencies pointing inward:

- `SusurroCore`: Foundation only. Domain types, ports (protocols), pure logic, the pipeline, and test fakes.
- `SusurroPlatform`: adapters over Apple frameworks (audio, accessibility, pasteboard, hotkeys, persistence, permissions).
- `SusurroInference`: adapters for models and network providers.
- `SusurroUI`: design system and UI contracts. It imports no other Susurro package.
- `SusurroFeatures`: view models and the dependency graph that connect the others.

The app target holds `@main`, entitlements, and wiring only. Every package uses Swift 6 language mode and
`platforms: [.macOS(.v26)]`. Only `SusurroUI` and the app default to `@MainActor` isolation; Core stays nonisolated.

### Consequences

- Good: `swift test` on Core never builds heavy dependencies; boundaries are enforced by the manifests.
- Bad: five manifests to maintain; cross-package changes need a coordinated version of each.
