# Delta for Recording Overlay

## ADDED Requirements

### Requirement: Non-activating panel

The overlay MUST be a non-activating, borderless panel that cannot become key or main, ignores mouse events, and is visible on all Spaces and over full-screen apps. Showing or hiding it MUST NOT change the frontmost app or focused element.

#### Scenario: Panel configuration

- GIVEN the overlay panel is created
- WHEN its configuration is inspected
- THEN it is non-activating, cannot become key or main, and ignores mouse events
- AND its collection behavior includes all Spaces and full-screen auxiliary

#### Scenario: Focus preserved

- GIVEN app X is frontmost with a focused field
- WHEN the overlay is shown and hidden
- THEN the frontmost app and focused element are still X's

### Requirement: Pipeline-driven state

The overlay content MUST be a pure function of the dictation pipeline state, covering: hidden, starting, recording (hold or hands-free), transcribing, polishing, inserted, notice (message), and error (message). The recording state MUST appear only after audio capture reports ready.

#### Scenario: Ready gating

- GIVEN a recording was requested
- WHEN no audio buffer has arrived yet
- THEN the overlay state is starting
- AND after the first buffer it is recording

#### Scenario: Cleanup stage

- GIVEN transcription finished and cleanup is running
- WHEN the state is mapped
- THEN the overlay state is polishing

### Requirement: Hands-free indication

The recording state MUST distinguish hands-free from hold-to-talk and MUST tell the user how to stop.

#### Scenario: Hands-free state

- GIVEN a hands-free recording is active
- WHEN the state is mapped
- THEN the overlay state is recording with hands-free set and a stop hint

### Requirement: Level meter throttling

The overlay MUST receive input-level updates no more often than 30 per second.

#### Scenario: Burst of levels

- GIVEN 100 level samples arrive within 100 ms
- WHEN updates are published
- THEN at most 3 are delivered to the view

### Requirement: Placement

The overlay MUST appear on the screen containing the focused window (main screen as fallback), horizontally centered, at the top or bottom edge per setting (default bottom).

#### Scenario: Multi-screen

- GIVEN two screens and the focused window is on the second
- WHEN the overlay frame is computed
- THEN it lies on the second screen at the configured edge

### Requirement: Auto-dismiss

Inserted, notice, and error states MUST dismiss without user interaction after a bounded delay; error states MUST stay visible longer than inserted. Errors MUST name the recovery path (history or permissions) since the overlay is not interactive.

#### Scenario: Success dismissal

- GIVEN the overlay shows inserted
- WHEN the success delay elapses
- THEN the overlay is hidden

#### Scenario: Error persists longer

- GIVEN the overlay shows an error
- WHEN the success delay elapses
- THEN the error is still visible and is hidden after the error delay
