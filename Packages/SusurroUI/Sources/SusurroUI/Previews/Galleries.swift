import DesignSystem
import SwiftUI

// What the onboarding views look like, in one place: each gallery shows every state of one view. The previews draw
// these, and the snapshot tests draw the same fixtures one by one.
#if DEBUG

    extension PermissionRow {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(spacing: theme.spacing(.sm)) {
                    ForEach(OnboardingFixtures.Row.allCases, id: \.self) {
                        PermissionRow(OnboardingFixtures.row($0)) { _ in }
                    }
                }
            }
        }
    }

    extension Banner {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(spacing: theme.spacing(.sm)) {
                    Banner(OnboardingFixtures.shortBanner)
                    Banner(OnboardingFixtures.longBanner)
                }
            }
        }
    }

    extension PermissionChecklist {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(spacing: theme.spacing(.lg)) {
                    ForEach(OnboardingFixtures.Screen.allCases, id: \.self) { screen in
                        PermissionChecklist(OnboardingFixtures.rows(screen)) { _, _ in }
                    }
                }
            }
        }
    }

    extension OnboardingScreen {
        struct Gallery: View {
            @Environment(\.theme) private var theme
            private static let screens: [OnboardingFixtures.Screen] = [.fresh, .allGranted, .stale]

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    ForEach(Self.screens, id: \.self) { screen in
                        OnboardingScreen(
                            state: OnboardingFixtures.state(screen), onAction: { _, _ in }, onRecheck: {}, onDone: {})
                    }
                }
            }
        }
    }

    extension OverlayHUD {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(spacing: theme.spacing(.sm)) {
                    ForEach(OverlayFixtures.Fixture.allCases, id: \.self) {
                        OverlayHUD(state: OverlayFixtures.state($0), level: OverlayFixtures.level)
                    }
                }
            }
        }
    }

    extension WaveformMeter {
        struct Gallery: View {
            @Environment(\.theme) private var theme
            private static let levels = [0.0, 0.25, 0.6, 1.0]

            var body: some View {
                VStack(spacing: theme.spacing(.md)) {
                    ForEach(Self.levels, id: \.self) { WaveformMeter(level: $0, label: "Input level") }
                }
            }
        }
    }

    #Preview("OverlayHUD") { PreviewMatrix { OverlayHUD.Gallery() } }
    #Preview("WaveformMeter") { PreviewMatrix { WaveformMeter.Gallery() } }

    /// A model with a fixed state, for the preview of the container.
    @MainActor
    private final class PreviewModel: OnboardingViewModeling {
        let state: OnboardingViewState

        init(_ state: OnboardingViewState) {
            self.state = state
        }

        func request(_ permission: OnboardingPermission) async {}
        func openSettings(_ permission: OnboardingPermission) {}
        func recheck() async {}
    }

    #Preview("OnboardingContainer") {
        PreviewMatrix { OnboardingContainer(model: PreviewModel(OnboardingFixtures.state(.fresh)), onDone: {}) }
    }

#endif
