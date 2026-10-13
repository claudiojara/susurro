# 0007. swift-format, token lint test, snapshot tests

- Status: accepted
- Date: 2026-10-13

## Context and Problem Statement

The project needs consistent formatting, a guard against raw design values in views, and regression safety for UI that will
change often. SwiftLint is not installed, and snapshot images differ across OS and renderer versions.

## Considered Options

- SwiftLint with a custom rule, or `swift-format` plus a Swift Testing test.
- Previews only, or snapshot tests with references recorded on a fixed machine image.

## Decision Outcome

- Formatting: `swift-format` from the toolchain, configured in `.swift-format` (4 spaces, 120 columns, ordered imports).
  `make lint` runs it with `--strict` locally and in CI.
- Design values: a token-lint test scans the UI sources and fails on literal colors, fonts, spacing, radii, and durations
  outside the token files.
- Snapshots: swift-snapshot-testing on presentational views. References are recorded only by a CI job on the
  `xcode-27-arm64` runner image, never locally, so they stay deterministic.

### Consequences

- Good: no extra linter to install; the one custom rule is an ordinary test; UI regressions are caught.
- Bad: contributors cannot record snapshots locally, and the CI runner image must stay pinned.
