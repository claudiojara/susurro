import DesignSystem
import SwiftUI

/// The permissions of the onboarding, one row under the other in the order of the state. What a row's action does is
/// passed in, with the permission it belongs to.
struct PermissionChecklist: View {
    @Environment(\.theme) private var theme
    private let rows: [OnboardingRowState]
    private let onAction: (OnboardingPermission, OnboardingAction) -> Void

    init(_ rows: [OnboardingRowState], onAction: @escaping (OnboardingPermission, OnboardingAction) -> Void) {
        self.rows = rows
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: theme.spacing(.sm)) {
            ForEach(rows) { row in
                PermissionRow(row) { onAction(row.id, $0) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permissions")
    }
}

#Preview("PermissionChecklist") { PreviewMatrix { PermissionChecklist.Gallery() } }
