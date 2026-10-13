# Delta for UI Theming

## ADDED Requirements

### Requirement: Injected semantic Theme

Every visual value (color, typography, spacing, radius, motion, overlay geometry) MUST come from an injected Theme of semantic tokens (for example surface, accent, danger, body, overlay corner radius), not from globals or view literals. A complete default Theme defining every token MUST ship with the app.

#### Scenario: Different theme, different render

- GIVEN two Themes differing only in the accent color
- WHEN the same view state is rendered with each
- THEN the outputs differ only in accent-colored elements

#### Scenario: Default completeness

- GIVEN the bundled default Theme
- WHEN it is checked against the token list
- THEN no token is missing

### Requirement: Light and dark appearance

Each color token MUST have a light and a dark value. Appearance MUST follow the system or a user override, and changing it MUST re-resolve colors without relaunch.

#### Scenario: Appearance switch

- GIVEN a view rendered in light appearance
- WHEN the appearance becomes dark
- THEN each color resolves to its dark value

### Requirement: JSON theme loading

A Theme MUST be loadable from a versioned JSON file. Tokens omitted from the file MUST inherit the default Theme. Unparseable JSON, an unsupported schema version, or malformed token values MUST make the loader return the default Theme together with a reported error. The system SHOULD allow reloading a theme file without restart.

#### Scenario: Valid partial file

- GIVEN a JSON file that overrides only the accent color
- WHEN it is loaded
- THEN the accent changes, all other tokens equal the default, and no error is reported

#### Scenario: Invalid JSON

- GIVEN a file containing malformed JSON
- WHEN it is loaded
- THEN the default Theme is active and an error describing the failure is reported

#### Scenario: Reload

- GIVEN a loaded theme file is replaced by another valid file
- WHEN reload is requested
- THEN observers receive the new Theme

### Requirement: No visual literals in views

Presentation sources MUST NOT contain hard-coded colors, font sizes, spacing, radii, or animation durations. An automated test MUST scan them and fail on violations; structural values such as 0 MAY be allowlisted.

#### Scenario: Clean sources

- GIVEN the presentation sources
- WHEN the literal scan runs
- THEN it reports no violations

#### Scenario: Scanner detects a violation

- GIVEN a fixture view with a literal color and a literal corner radius
- WHEN the scan runs
- THEN both are reported

### Requirement: Replaceable overlay variants

The overlay look MUST be provided by a variant registered by id; a variant renders from the overlay state and the Theme. Selecting a variant by id MUST NOT require changes to activation, pipeline, or state-mapping code. An unknown id MUST fall back to the default variant with a reported error.

#### Scenario: Register a variant

- GIVEN a test variant "compact" is registered
- WHEN the overlay setting selects "compact"
- THEN the overlay host renders that variant for the same state values

#### Scenario: Unknown variant

- GIVEN the setting names an unregistered variant
- WHEN the overlay is resolved
- THEN the default variant is used and an error is reported

### Requirement: Deterministic presentational views

Presentational views MUST be pure functions of a plain state value, the Theme, and the appearance, with no access to the clock, randomness, permissions, audio, Accessibility, or network. Motion MUST be disableable so a fixed input yields a byte-identical rendering. Each overlay state MUST be renderable in light and dark for snapshot tests.

#### Scenario: Stable snapshot

- GIVEN the overlay recording state, the default Theme, light appearance
- WHEN it is rendered twice in test mode
- THEN the two renderings are identical

#### Scenario: State coverage

- GIVEN every overlay state in light and dark
- WHEN rendered without app services
- THEN each renders and produces a snapshot
