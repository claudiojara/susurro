import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// A model with a fixed state and style id.
@MainActor
final class StubOverlayModel: OverlayViewModeling {
    var state: OverlayViewState
    var level: Double
    var styleID: String
    var transcript = ""

    init(state: OverlayViewState, level: Double = 0.5, styleID: String = PillOverlayStyle.id) {
        self.state = state
        self.level = level
        self.styleID = styleID
    }
}

/// A look that exists only in tests: it draws the words of the state and nothing else.
struct CompactOverlayStyle: OverlayStyle {
    static let id = "compact"

    func body(state: OverlayViewState, level: Double) -> AnyView {
        AnyView(Text(state.text ?? ""))
    }
}

@MainActor
@Suite("Overlay style registry")
struct OverlayStyleRegistryTests {
    private static let state = OverlayViewState.inserted(text: "Pasted")
    private let size = CGSize(width: 412, height: 120)

    private func png(of view: some View) -> Data {
        SnapshotSupport.pngData(of: view, size: size, scheme: .light)
    }

    @Test("the pill is registered, and it is the default")
    func pillIsThere() {
        let registry = OverlayStyleRegistry.standard()

        #expect(type(of: registry.style(for: "pill")).id == "pill")
        #expect(registry.reportedErrors.isEmpty)
    }

    @Test("a registered variant is selected by its id and the host draws it for the same state values")
    func registerAVariant() {
        let registry = OverlayStyleRegistry.standard()
        registry.register(CompactOverlayStyle())
        let compact = StubOverlayModel(state: Self.state, styleID: "compact")
        let pill = StubOverlayModel(state: Self.state)

        #expect(type(of: OverlayContainer.style(for: compact, in: registry)).id == "compact")
        #expect(
            png(of: OverlayContainer(model: compact, registry: registry))
                == png(of: CompactOverlayStyle().body(state: Self.state, level: 0.5)))
        #expect(
            png(of: OverlayContainer(model: pill, registry: registry))
                == png(of: PillOverlayStyle().body(state: Self.state, level: 0.5)))
        #expect(
            png(of: OverlayContainer(model: compact, registry: registry))
                != png(of: OverlayContainer(model: pill, registry: registry)))
        #expect(registry.reportedErrors.isEmpty)
    }

    @Test("selecting another variant changes what is drawn, with no change to the state")
    func switchingVariant() {
        let registry = OverlayStyleRegistry.standard()
        registry.register(CompactOverlayStyle())
        let model = StubOverlayModel(state: Self.state)
        let before = png(of: OverlayContainer(model: model, registry: registry))

        model.styleID = "compact"

        #expect(png(of: OverlayContainer(model: model, registry: registry)) != before)
    }

    @Test("an unknown id falls back to the default variant and reports the error")
    func unknownVariant() {
        var seen: [OverlayStyleError] = []
        let registry = OverlayStyleRegistry.standard { seen.append($0) }
        let model = StubOverlayModel(state: Self.state, styleID: "nope")

        let style = OverlayContainer.style(for: model, in: registry)

        #expect(type(of: style).id == PillOverlayStyle.id)
        #expect(registry.reportedErrors == [.unknownStyle(id: "nope")])
        #expect(seen == [.unknownStyle(id: "nope")])
    }

    @Test("a hidden state draws nothing, whatever the style")
    func hiddenDrawsNothing() {
        let registry = OverlayStyleRegistry.standard()
        let hidden = StubOverlayModel(state: .hidden)

        let blank = SnapshotSupport.pngData(of: Color.clear, size: size, scheme: .light)
        #expect(png(of: OverlayContainer(model: hidden, registry: registry)) == blank)
    }
}
