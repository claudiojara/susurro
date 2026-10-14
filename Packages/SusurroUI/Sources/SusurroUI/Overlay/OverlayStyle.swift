import SwiftUI

/// A look for the overlay. The overlay draws whatever style the user selected by id, from the state and the input level
/// and the theme alone; selecting another style needs no change to activation, the pipeline, or the mapping of states. A
/// new look is one file and one registration.
@MainActor
public protocol OverlayStyle {
    /// The id the setting `overlay.variant` selects it by.
    static var id: String { get }
    /// What the overlay shows for the state. It is not asked for a hidden state.
    func body(state: OverlayViewState, level: Double) -> AnyView
}

/// What went wrong in selecting a style.
public nonisolated enum OverlayStyleError: Error, Equatable, Sendable {
    /// The setting names a style nobody registered, and the default one is drawn instead.
    case unknownStyle(id: String)
}

/// The styles that can be selected, by id. The default one is always there, and it is what an id nobody registered gets.
@MainActor
public final class OverlayStyleRegistry {
    private var styles: [String: any OverlayStyle] = [:]
    private let fallback: any OverlayStyle
    private let report: (OverlayStyleError) -> Void

    /// Every error that was reported, in order, for a screen that lists them.
    public private(set) var reportedErrors: [OverlayStyleError] = []

    /// - Parameters:
    ///   - fallback: The style that an unknown id gets. It is registered under its own id.
    ///   - report: Gets each error as it happens. The registry also keeps them in `reportedErrors`.
    public init(
        fallback: any OverlayStyle = PillOverlayStyle(), report: @escaping (OverlayStyleError) -> Void = { _ in }
    ) {
        self.fallback = fallback
        self.report = report
        register(fallback)
    }

    /// The registry of the app: the pill.
    public static func standard(report: @escaping (OverlayStyleError) -> Void = { _ in }) -> OverlayStyleRegistry {
        OverlayStyleRegistry(report: report)
    }

    /// Adds a style under its id, replacing the one that had it.
    public func register(_ style: some OverlayStyle) {
        styles[type(of: style).id] = style
    }

    /// The style with this id. An id nobody registered gives the default style and is reported once per call.
    public func style(for id: String) -> any OverlayStyle {
        if let style = styles[id] { return style }
        let error = OverlayStyleError.unknownStyle(id: id)
        reportedErrors.append(error)
        report(error)
        return fallback
    }
}

/// The default look: a pill, as wide as the theme says, over the overlay surface.
public struct PillOverlayStyle: OverlayStyle {
    public static let id = "pill"

    public init() {}

    public func body(state: OverlayViewState, level: Double) -> AnyView {
        AnyView(OverlayHUD(state: state, level: level))
    }
}
