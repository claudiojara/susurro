import CoreTestSupport
import Domain
import Testing

@testable import Presentation

@Suite("Permission prompter", .timeLimit(.minutes(1)))
struct PermissionPrompterTests {
    @Test("a Mac with neither permission is asked for the microphone, then for Accessibility")
    func bothMissing() async {
        let checker = FakePermissionsChecker([.microphone: .notDetermined, .accessibility: .denied])

        await PermissionPrompter(checker: checker).requestMissingPermissions()

        #expect(checker.requested == [.microphone, .accessibility])
    }

    @Test(
        "a permission that is already granted is not asked for again",
        arguments: [
            ([Permission.microphone: PermissionStatus.granted, .accessibility: .denied], [Permission.accessibility]),
            ([.microphone: .denied, .accessibility: .granted], [.microphone]),
            ([.microphone: .granted, .accessibility: .granted], []),
        ]
    )
    func grantedIsNotRequested(statuses: [Permission: PermissionStatus], expected: [Permission]) async {
        let checker = FakePermissionsChecker(statuses)

        await PermissionPrompter(checker: checker).requestMissingPermissions()

        #expect(checker.requested == expected)
    }

    @Test("asking twice at launch asks the system once")
    func askedOnce() async {
        let checker = FakePermissionsChecker([.microphone: .denied, .accessibility: .denied])
        let sut = PermissionPrompter(checker: checker)

        await sut.requestMissingPermissions()
        await sut.requestMissingPermissions()

        #expect(checker.requested == [.microphone, .accessibility])
    }

    @Test("Accessibility is asked for only after the microphone prompt has been answered")
    func oneAtATime() async {
        let checker = FakePermissionsChecker([.microphone: .notDetermined], gatedRequests: true)
        let sut = PermissionPrompter(checker: checker)
        let prompting = Task { await sut.requestMissingPermissions() }
        await checker.requestEntered.wait()
        for _ in 0..<50 { await Task.yield() }
        let whileMicrophonePromptIsUp = checker.requested

        checker.releaseRequest()
        await checker.requestEntered.wait()
        checker.releaseRequest()
        await prompting.value

        #expect(whileMicrophonePromptIsUp == [.microphone])
        #expect(checker.requested == [.microphone, .accessibility])
    }
}
