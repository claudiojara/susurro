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

#endif
