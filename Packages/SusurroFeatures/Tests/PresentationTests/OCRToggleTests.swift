import CoreTestSupport
import Domain
import Testing

@testable import Presentation

@MainActor
@Suite("OCR toggle", .timeLimit(.minutes(1)))
struct OCRToggleTests {
    private let granted: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]

    private func controller(
        _ rig: Rig, settings: InMemorySettingsStore = InMemorySettingsStore()
    ) -> OCRPreferenceController {
        OCRPreferenceController(settings: settings, monitor: rig.monitor)
    }

    @Test("OCR is off by default and asks for nothing")
    func offByDefault() async {
        let rig = Rig(granted)
        let sut = controller(rig)
        await sut.start()
        #expect(!sut.isEnabled)
        #expect(!sut.isActive)
        #expect(sut.explanation == nil)
        #expect(rig.board.requested.isEmpty)
        #expect(!rig.monitor.requested.contains(.screenRecording))
    }

    @Test("turning OCR on without Screen Recording requests it, and a refusal leaves OCR inactive with a reason")
    func onWithoutPermission() async {
        let rig = Rig(granted.merging([.screenRecording: .denied]) { $1 })
        let settings = InMemorySettingsStore()
        let sut = controller(rig, settings: settings)
        await sut.setEnabled(true)

        #expect(rig.board.requested == [.screenRecording])
        #expect(sut.isEnabled)
        #expect(!sut.isActive)
        #expect(sut.explanation == "Screen text is off until Screen Recording is allowed for Susurro.")
        #expect(settings.value(for: ContextSettings.ocrEnabled))
    }

    @Test("allowing the permission activates OCR with no second step")
    func grantActivates() async {
        let rig = Rig(granted.merging([.screenRecording: .denied]) { $1 })
        let sut = controller(rig)
        await sut.setEnabled(true)
        #expect(!sut.isActive)

        rig.board.set(.screenRecording, to: .granted)
        await rig.monitor.refresh()
        #expect(sut.isActive)
        #expect(sut.explanation == nil)
    }

    @Test("turning OCR on with Screen Recording already allowed requests nothing")
    func onWithPermission() async {
        let rig = Rig(granted.merging([.screenRecording: .granted]) { $1 })
        let sut = controller(rig)
        await sut.setEnabled(true)
        #expect(rig.board.requested.isEmpty)
        #expect(sut.isActive)
    }

    @Test("turning OCR off requests nothing and stops asking for Screen Recording")
    func turningOff() async {
        let rig = Rig(granted.merging([.screenRecording: .denied]) { $1 })
        let settings = InMemorySettingsStore()
        let sut = controller(rig, settings: settings)
        await sut.setEnabled(true)
        let requestsBefore = rig.board.requested.count
        await sut.setEnabled(false)

        #expect(rig.board.requested.count == requestsBefore)
        #expect(!sut.isEnabled)
        #expect(sut.explanation == nil)
        #expect(!rig.monitor.requested.contains(.screenRecording))
        #expect(!settings.value(for: ContextSettings.ocrEnabled))
    }

    @Test(
        "OCR on and Screen Recording denied at launch reports inactive while dictation and the onboarding are unaffected"
    )
    func deniedAtLaunch() async {
        let rig = Rig(granted.merging([.screenRecording: .denied]) { $1 })
        let settings = InMemorySettingsStore()
        settings.set(true, for: ContextSettings.ocrEnabled)
        let sut = controller(rig, settings: settings)
        await sut.start()

        #expect(sut.isEnabled)
        #expect(!sut.isActive)
        #expect(sut.explanation != nil)
        #expect(rig.monitor.blocking.isEmpty)
        #expect(rig.monitor.restriction == nil)
        #expect(!rig.monitor.needsOnboarding)
    }
}
