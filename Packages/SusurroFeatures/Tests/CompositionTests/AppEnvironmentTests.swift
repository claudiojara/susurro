import CoreTestSupport
import DesignSystem
import Domain
import Pipeline
import Testing

@testable import Composition
@testable import Presentation

@MainActor
@Suite("App environment", .timeLimit(.minutes(1)))
struct AppEnvironmentTests {
    private static let pressTime = Duration.seconds(10)

    // MARK: Launch

    @Test("launch loads the model and asks for no permission: the onboarding does that")
    func launch() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .notDetermined, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the model to be prepared") { f.recognizer.calls.contains(.prepare) }
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }

        #expect(f.permissions.requested.isEmpty)
        #expect(f.diagnostics.events.first == .appLaunched)
        #expect(f.diagnostics.events.contains(.modelPrepareRequested))
        await f.environment.shutdown()
    }

    @Test("starting twice starts everything once")
    func startIsIdempotent() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .denied, .accessibility: .granted])
        f.environment.start()
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }
        await f.eventually("the model to be prepared") { f.recognizer.calls.contains(.prepare) }
        await f.eventually("the window") { f.window.shown >= 1 }
        await f.clock.waitForSleeps(1)
        for _ in 0..<50 { await Task.yield() }

        let launches = f.diagnostics.events.filter { $0 == .appLaunched }.count
        let prepares = f.recognizer.calls.filter { $0 == .prepare }.count
        #expect(launches == 1)
        #expect(prepares == 1)
        #expect(f.clock.pendingSleeps == 1)  // one permission poll
        #expect(f.permissions.statusReads == 2)  // the two required permissions, once
        #expect(f.themePreparations.value == 1)
        #expect(f.window.shown == 1)  // one presenter
        await f.environment.shutdown()
    }

    // MARK: Onboarding window

    @Test("the window opens at launch when a required permission is missing")
    func windowOpensAtLaunch() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .denied, .accessibility: .granted])
        f.environment.start()

        await f.eventually("the window") { f.window.shown == 1 }

        await f.environment.shutdown()
    }

    @Test("the window stays closed at launch when the required permissions are granted")
    func windowStaysClosed() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }
        for _ in 0..<50 { await Task.yield() }

        #expect(f.window.shown == 0)
        await f.environment.shutdown()
    }

    @Test("the window opens when a permission is revoked while the app idles")
    func windowOpensOnRevocation() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }
        await f.clock.waitForSleeps(1)

        f.permissions.set(.accessibility, to: .denied)
        f.clock.advance(by: .seconds(1))

        await f.eventually("the window") { f.window.shown == 1 }
        await f.environment.shutdown()
    }

    @Test("setting up from the menu opens the window")
    func menuOpensTheWindow() async {
        let f = AppEnvironmentFixture()

        f.environment.menu.setUp()

        #expect(f.window.shown == 1)
    }

    @Test("the window shows the environment's onboarding view model, in the environment's theme")
    func windowIsBuiltFromTheEnvironment() {
        let f = AppEnvironmentFixture()

        #expect(f.window.model === f.environment.onboardingModel)
        #expect(f.window.themes === f.environment.themeModel)
    }

    // MARK: Dictation through the whole graph

    @Test("holding the hotkey, speaking, and releasing pastes the text, and the overlay follows each step")
    func dictation() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        f.hotkeys.send(.down(at: Self.pressTime))
        await f.eventually("the starting indicator") { f.overlay.current == "Getting ready…" }
        f.capture.emit(AudioChunk(samples: [0.1, 0.2, 0.3]))
        await f.eventually("the recording indicator") { f.overlay.current == "Listening…" }
        f.hotkeys.send(.up(at: Self.pressTime + .milliseconds(1200)))
        await f.eventually("the pasted indicator") { f.overlay.current == "Pasted" }

        #expect(f.inserter.insertedTexts == ["hola"])
        #expect(f.overlay.messages == ["Getting ready…", "Listening…", "Transcribing…", "Pasted"])
        await f.advance(by: OverlayTiming.standard.inserted, until: "the overlay to hide") { f.overlay.current == nil }
        await f.environment.shutdown()
    }

    @Test("a press while a dictation is processed shows the busy notice on the overlay")
    func busyPress() async {
        let f = AppEnvironmentFixture(recognizer: FakeRecognizer(transcript: "uno", gated: true))
        f.environment.start()
        f.hotkeys.send(.down(at: Self.pressTime))
        f.capture.emit(AudioChunk(samples: [0.1]))
        await f.eventually("the recording indicator") { f.overlay.current == "Listening…" }
        f.hotkeys.send(.up(at: Self.pressTime + .milliseconds(1200)))
        await f.eventually("the transcribing indicator") { f.overlay.current == "Transcribing…" }
        f.hotkeys.send(.down(at: Self.pressTime + .milliseconds(1300)))
        await f.eventually("the busy notice") { f.overlay.current == "Still working on the last dictation" }

        f.recognizer.releaseTranscription()
        await f.environment.shutdown()
    }

    @Test("a missing microphone permission shows an error that names the menu")
    func microphoneMissing() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .denied, .accessibility: .granted])
        f.environment.start()
        f.hotkeys.send(.down(at: Self.pressTime))
        await f.eventually("the error") { f.overlay.current?.contains("Microphone access is off") == true }

        #expect(f.overlay.current == "Microphone access is off. Open the Susurro menu to turn it on.")
        #expect(f.capture.startCount == 0)
        await f.environment.shutdown()
    }

    @Test("one clock paces the whole graph: a limit of the coordinator, the poll, and the hold of the overlay")
    func oneClockPacesTheGraph() async {
        let f = AppEnvironmentFixture(capture: FakeAudioCaptureSource(gatesStart: true))
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }
        f.hotkeys.send(.down(at: Self.pressTime))
        await f.eventually("the starting indicator") { f.overlay.current == "Getting ready…" }
        let readsBefore = f.permissions.statusReads

        await f.advance(by: DictationLimits.captureStartTimeout, until: "the capture limit") {
            f.overlay.current != "Getting ready…"
        }
        let error = f.overlay.current
        await f.eventually("a read of the permissions") { f.permissions.statusReads > readsBefore }
        await f.advance(by: OverlayTiming.standard.error, until: "the overlay to hide") { f.overlay.current == nil }

        #expect(error == "The microphone did not stop in time. Hold the key to try again.")
        f.capture.releaseStart()
        await f.environment.shutdown()
    }

    // MARK: Model progress

    @Test("the model's readiness reaches the menu, the overlay after the delay, and the log")
    func modelProgress() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        f.readiness.publish(.loading(progress: 0.4))
        await f.eventually("the menu line") { f.environment.menu.content.modelLine == "Speech model: preparing… 40%" }
        await f.advance(by: ModelLoadWatcher.standardDelay, until: "the overlay progress") {
            f.overlay.current == "Preparing the speech model… 40%"
        }

        f.readiness.publish(.ready)
        await f.eventually("the model to be ready") { f.environment.menu.content.modelLine == "Speech model: ready" }
        await f.eventually("the overlay to hide") { f.overlay.current == nil }
        #expect(f.diagnostics.events.contains(.modelReadiness("loading")))
        #expect(f.diagnostics.events.contains(.modelReadiness("ready")))
        await f.environment.shutdown()
    }

    @Test("a model that fails to load after its progress showed puts a warning on the overlay, and then hides it")
    func modelUnavailable() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        f.readiness.publish(.loading(progress: 0.4))
        await f.advance(by: ModelLoadWatcher.standardDelay, until: "the overlay progress") {
            f.overlay.current == "Preparing the speech model… 40%"
        }

        f.readiness.publish(.unavailable("offline", retryable: true))
        await f.eventually("the warning") {
            f.overlay.current == "Speech model unavailable. Open the Susurro menu for details."
        }
        await f.advance(by: OverlayTiming.standard.error, until: "the overlay to hide") { f.overlay.current == nil }
        await f.environment.shutdown()
    }

    // MARK: Permissions

    @Test(
        "the monitor reads the permissions at launch, and again each second, so a revocation shows while the app idles")
    func monitorPolls() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }
        await f.clock.waitForSleeps(1)
        let granted = f.environment.monitor.missingRequired

        f.permissions.set(.accessibility, to: .denied)
        f.clock.advance(by: .seconds(1))
        await f.eventually("the revocation") { f.environment.monitor.missingRequired == [.accessibility] }

        #expect(granted.isEmpty)
        await f.environment.shutdown()
    }

    @Test("the menu reads the permissions again when the app becomes active")
    func activationRefreshesTheMenu() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .granted, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the first read") { !f.environment.menu.content.microphone.title.contains("not decided") }
        let before = f.environment.menu.content.accessibility.isGranted

        f.permissions.set(.accessibility, to: .granted)
        f.activations.continuation.yield()
        await f.eventually("the grant") { f.environment.menu.content.accessibility.isGranted }

        #expect(!before)
        await f.environment.shutdown()
    }

    @Test("the menu says what a missing required permission costs, and stops when it is granted")
    func menuShowsTheRestriction() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .denied, .accessibility: .granted])
        f.environment.start()
        await f.eventually("the restriction") { f.environment.menu.content.restrictionMessage != nil }
        let message = f.environment.menu.content.restrictionMessage

        f.permissions.set(.microphone, to: .granted)
        f.activations.continuation.yield()
        await f.eventually("the restriction to go") { f.environment.menu.content.restrictionMessage == nil }

        #expect(message == "Dictation is off until Microphone is allowed.")
        await f.environment.shutdown()
    }

    @Test("with Accessibility missing the menu says the text goes to the clipboard, not that dictation is off")
    func menuSaysTheClipboardForAccessibility() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .granted, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the restriction") { f.environment.menu.content.restrictionMessage != nil }

        #expect(
            f.environment.menu.content.restrictionMessage
                == "Dictated text goes to the clipboard until Accessibility is allowed.")
        await f.environment.shutdown()
    }

    @Test("the menu offers to allow a permission nobody has asked for, and the item asks the system")
    func menuAllowAsksTheSystem() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .notDetermined, .accessibility: .granted])
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }
        let item = f.environment.menu.content.microphone.action

        await f.environment.menu.request(.microphone)

        #expect(item?.title == "Allow Microphone…")
        #expect(f.permissions.requested == [.microphone])
        #expect(f.openedSettings.isEmpty)
        await f.environment.shutdown()
    }

    @Test("the onboarding sees what the monitor reads: the rows and what the missing permissions cost")
    func onboardingFollowsTheMonitor() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .granted, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }

        let state = f.environment.onboardingModel.state

        #expect(state.rows.map(\.id) == [.microphone, .accessibility])
        #expect(state.rows.map(\.status) == [.granted, .denied])
        #expect(!state.isDoneEnabled)
        #expect(state.restrictionMessage == "Dictated text goes to the clipboard until Accessibility is allowed.")
        await f.environment.shutdown()
    }

    @Test("the status changes the monitor finds are logged, the first read included")
    func monitorLogsItsReads() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .granted, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }

        #expect(
            f.diagnostics.events.contains(.permissionStatusChanged(permission: .microphone, from: nil, to: .granted)))
        #expect(
            f.diagnostics.events.contains(.permissionStatusChanged(permission: .accessibility, from: nil, to: .denied)))
        await f.environment.shutdown()
    }

    @Test("opening System Settings from the menu opens the pane, and the monitor follows the permission")
    func openSettings() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .granted, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }

        f.environment.menu.openSettings(for: .accessibility)

        #expect(f.openedSettings == [.accessibility])
        #expect(f.environment.monitor.followUps[.accessibility] == .sentToSettings)
        await f.environment.shutdown()
    }

    // MARK: Themes and settings

    @Test("the theme in use is the one the theme store publishes, and a theme file that works changes it")
    func themeFollowsTheStore() async {
        let f = AppEnvironmentFixture(themeFiles: ["ocean.json": #"{"schemaVersion": 1, "name": "Ocean"}"#])
        defer { f.removeThemeFolder() }
        f.environment.start()
        await f.eventually("the bundled theme") { f.environment.themeModel.theme == .default }

        await f.themes.select("ocean")
        await f.eventually("the theme file") { f.environment.themeModel.theme.name == "Ocean" }

        #expect(f.environment.themeModel.errors.isEmpty)
        await f.environment.shutdown()
    }

    @Test("a theme file that cannot be used leaves the bundled theme and its errors")
    func brokenThemeFile() async {
        let f = AppEnvironmentFixture(themeFiles: ["broken.json": #"{"schemaVersion": 1, "colours": {}}"#])
        defer { f.removeThemeFolder() }
        f.environment.start()
        await f.eventually("the bundled theme") { f.environment.themeModel.theme == .default }

        await f.themes.select("broken")
        await f.eventually("the errors") { !f.environment.themeModel.errors.isEmpty }

        #expect(f.environment.themeModel.theme == .default)
        await f.environment.shutdown()
    }

    @Test("the themes folder is read at launch: a theme chosen before then shows once the folder is read")
    func themesAreReadAtLaunch() async {
        let f = AppEnvironmentFixture(themeFiles: ["ocean.json": #"{"schemaVersion": 1, "name": "Ocean"}"#])
        defer { f.removeThemeFolder() }
        await f.themes.select("ocean")
        let beforeLaunch = f.environment.themeModel.theme

        f.environment.start()
        await f.eventually("the theme file") { f.environment.themeModel.theme.name == "Ocean" }

        #expect(beforeLaunch == .default)
        await f.environment.shutdown()
    }

    // MARK: Shutdown

    @Test("shutdown stops the coordinator, drains the inserter, and ignores the hotkey after it")
    func shutdown() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        await f.eventually("the launch") { f.diagnostics.events.contains(.appLaunched) }

        await f.environment.shutdown()
        f.hotkeys.send(.down(at: Self.pressTime))
        for _ in 0..<50 { await Task.yield() }

        #expect(f.inserter.drainCount == 1)
        #expect(f.capture.startCount == 0)
    }

    @Test("shutdown ends the monitor's poll")
    func shutdownStopsThePoll() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }
        await f.clock.waitForSleeps(1)
        await f.eventually("the model to be prepared") { f.recognizer.calls.contains(.prepare) }

        await f.environment.shutdown()
        let reads = f.permissions.statusReads
        f.clock.advance(by: .seconds(5))
        for _ in 0..<50 { await Task.yield() }

        #expect(f.permissions.statusReads == reads)
    }

    @Test("termination is logged, and then puts the clipboard back")
    func termination() {
        let f = AppEnvironmentFixture()

        f.environment.willTerminate()

        #expect(f.diagnostics.events == [.appTerminating])
        #expect(f.clipboardRestores == 1)
    }

    // MARK: Preview

    @Test("the preview environment is ready to dictate: permissions granted and the model ready")
    func preview() async {
        let dependencies = AppEnvironment.Dependencies.preview()

        #expect(await dependencies.permissions.status(.microphone) == .granted)
        #expect(await dependencies.permissions.status(.accessibility) == .granted)
        #expect(await dependencies.recognizer.readiness() == .ready)
        #expect(await dependencies.theming.store.current.theme == .default)
    }
}
