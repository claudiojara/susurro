import SwiftUI

/// A thin bar filled from the left to a level between 0 and 1, such as the input level of the microphone. It takes the
/// width it is offered.
public struct LevelBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.motionEnabled) private var motionEnabled
    private let label: String
    private let level: Double
    private let tint: Tint

    /// `label` is what VoiceOver says; the bar has no text of its own.
    public init(_ label: String, level: Double, tint: Tint = .accent) {
        self.label = label
        self.level = level
        self.tint = tint
    }

    /// The part of the bar that is filled: `level` from 0 to 1, and an empty bar for a number that is not one.
    static func shown(level: Double) -> Double {
        level.isFinite ? min(max(level, 0), 1) : 0
    }

    public var body: some View {
        let shown = Self.shown(level: level)
        Capsule()
            .fill(theme.swiftUIColor(.borderSubtle))
            .overlay {
                GeometryReader { bar in
                    Capsule()
                        .fill(theme.swiftUIColor(tint.color))
                        .frame(width: bar.size.width * shown)
                }
            }
            .frame(height: theme.spacing(.xs))
            .animation(theme.easing(.fast, motionEnabled: motionEnabled), value: shown)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Text(shown, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("LevelBar") { PreviewMatrix { LevelBar.Gallery() } }
