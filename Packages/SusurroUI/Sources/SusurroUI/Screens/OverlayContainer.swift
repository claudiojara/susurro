import SwiftUI

/// Puts the overlay in front of the code that drives it. It reads the state, the level and the selected style id of its
/// model, asks the registry for the style, and draws it. The model is observable, so a change to any of them redraws the
/// overlay without anything here asking for it. The style below knows neither the model nor the registry.
public struct OverlayContainer: View {
    private let model: any OverlayViewModeling
    private let registry: OverlayStyleRegistry

    public init(model: any OverlayViewModeling, registry: OverlayStyleRegistry) {
        self.model = model
        self.registry = registry
    }

    public var body: some View {
        let state = model.state
        if !state.isHidden {
            Self.style(for: model, in: registry).body(state: state, level: model.level)
        }
    }

    /// The style the model selects, which is the default one when the id is unknown (and the registry reports it).
    static func style(for model: any OverlayViewModeling, in registry: OverlayStyleRegistry) -> any OverlayStyle {
        registry.style(for: model.styleID)
    }
}
