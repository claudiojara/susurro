import CoreTestSupport
import DesignSystem
import Domain
import Testing

@testable import Composition
@testable import Presentation

@MainActor
@Suite("App environment", .timeLimit(.minutes(1)))
struct AppEnvironmentTests {
    private static let pressTime = Duration.seconds(10)

    // MARK: Launch

    @Test("launch loads the model and asks for the permissions that are missing, one after the other")
    func launch() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .notDetermined, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the launch permissions") {
            f.diagnostics.events.contains(.launchPermissions(microphone: "notDetermined", accessibility: "denied"))
        }

        #expect(f.recognizer.calls.contains(.prepare))
        #expect(f.permissions.requested == [.microphone, .accessibility])
        #expect(f.diagnostics.events.first == .appLaunched)
        #expect(f.diagnostics.events.contains(.modelPrepareRequested))
        await f.environment.shutdown()
    }

    @Test("launch asks for nothing that is granted already")
    func launchWithPermissionsGranted() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        await f.eventually("the launch permissions") {
            f.diagnostics.events.contains(.launchPermissions(microphone: "granted", accessibility: "granted"))
        }

        #expect(f.permissions.requested.isEmpty)
        await f.environment.shutdown()
    }

    @Test("starting twice starts everything once")
    func startIsIdempotent() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        f.environment.start()
        await f.eventually("the launch permissions") {
            f.diagnostics.events.contains(.launchPermissions(microphone: "granted", accessibility: "granted"))
        }

        await f.clock.waitForSleeps(1)

        let launches = f.diagnostics.events.filter { $0 == .appLaunched }.count
        let prepares = f.recognizer.calls.filter { $0 == .prepare }.count
        #expect(launches == 1)
        #expect(prepares == 1)
        #expect(f.clock.pendingSleeps == 1)  // one permission poll
        #expect(f.themeWatches.value == 1)
        await f.environment.shutdown()
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
        f.sleeper.fire(OverlayTiming.standard.inserted)
        await f.eventually("the overlay to hide") { f.overlay.current == nil }
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

    // MARK: Model progress

    @Test("the model's readiness reaches the menu, the overlay after the delay, and the log")
    func modelProgress() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        f.readiness.publish(.loading(progress: 0.4))
        await f.eventually("the menu line") { f.environment.menu.content.modelLine == "Speech model: preparing… 40%" }
        f.sleeper.fire(ModelLoadWatcher.standardDelay)
        await f.eventually("the overlay progress") { f.overlay.current == "Preparing the speech model… 40%" }

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
        f.sleeper.fire(ModelLoadWatcher.standardDelay)
        await f.eventually("the overlay progress") { f.overlay.current == "Preparing the speech model… 40%" }

        f.readiness.publish(.unavailable("offline", retryable: true))
        await f.eventually("the warning") {
            f.overlay.current == "Speech model unavailable. Open the Susurro menu for details."
        }
        f.sleeper.fire(OverlayTiming.standard.error)
        await f.eventually("the overlay to hide") { f.overlay.current == nil }
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
        let granted = f.environment.monitor.blocking

        f.permissions.set(.accessibility, to: .denied)
        f.clock.advance(by: .seconds(1))
        await f.eventually("the revocation") { f.environment.monitor.blocking == [.accessibility] }

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

    @Test("the menu says why dictation is off while a required permission is missing, and stops when it is granted")
    func menuShowsTheDisabledReason() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .denied, .accessibility: .granted])
        f.environment.start()
        await f.eventually("the reason") { f.environment.menu.content.disabledMessage != nil }
        let message = f.environment.menu.content.disabledMessage

        f.permissions.set(.microphone, to: .granted)
        f.activations.continuation.yield()
        await f.eventually("the reason to go") { f.environment.menu.content.disabledMessage == nil }

        #expect(message == "Dictation is off until Microphone is allowed.")
        await f.environment.shutdown()
    }

    @Test("the onboarding sees what the monitor reads: the rows and the permissions that block dictation")
    func onboardingFollowsTheMonitor() async {
        let f = AppEnvironmentFixture(permissions: [.microphone: .granted, .accessibility: .denied])
        f.environment.start()
        await f.eventually("the first read") { f.environment.monitor.hasReadStatuses }

        let state = f.environment.onboarding.state

        #expect(state.rows.map(\.id) == [.microphone, .accessibility])
        #expect(state.rows.map(\.status) == [.granted, .denied])
        #expect(!state.isDoneEnabled)
        #expect(state.dictationDisabledMessage == "Dictation is off until Accessibility is allowed.")
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
        await f.eventually("the bundled theme") { f.environment.themes.theme == .default }

        await f.themes.select("ocean")
        await f.eventually("the theme file") { f.environment.themes.theme.name == "Ocean" }

        #expect(f.environment.themes.errors.isEmpty)
        await f.environment.shutdown()
    }

    @Test("a theme file that cannot be used leaves the bundled theme and its errors")
    func brokenThemeFile() async {
        let f = AppEnvironmentFixture(themeFiles: ["broken.json": #"{"schemaVersion": 1, "colours": {}}"#])
        defer { f.removeThemeFolder() }
        f.environment.start()
        await f.eventually("the bundled theme") { f.environment.themes.theme == .default }

        await f.themes.select("broken")
        await f.eventually("the errors") { !f.environment.themes.errors.isEmpty }

        #expect(f.environment.themes.theme == .default)
        await f.environment.shutdown()
    }

    @Test("the environment holds the settings store it was given")
    func settingsStore() {
        let f = AppEnvironmentFixture()
        let key = SettingKey(area: "test", name: "flag", default: false)

        f.environment.settings.set(true, for: key)

        #expect(f.settings.value(for: key))
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
        await f.eventually("the launch") {
            f.diagnostics.events.contains(.launchPermissions(microphone: "granted", accessibility: "granted"))
        }

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
        #expect(await dependencies.themes.current.theme == .default)
    }
}
