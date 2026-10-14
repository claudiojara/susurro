import CoreTestSupport
import Domain
import Observation
import Synchronization
import Testing

@testable import Presentation

/// The menu shows what the permissions monitor knows, so these tests change the board the monitor reads and let it read.
@MainActor
@Suite("Menu model", .timeLimit(.minutes(1)))
struct MenuModelTests {
    private let bothGranted: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]

    @Test(
        "before anything is read the menu shows nothing as allowed, says nothing about dictation, and shows the model as preparing"
    )
    func initialContent() {
        let model = MenuModel(monitor: Rig([:]).monitor)

        #expect(
            model.content
                == MenuContent.make(
                    microphone: .notDetermined, accessibility: .notDetermined, restriction: nil,
                    readiness: .loading(progress: 0)))
    }

    @Test("the menu shows the statuses the monitor read")
    func showsTheMonitorsStatuses() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let model = MenuModel(monitor: rig.monitor)

        await rig.monitor.refresh()

        #expect(model.content.microphone.isGranted)
        #expect(!model.content.accessibility.isGranted)
        #expect(model.content.accessibility.title == "Accessibility: not allowed")
    }

    @Test(
        "a permission granted or revoked in System Settings shows after the monitor's next read, with no refresh here")
    func followsTheMonitor() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let model = MenuModel(monitor: rig.monitor)
        await rig.monitor.refresh()
        let before = model.content.accessibility.isGranted

        rig.board.set(.accessibility, to: .granted)
        rig.board.set(.microphone, to: .denied)
        await rig.monitor.refresh()

        #expect(!before)
        #expect(model.content.accessibility.isGranted)
        #expect(!model.content.microphone.isGranted)
    }

    @Test("a required permission that is missing turns the restriction on, naming it, and granting it turns it off")
    func restriction() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let model = MenuModel(monitor: rig.monitor)

        await rig.monitor.refresh()
        let clipboard = model.content.restrictionMessage
        rig.board.set(.microphone, to: .denied)
        await rig.monitor.refresh()
        let both = model.content.restrictionMessage
        rig.board.set(.accessibility, to: .granted)
        await rig.monitor.refresh()
        let off = model.content.restrictionMessage
        rig.board.set(.microphone, to: .granted)
        await rig.monitor.refresh()

        #expect(clipboard == "Dictated text goes to the clipboard until Accessibility is allowed.")
        #expect(
            both
                == "Dictation is off until Microphone is allowed. "
                + "Dictated text goes to the clipboard until Accessibility is allowed.")
        #expect(off == "Dictation is off until Microphone is allowed.")
        #expect(model.content.restrictionMessage == nil)
    }

    @Test("a denied permission that dictation does not need leaves the menu without a reason")
    func conditionalPermissionIsNotAReason() async {
        let rig = Rig(
            bothGranted.merging([.inputMonitoring: .denied]) { $1 }, needs: PermissionNeeds(modifierOnlyHotkey: true))
        let model = MenuModel(monitor: rig.monitor)

        await rig.monitor.refresh()

        #expect(model.content.restrictionMessage == nil)
    }

    @Test("a SwiftUI view that reads the content is told when the monitor reads a change")
    func contentIsObservable() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        let model = MenuModel(monitor: rig.monitor)
        await rig.monitor.refresh()
        let told = Mutex(false)

        withObservationTracking {
            _ = model.content
        } onChange: {
            told.withLock { $0 = true }
        }
        rig.board.set(.accessibility, to: .denied)
        await rig.monitor.refresh()

        #expect(told.withLock { $0 })
    }

    @Test("the model line follows the readiness the recognizer reports, until the stream ends")
    func observesReadiness() async {
        let model = MenuModel(monitor: Rig([:]).monitor)
        let (readiness, continuation) = AsyncStream.makeStream(of: RecognizerReadiness.self)
        let observing = Task { await model.observe(readiness) }

        continuation.yield(.loading(progress: 0.3))
        await waitUntil { model.content.modelLine == "Speech model: preparing… 30%" }
        continuation.yield(.ready)
        await waitUntil { model.content.modelLine == "Speech model: ready" }
        continuation.finish()
        await observing.value

        #expect(model.content.modelLine == "Speech model: ready")
    }

    @Test("a read of the permissions keeps the model line the recognizer reported")
    func readKeepsTheModelLine() async {
        let rig = Rig(bothGranted)
        let model = MenuModel(monitor: rig.monitor)
        let (readiness, continuation) = AsyncStream.makeStream(of: RecognizerReadiness.self)
        continuation.yield(.ready)
        continuation.finish()
        await model.observe(readiness)

        await rig.monitor.refresh()

        #expect(model.content.modelLine == "Speech model: ready")
        #expect(model.content.microphone.isGranted)
    }

    @Test("allowing a permission asks the monitor, which asks the system and then waits for the status to change")
    func allowRequestsThroughTheMonitor() async {
        let rig = Rig([.microphone: .notDetermined, .accessibility: .granted])
        let model = MenuModel(monitor: rig.monitor)
        await rig.monitor.refresh()
        let before = model.content.microphone.action

        await model.request(.microphone)

        #expect(before == MenuContent.PermissionRow.Action(kind: .request, title: "Allow Microphone…"))
        #expect(rig.board.requested == [.microphone])
        // The answer left the status as it was, so the next step is System Settings.
        #expect(
            model.content.microphone.action
                == MenuContent.PermissionRow.Action(
                    kind: .openSettings, title: "Open System Settings for Microphone…"))
    }

    @Test("while the system prompt is up the menu offers nothing for the permission")
    func nothingWhileThePromptIsUp() async {
        let checker = FakePermissionsChecker([.microphone: .notDetermined], gatedRequests: true)
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())
        let model = MenuModel(monitor: monitor)
        await monitor.refresh()

        let asking = Task { await model.request(.microphone) }
        await checker.requestEntered.wait()
        let whileUp = model.content.microphone.action
        checker.releaseRequest()
        await asking.value

        #expect(whileUp == nil)
    }

    @Test("a trip to System Settings from the menu keeps the item that opens it")
    func settingsTripKeepsTheItem() async {
        let rig = Rig([.microphone: .denied, .accessibility: .denied])
        let model = MenuModel(monitor: rig.monitor)
        await rig.monitor.refresh()
        let before = model.content.accessibility.action?.kind

        model.openSettings(for: .accessibility)

        #expect(before == .request)
        #expect(model.content.accessibility.action?.kind == .openSettings)
    }

    @Test("opening System Settings opens the pane through the monitor, which then follows the permission")
    func opensSettingsThroughTheMonitor() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let model = MenuModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        model.openSettings(for: .accessibility)

        #expect(rig.panes.opened == [.accessibility])
        #expect(rig.monitor.followUps[.accessibility] == .sentToSettings)
        #expect(rig.monitor.followUps[.microphone] == nil)
    }

    @Test("setting up opens the onboarding window")
    func setUpShowsTheOnboarding() {
        var shown = 0
        let model = MenuModel(monitor: Rig([:]).monitor, showOnboarding: { shown += 1 })

        model.setUp()
        model.setUp()

        #expect(shown == 2)
    }
}
