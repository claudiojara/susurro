# 0004. GRDB for history, per-key UserDefaults for settings

- Status: accepted
- Date: 2026-10-13

## Context and Problem Statement

Dictation history needs durable, queryable records with explicit schema changes. Settings need to survive partial corruption
and be easy to fake in tests.

## Considered Options

- History: SwiftData, or GRDB (SQLite) with explicit migrations.
- Settings: one serialized blob, or one `UserDefaults` key per setting.

## Decision Outcome

History uses GRDB. A `DatabaseQueue` is `Sendable` and runs in memory under `swift test`, and migrations are explicit
and reviewable. SwiftData's `ModelContext` is not `Sendable` and its migrations are implicit.

Settings sit behind a `SettingsStore` port backed by one `UserDefaults` key per setting, named `<area>.<name>`. A corrupt
key falls back to its default and cannot damage the others.

A key is declared in code as `SettingKey(area:name:default:)`, which fixes the `<area>.<name>` form and the type of the
value. Basic values are stored as themselves, an enum as its raw value, and any `Codable` value as JSON data. The port
has two implementations, `UserDefaultsSettingsStore` and the `InMemorySettingsStore` fake, and one contract suite runs
against both.

### Consequences

- Good: fast in-memory repository tests; isolated failures for settings.
- Bad: one more dependency (GRDB); typed keys need a small amount of boilerplate.
