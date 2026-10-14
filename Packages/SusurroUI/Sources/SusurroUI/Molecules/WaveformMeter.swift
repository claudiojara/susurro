import DesignSystem
import SwiftUI

/// The input level of the microphone as a short stack of level bars that shorten from the top down, so that the shape
/// follows the voice. It takes the width it is offered, and it is one element for VoiceOver.
struct WaveformMeter: View {
    @Environment(\.theme) private var theme
    private let level: Double
    private let tint: Tint
    private let label: String

    /// How much of the level each bar of the stack shows, from the first to the last.
    static let weights: [Double] = [1, 0.7, 0.45]

    /// The level from 0 to 1, and no level for a number that is not one.
    static func shown(level: Double) -> Double {
        level.isFinite ? min(max(level, 0), 1) : 0
    }

    /// `label` is what VoiceOver says; the bars have no text of their own.
    init(level: Double, tint: Tint = .recording, label: String) {
        self.level = level
        self.tint = tint
        self.label = label
    }

    var body: some View {
        VStack(spacing: theme.spacing(.xs)) {
            ForEach(Self.weights.indices, id: \.self) { index in
                LevelBar(level: Self.shown(level: level) * Self.weights[index], tint: tint, label: label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(Self.shown(level: level), format: .percent.precision(.fractionLength(0))))
    }
}
