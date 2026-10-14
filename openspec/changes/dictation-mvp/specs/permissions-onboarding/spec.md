# Delta for Permissions Onboarding

## ADDED Requirements

### Requirement: Permission status model

The system MUST expose the status (not determined, granted, denied) of Microphone, Accessibility, Input Monitoring, and Screen Recording through a single protocol, and MUST update it live without requiring a relaunch.

#### Scenario: Granted in System Settings

- GIVEN Accessibility is denied and the onboarding is open
- WHEN the user grants it in System Settings
- THEN the status becomes granted without relaunch

### Requirement: Required vs conditional permissions

Microphone and Accessibility MUST be required for dictation. Input Monitoring MUST be requested only when a modifier-only or fn hotkey is selected. Screen Recording MUST be requested only when OCR is enabled. Unneeded permissions MUST NOT be requested.

#### Scenario: Default setup

- GIVEN a keyed hotkey and OCR off
- WHEN onboarding runs
- THEN only Microphone and Accessibility are requested

#### Scenario: OCR enabled

- GIVEN Screen Recording is not granted
- WHEN the user turns on OCR
- THEN Screen Recording is requested and, if denied, OCR stays inactive with an explanation

### Requirement: Guided request flow

For each missing permission the onboarding MUST explain why it is needed, trigger the system request or open the matching System Settings pane, and show a waiting state until the status changes. Dictation MUST be disabled with a visible reason while a required permission is missing.

#### Scenario: Missing required permission

- GIVEN Microphone is denied
- WHEN the user opens the menu or presses the hotkey
- THEN the missing permission and a link to the settings pane are shown and no recording starts

### Requirement: Runtime revocation

If a permission is revoked while running, the system MUST detect it, disable the dependent features gracefully, and show a banner, without freezing or crashing.

#### Scenario: Accessibility revoked

- GIVEN the app is idle and Accessibility is granted
- WHEN it is revoked
- THEN the status updates and dictation is disabled with a reason

### Requirement: Stale-grant guidance

If a permission stays denied after the user returned from System Settings for a bounded time, the system SHOULD show troubleshooting steps (remove and re-add the app).

#### Scenario: Still denied

- GIVEN the user returned from System Settings and the status is still denied after the bounded time
- WHEN the time elapses
- THEN the remove-and-re-add guidance is shown

### Requirement: Onboarding completion

Onboarding MUST complete when all required permissions are granted and MUST NOT reappear unless one becomes missing.

#### Scenario: Already granted

- GIVEN all required permissions are granted at launch
- WHEN the app starts
- THEN onboarding is not shown

#### Scenario: Conditional denied

- GIVEN Microphone and Accessibility are granted, OCR is on, and Screen Recording is denied
- WHEN the app starts
- THEN onboarding is not shown, dictation works, and OCR reports inactive
