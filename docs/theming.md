# Theming

Every color, type size, space, radius, duration, and the overlay geometry comes from a theme: data, not code. The model
and the loader are in `Packages/SusurroUI/Sources/DesignSystem`. The bundled default is
`Resources/DefaultTheme.json`, and it defines every token. The app does not read a themes folder yet: task 1f.3 wires
the store into the composition root.

## Theme files

A theme file is JSON. It lists only what it changes, and everything it leaves out comes from the default, key by key,
down to a single field of a token. This file changes the accent in light and dark, and the body size:

```json
{
  "schemaVersion": 1,
  "palette": { "ocean": { "light": "#0077B6", "dark": "#48CAE4" } },
  "colors": { "accent.primary": "ocean" },
  "typography": { "body": { "size": 14 } }
}
```

| Key | Holds |
|---|---|
| `schemaVersion` | Required. This build reads `1`. |
| `name` | Display name. |
| `palette` | Raw colors by name, each with `light` and `dark` as `#RRGGBB` or `#RRGGBBAA`. |
| `colors` | For each color token, the name of a palette entry. |
| `typography` | `size` in points, `weight` (`regular`, `medium`, `semibold`, `bold`), `design` (`standard`, `rounded`, `monospaced`, `serif`). |
| `spacing`, `radii` | Points. |
| `motion` | Durations in seconds, and `springResponse` and `springDamping`. |
| `overlay` | `width`, `cornerRadius`, `offset` (points from the screen edge), `edge` (`top` or `bottom`). |

A file is used whole or not at all. If it is not JSON, has another `schemaVersion`, holds a value of the wrong form (a
bad hex color, a number where a word belongs), names a token that does not exist (a typo), or points a color at a palette
entry that does not exist, the loader returns the default theme together with every error found. A new token added by a
later version of the app counts as unknown to an older one.

## Token naming rules

- **Semantic over palette.** Views ask for a role (`text.primary`, `status.error`), never for a color. Palette names say
  what the color looks like (`ink`, `blue`); token names say what it is for. Two tokens may share a palette entry, and a
  theme can change the one without the other.
- **Color tokens** are `<role>.<variant>`: lowercase words in camelCase, joined by one dot (`surface.overlay`,
  `text.onAccent`). **All other tokens** are one camelCase word (`md`, `bodyEmphasized`, `springResponse`).
- **A token is an enum case** in `Tokens/ThemeToken.swift`. The case is the key in camelCase (`textOnAccent`), and the
  raw value is the key in the file (`"text.onAccent"`). `ThemeTokenCatalog` is built from the cases, so there is no
  second list.
- **Scales grow.** `xs` to `xl` for spacing, `sm` to `lg` for radii, `fast` to `slow` for durations, and `caption` to
  `title` for type sizes. A test checks the order of the default.
- **Adding a token** means a case and a value in `DefaultTheme.json`; the default-theme test fails until both exist.
  **Renaming or removing one** breaks every theme file that uses it, so it needs a new `schemaVersion`.
- **`default` is reserved.** In the themes folder `default.json` is ignored: `default` always means the bundled theme.

## In code

Views read `@Environment(\.theme)`, a `ResolvedTheme` with the light or dark value of each color already picked.
`View.themed(_:override:)` provides it, following the system appearance unless the override is `.light` or `.dark`.
`ThemeLoader` is `nonisolated`, so files can be read off the main actor. `ThemeStore` keeps the theme in use and
publishes it through `updates()`. In debug builds `ThemeFileWatcher` calls `store.reload()` when a file in the folder
changes, which is hot reload.
