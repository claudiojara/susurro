import Observation

/// Runs `apply` now and again after each change of what it read, such as the interface language, for as long as the app
/// runs. It keeps AppKit text that SwiftUI does not draw, a window title, in the language the user picked.
@MainActor
func followLanguage(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in followLanguage(apply) }
    }
}
