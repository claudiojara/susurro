import SwiftUI

// What the atoms look like, in one place: each gallery shows every variant of one atom. The previews and the snapshot
// tests draw these same views, so there is one list of variants to keep.
#if DEBUG

    /// Every theme that ships with the app, in light and dark, for previews. The default is the only one for now.
    private let bundledThemes: [Theme] = [.default]

    /// A preview of `content` on the window color of each bundled theme, in light and in dark.
    struct PreviewMatrix<Content: View>: View {
        private let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            VStack(spacing: 0) {
                ForEach(bundledThemes, id: \.name) { theme in
                    HStack(spacing: 0) {
                        Panel(content: content).themed(theme, override: .light)
                        Panel(content: content).themed(theme, override: .dark)
                    }
                }
            }
        }

        private struct Panel: View {
            @Environment(\.theme) private var theme
            let content: Content

            var body: some View {
                content
                    .padding(theme.spacing(.lg))
                    .background(theme.swiftUIColor(.surfaceWindow))
            }
        }
    }

    extension TextLabel {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
                    ForEach(TypeToken.allCases, id: \.self) { TextLabel($0.rawValue, style: $0) }
                    ForEach(Tint.allCases, id: \.self) { TextLabel("\($0)", tint: $0) }
                }
            }
        }
    }

    extension Icon {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.md)) {
                    HStack(spacing: theme.spacing(.md)) {
                        ForEach(TypeToken.allCases, id: \.self) { Icon("mic.fill", style: $0) }
                    }
                    HStack(spacing: theme.spacing(.md)) {
                        ForEach(Tint.allCases, id: \.self) { Icon("circle.fill", style: .title, tint: $0) }
                    }
                }
            }
        }
    }

    extension Pill {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
                    ForEach(Tint.allCases, id: \.self) { Pill("\($0)", tint: $0) }
                }
            }
        }
    }

    extension StatusDot {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(spacing: theme.spacing(.md)) {
                    ForEach(Tint.allCases, id: \.self) { StatusDot($0) }
                }
            }
        }
    }

    extension LevelBar {
        struct Gallery: View {
            @Environment(\.theme) private var theme
            private static let levels: [Double] = [0, 0.25, 0.5, 0.75, 1]

            var body: some View {
                VStack(spacing: theme.spacing(.md)) {
                    ForEach(Self.levels, id: \.self) { LevelBar(level: $0, label: "Level") }
                    ForEach(Tint.allCases, id: \.self) { LevelBar(level: 0.6, tint: $0, label: "Level") }
                }
            }
        }
    }

    extension ActionButton {
        /// A row for each kind: at rest, pressed, and disabled.
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.md)) {
                    ForEach(Kind.allCases, id: \.self) { kind in
                        HStack(spacing: theme.spacing(.md)) {
                            ActionButton("\(kind)", kind: kind) {}
                            ActionButtonFace(kind: kind, isPressed: true) { Text("pressed") }
                            ActionButton("disabled", kind: kind) {}.disabled(true)
                        }
                    }
                }
            }
        }
    }

#endif
