import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// A model that records what the screen asks of it.
@MainActor
private final class SpyModel: OnboardingViewModeling {
    var state: OnboardingViewState
    private(set) var requests: [OnboardingPermission] = []
    private(set) var settingsOpened: [OnboardingPermission] = []
    private(set) var rechecks = 0

    init(_ state: OnboardingViewState) {
        self.state = state
    }

    func request(_ permission: OnboardingPermission) async { requests.append(permission) }
    func openSettings(_ permission: OnboardingPermission) { settingsOpened.append(permission) }
    func recheck() async { rechecks += 1 }
}

@MainActor
@Suite("Onboarding container")
struct OnboardingContainerTests {
    private let size = CGSize(width: 472, height: 520)

    private func container(_ model: SpyModel) -> OnboardingContainer {
        OnboardingContainer(model: model, onDone: {})
    }

    private func png(of view: some View, scheme: ColorScheme = .light) -> Data {
        SnapshotSupport.pngData(of: view, size: size, scheme: scheme)
    }

    @Test(
        "the container draws the state its model has: the screen of that state and no other",
        arguments: [OnboardingFixtures.Screen.fresh, .allGranted, .stale])
    func drawsTheModelsState(fixture: OnboardingFixtures.Screen) {
        let state = OnboardingFixtures.state(fixture)
        let screen = OnboardingScreen(state: state, onAction: { _, _ in }, onRecheck: {}, onDone: {})

        #expect(png(of: container(SpyModel(state))) == png(of: screen))
    }

    @Test("a model that has another state is drawn differently")
    func followsTheModel() {
        let model = SpyModel(OnboardingFixtures.state(.fresh))
        let before = png(of: container(model))

        model.state = OnboardingFixtures.state(.allGranted)

        #expect(png(of: container(model)) != before)
    }

    @Test("asking for a permission asks the model, and only for that permission")
    func requestReachesTheModel() async {
        let model = SpyModel(OnboardingFixtures.state(.fresh))
        let action = OnboardingAction(kind: .request, title: "Allow Accessibility")

        await OnboardingContainer.perform(action, for: .accessibility, on: model)

        #expect(model.requests == [.accessibility])
        #expect(model.settingsOpened.isEmpty)
    }

    @Test("opening System Settings opens the pane of that permission, and asks for nothing")
    func openSettingsReachesTheModel() async {
        let model = SpyModel(OnboardingFixtures.state(.fresh))
        let action = OnboardingAction(kind: .openSettings, title: "Open System Settings")

        await OnboardingContainer.perform(action, for: .microphone, on: model)

        #expect(model.settingsOpened == [.microphone])
        #expect(model.requests.isEmpty)
    }
}
