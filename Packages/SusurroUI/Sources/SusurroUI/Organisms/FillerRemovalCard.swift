import DesignSystem
import SwiftUI

/// The switch that removes hesitations and simple self-corrections from every dictation, by rule and without a model.
struct FillerRemovalCard: View {
    private let isOn: Bool
    private let onChange: (Bool) -> Void

    init(isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.onChange = onChange
    }

    var body: some View {
        SettingsCard(Copy.title) {
            SettingsToggle(Copy.toggle, detail: Copy.detail, isOn: isOn, onChange: onChange)
        }
    }

    private enum Copy {
        static var title: String { L10n.string("fillers.title", "Filler words") }
        static var toggle: String { L10n.string("fillers.toggle", "Remove filler words") }
        static var detail: String {
            L10n.string(
                "fillers.detail",
                "Drops hesitations such as “eh”, “em” or “erm”, and keeps only the correction in “at 2, no, at 3”. It runs on this Mac, with or without cleanup, and leaves words that can mean something, such as “um” or “like”."
            )
        }
    }
}

#Preview("FillerRemovalCard") { PreviewMatrix { FillerRemovalCard.Gallery() } }
