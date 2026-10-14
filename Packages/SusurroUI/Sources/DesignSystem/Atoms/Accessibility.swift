import SwiftUI

extension View {
    /// What VoiceOver says for a view that has no text of its own. With no `label` the view is decoration and
    /// VoiceOver skips it.
    @ViewBuilder func described(by label: String?) -> some View {
        if let label {
            accessibilityLabel(label)
        } else {
            accessibilityHidden(true)
        }
    }
}
