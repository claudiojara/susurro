import CoreTestSupport
import Domain
import Testing

@testable import Presentation

/// A window that counts how many times it was asked to show.
@MainActor
final class SpySurface: OnboardingSurface {
    private(set) var shown = 0

    func show() { shown += 1 }
}

/// The presenter opens the onboarding window when a required permission is missing, once the statuses are known, and when
/// one is revoked later. It watches the monitor, which the tests read by hand.
@MainActor
@Suite("Onboarding presenter", .timeLimit(.minutes(1)))
struct OnboardingPresenterTests {
    private let granted: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]

    private func start(_ rig: Rig) -> (surface: SpySurface, presenter: OnboardingPresenter, running: Task<Void, Never>)
    {
        let surface = SpySurface()
        let presenter = OnboardingPresenter(monitor: rig.monitor, surface: surface)
        return (surface, presenter, Task { await presenter.run() })
    }

    @Test("it opens the window at launch when a required permission is missing")
    func opensWhenSomethingIsMissing() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let (surface, _, running) = start(rig)

        await rig.monitor.refresh()
        await waitUntil { surface.shown == 1 }
        running.cancel()

        #expect(surface.shown == 1)
    }

    @Test("it stays closed at launch when the required permissions are granted, and opens for a revocation after that")
    func staysClosedWhenAllIsGranted() async {
        let rig = Rig(granted)
        let (surface, _, running) = start(rig)

        await rig.monitor.refresh()
        await rig.settle()
        let atLaunch = surface.shown
        rig.board.set(.accessibility, to: .denied)
        await rig.monitor.refresh()
        await waitUntil { surface.shown == 1 }
        running.cancel()

        #expect(atLaunch == 0)
        #expect(surface.shown == 1)
    }

    @Test("it does not open before the statuses are read, because nothing is known yet")
    func waitsForTheFirstRead() async {
        let rig = Rig([:])
        let (surface, _, running) = start(rig)

        await rig.settle()
        let before = surface.shown
        await rig.monitor.refresh()  // nothing is granted, so now it is known that something is missing
        await waitUntil { surface.shown == 1 }
        running.cancel()

        #expect(before == 0)
        #expect(surface.shown == 1)
    }

    @Test("a denied permission that dictation does not need does not open it")
    func conditionalPermissionIsNotEnough() async {
        let rig = Rig(
            granted.merging([.inputMonitoring: .denied]) { $1 }, needs: PermissionNeeds(modifierOnlyHotkey: true))
        let (surface, _, running) = start(rig)

        await rig.monitor.refresh()
        await rig.settle()
        // A revocation of a required permission still opens it, which shows the presenter was watching.
        rig.board.set(.microphone, to: .denied)
        await rig.monitor.refresh()
        await waitUntil { surface.shown == 1 }
        running.cancel()

        #expect(surface.shown == 1)
    }

    @Test("it opens once for a missing permission, however many reads find it missing")
    func opensOncePerEpisode() async {
        let rig = Rig([.microphone: .denied, .accessibility: .granted])
        let (surface, _, running) = start(rig)

        await rig.monitor.refresh()
        await waitUntil { surface.shown == 1 }
        await rig.monitor.refresh()
        await rig.monitor.refresh()
        await rig.settle()
        running.cancel()

        #expect(surface.shown == 1)
    }

    @Test("it opens again when a permission that was granted is revoked again")
    func opensForEachRevocation() async {
        let rig = Rig([.microphone: .denied, .accessibility: .granted])
        let (surface, _, running) = start(rig)
        await rig.monitor.refresh()
        await waitUntil { surface.shown == 1 }

        rig.board.set(.microphone, to: .granted)
        await rig.monitor.refresh()
        await rig.settle()
        let whileGranted = surface.shown
        rig.board.set(.accessibility, to: .denied)
        await rig.monitor.refresh()
        await waitUntil { surface.shown == 2 }
        running.cancel()

        #expect(whileGranted == 1)
        #expect(surface.shown == 2)
    }

    @Test("the user can open it from the menu whatever the permissions are")
    func showsOnRequest() async {
        let rig = Rig(granted)
        let (surface, presenter, running) = start(rig)
        await rig.monitor.refresh()

        presenter.show()
        running.cancel()

        #expect(surface.shown == 1)
    }
}
