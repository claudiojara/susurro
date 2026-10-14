# Theming

Every color, type size, space, radius, component size, duration, and the overlay geometry comes from a theme: data, not code. The model
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
| `sizes` | Points: the fixed dimension of a component (`statusDot` is the diameter of a status dot, `levelBar` the thickness of a level bar, `onboardingWidth` the width of the onboarding screen). |
| `motion` | Durations in seconds, and `springResponse` and `springDamping`. |
| `overlay` | `width`, `cornerRadius`, `offset` (points from the screen edge), `edge` (`top` or `bottom`). |

A file is used whole or not at all. If anything in it cannot be used, the loader returns the default theme together
with the errors, and a mistake in a file being edited shows up instead of leaving the old look. The loader reports
every problem it finds in one pass, in this order:

1. **Unknown keys**, at any depth: a misspelled group (`colours`), token (`spacing.huge`), or field
   (`typography.body.sizee`, `palette.blue.ligth`). A key the loader does not know would otherwise be skipped without a
   word. A new token added by a later version of the app counts as unknown to an older one.
2. **Bad values**, each with its path: not a number where a number belongs, a word that is not one of the choices
   (`weight`, `design`, `edge`), a color that is not `#RRGGBB` or `#RRGGBBAA`, a palette color with a part missing, or a
   number that JSON text can only spell as infinity (`-1e999`). The two colors of a palette entry are checked
   separately, so both are reported if both are bad; an entry that is not an object at all (`"ocean": "#0077B6"`) is
   reported once, for the entry.
3. **Colors that point at a palette entry that does not exist.** A color that points at an entry the file wrote but got
   wrong is not reported again: the error for the entry says what to fix.
4. **Numbers that are negative or not finite**: sizes, spaces, radii, durations, and the overlay geometry. Zero is
   allowed.

Some things stop the report early, because nothing after them can be read:

- Text that is not a JSON object is reported alone.
- A file that cannot be read is reported alone. Only regular files are read, or symlinks that lead to one: a pipe, a
  device, or a folder named `x.json` is never read, and the store does not list it as a theme. A file over 256 KB is
  refused with an error instead of being read.
- A missing or unsupported `schemaVersion` is reported alone, because a file of another version may have another shape.
- A file with more than 50 bad values is reported for the first 50, since the loader reads the whole file again for each
  one it finds.

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
- **Adding a group** (a new table of tokens, such as `shadows`) touches these places, and no others:
  1. `Tokens/ThemeToken.swift`: an enum of the tokens, whose `group` is the key in the file.
  2. `Tokens/Theme.swift`: a property of `Theme` with that same name. If a token is an object, its type gets an explicit
     `CodingKeys: CaseIterable` enum, since the loader reads the field names from it.
  3. `Resources/DefaultTheme.json`: a value for every case.
  4. `Tokens/ThemeTokenCatalog.swift`: a `Group` in `groups`, which says how to read the names a theme defines (and,
     for object tokens, `fields:`). The loader's check for unknown keys and the catalog counts follow from it.
  5. `Tokens/ResolvedTheme.swift`: a table and an accessor in `ResolvedTheme`, and, if the values are numbers, their
     paths in `Theme.numbers` so that negative or infinite ones are rejected.
  6. This file: the table of keys above.
  7. `DefaultThemeTests`: the test that ties each group to its `Theme` property and to its key in the file lists the
     group names, so it fails until the new one is added.
- **`default` is reserved.** In the themes folder `default.json` is ignored: `default` always means the bundled theme.

## In code

Views read `@Environment(\.theme)`, a `ResolvedTheme` with the light or dark value of each color already picked.
`View.themed(_:override:)` provides it, following the system appearance unless the override is `.light` or `.dark`.
`ThemeLoader` is `nonisolated`, so files can be read off the main actor. `ThemeStore` keeps the theme in use and
publishes it through `updates()`; an observer that is slow to read is given only the latest theme, not every one it
missed.

In debug builds `ThemeFileWatcher` calls `store.reload()` when a file in the folder changes, which is hot reload. The
folder does not have to exist: the watcher looks for it every two seconds until it does, and again if it is removed.
Failures to watch a file are logged (subsystem `dev.claudiojara.susurro`, category `ThemeFileWatcher`) and `state` says
whether it is watching. It waits through an injected `sleep`, so its tests decide when a debounce or a retry ends.

## Atoms

The atoms are in `Sources/DesignSystem/Atoms`. They take their color from a `Tint`, which is a role and not a color:

| Tint | Color token |
|---|---|
| `neutral` | `text.secondary` |
| `accent` | `accent.primary` |
| `recording` | `accent.recording` |
| `success` | `status.success` |
| `warning` | `status.warning` |
| `error` | `status.error` |

`TextLabel` and `Icon` take an optional tint, where none is the plain text color (`text.primary`). `Pill`, `StatusDot`, and
`LevelBar` take a tint. `ActionButton` takes a `Kind` instead (`primary`, `secondary`, `destructive`), because its fill,
its text, and its border are a fixed set for each kind. The text that VoiceOver says is always the argument `label:`: it is
optional for an icon and a dot, which can be decoration, and required for a level bar, which says something.

An atom asks for its own tokens and borrows none: the dot's diameter is `sizes.statusDot`, not a space; the thickness of a
bar is `sizes.levelBar`; the track behind its fill is `surface.track`; and the veil on a pressed button is `state.pressed`,
not the border color. A theme can then change the space between things, or the border, without resizing a dot or tinting
a track. `AtomTokenTests` changes the token an atom uses and the one it used to borrow, in separate themes, and looks at
the pixels. An animation takes a `DurationToken` (`fast`, `standard`, `slow`), so the numbers of the spring cannot be
passed as a duration, and the spring is `theme.spring(motionEnabled:)`.

## Contrast

The default theme meets WCAG 2 level AA (4.5:1) for every pair of text and background the app draws, in light and in
dark, and `ContrastTests` fails when a palette change breaks one. The pairs are the text roles (`text.primary`,
`text.secondary`) and the tints (as the text of a pill or a label) on `surface.window`, `surface.raised`, and
`surface.overlay`, and `text.onAccent` on the fills that carry it: `accent.primary`, `accent.recording`, and
`status.error`. `RGBAColor.contrastRatio(against:)` computes the ratio, with a translucent color taken as it looks over
what is behind it.

In dark appearance `text.onAccent` is the dark ink, not white. The accents (`accent.primary`, `accent.recording`,
`status.error`) are light enough there to be read as text on a dark surface, which the pills and the status lines do, and
white on a color that light is only 2.8:1. A dark accent would fix the button and break the pill, since both use the same
color. A theme file is not checked: a theme that changes the palette has to keep these pairs readable itself.

## Token lint

`TokenLintTests.sourcesAreClean` reads every Swift file in `Sources/DesignSystem` and `Sources/SusurroUI` and fails on a
visual value written in place of a token. The message names the file, the line, the rule, and the text of the line.

| Rule | What it flags | What to write instead |
|---|---|---|
| `colorInitializer` | `Color(`, `NSColor(`, `CGColor(`, `Color.init(`, `#colorLiteral(` | `theme.swiftUIColor(.textPrimary)` |
| `namedColor` | `Color.red`, `CGColor.white`, and a system color or style in a color position: `.foregroundStyle(.red)`, `.background(.white)`, `.tint(.blue)`, `color: .black`, `colors: [.red, .blue]`, `.foregroundStyle(.secondary)` (`Color.clear` and `.clear` are allowed) | `theme.swiftUIColor(.statusError)`. A system color ignores the theme. |
| `hexLiteral` | `0xFF8800`, `"#FF8800"` | A palette entry in `DefaultTheme.json` and the token that points at it |
| `fontSize` | `.system(size:`, `.custom(_, size:`, `NSFont.systemFont(ofSize:`, `NSFont(name:size:)` | `theme.font(.body)` |
| `spacing` | a number in `padding`, `frame`, `offset`, `lineSpacing`, `tracking`, `Spacer`, `CGSize`, `CGRect`, `EdgeInsets`, or in the expression after `spacing:` | `theme.spacing(.md)`, or `theme.size(.statusDot)` for the fixed size of a component |
| `cornerRadius` | a number in `cornerRadius`, or in the expression after a corner radius label (`cornerRadius:`, `topLeadingRadius:`) | `theme.radius(.md)` |
| `effectRadius` | a number as the radius of a shadow, a blur, or a gradient (`radius:`, `startRadius:`, `endRadius:`) | Nothing yet: these have no token. Add a group (see "Adding a group") before using one. |
| `strokeWidth` | a number as `lineWidth:`, or in `border` | Nothing yet: use the default hairline, or add a token for the width. |
| `animationDuration` | a number as `duration:`, `blendDuration:`, `delay` | `theme.easing(.fast, motionEnabled:)` |
| `animationSpring` | a number as `response:`, `dampingFraction:`, `bounce:`, `extraBounce:`, `stiffness:`, `damping:`, `mass:` | `theme.spring(motionEnabled:)`, which is built from the tokens `springResponse` and `springDamping` |
| `visualConstant` | a number assigned to a `CGFloat`, or to a constant named for a length (`static let cornerRadius: CGFloat = 16`, `let padding = 8`) | Ask the theme where the value is used, not in a constant |

An expression counts: `spacing: base * 2` and `cornerRadius: size / 2` are flagged for their `2`. Zero is allowed, because
no space and no radius is not a design choice. `Sources/DesignSystem/Tokens/ResolvedTheme+SwiftUI.swift` is the one file
that is not scanned: it is where a theme value becomes a SwiftUI one, so it is the one place that writes `Color(` and
`.system(size:`. The other files of `Tokens/` are scanned like any other, and anything else that has to turn a theme
value into a SwiftUI value goes in the bridge. A test (`theBridgeHoldsTheLiterals`) fails if another file of `Tokens/`
needs the allowance.

Only `Sources/DesignSystem` and `Sources/SusurroUI` are scanned. The skeleton views of `Packages/SusurroFeatures` still
hold literals (`SkeletonIndicatorView`, `SkeletonOverlayPanel`: sizes, margins, and a corner radius) and are not scanned:
the screens of PR 2d and 2e replace them, and they will be added to the scan then.

The scanner (`Tests/DesignSystemTests/TokenLint/LiteralScanner.swift`) reads text, not syntax. It skips comments and
the inside of strings, and it counts the text of a string interpolation as part of the string. It cannot know that a
helper's return value is a literal, so it checks what a view writes, not what it means.
