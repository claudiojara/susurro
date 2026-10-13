import AVFoundation
import Domain
import Synchronization
import Testing

@testable import Permissions

@Suite("System permissions checker", .timeLimit(.minutes(1)))
struct SystemPermissionsCheckerTests {
    enum Call: Sendable, Equatable {
        case requestMicrophone
        case requestAccessibility
    }

    /// Scripted system answers. Every request the checker makes is logged, in order.
    private final class Probes: Sendable {
        private let microphone: Mutex<AVAuthorizationStatus>
        private let trusted: Mutex<Bool>
        private let log = Mutex<[Call]>([])

        init(microphone: AVAuthorizationStatus = .notDetermined, accessibilityTrusted: Bool = false) {
            self.microphone = Mutex(microphone)
            trusted = Mutex(accessibilityTrusted)
        }

        var calls: [Call] { log.withLock { $0 } }

        func setMicrophone(_ status: AVAuthorizationStatus) { microphone.withLock { $0 = status } }
        func setAccessibilityTrusted(_ value: Bool) { trusted.withLock { $0 = value } }

        var probes: PermissionProbes {
            PermissionProbes(
                microphoneAuthorization: { self.microphone.withLock { $0 } },
                isAccessibilityTrusted: { self.trusted.withLock { $0 } },
                requestMicrophone: { self.log.withLock { $0.append(.requestMicrophone) } },
                requestAccessibility: { self.log.withLock { $0.append(.requestAccessibility) } }
            )
        }
    }

    @Test(
        "the microphone authorization maps to a permission status",
        arguments: [
            (AVAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
            (.authorized, .granted),
            (.denied, .denied),
            (.restricted, .denied),
        ]
    )
    func microphoneStatus(authorization: AVAuthorizationStatus, expected: PermissionStatus) async {
        let sut = SystemPermissionsChecker(probes: Probes(microphone: authorization).probes)

        #expect(await sut.status(.microphone) == expected)
    }

    @Test(
        "a trusted process has Accessibility and an untrusted one does not",
        arguments: [(true, PermissionStatus.granted), (false, .denied)]
    )
    func accessibilityStatus(trusted: Bool, expected: PermissionStatus) async {
        let sut = SystemPermissionsChecker(probes: Probes(accessibilityTrusted: trusted).probes)

        #expect(await sut.status(.accessibility) == expected)
    }

    @Test("each permission reads its own probe")
    func permissionsAreIndependent() async {
        let sut = SystemPermissionsChecker(
            probes: Probes(microphone: .authorized, accessibilityTrusted: false).probes
        )

        #expect(await sut.status(.microphone) == .granted)
        #expect(await sut.status(.accessibility) == .denied)
    }

    @Test("a change in System Settings shows on the next read, without a relaunch")
    func statusIsReadEveryTime() async {
        let scripted = Probes(microphone: .denied, accessibilityTrusted: false)
        let sut = SystemPermissionsChecker(probes: scripted.probes)
        #expect(await sut.status(.microphone) == .denied)
        #expect(await sut.status(.accessibility) == .denied)

        scripted.setMicrophone(.authorized)
        scripted.setAccessibilityTrusted(true)

        #expect(await sut.status(.microphone) == .granted)
        #expect(await sut.status(.accessibility) == .granted)
    }

    @Test(
        "a request goes to that permission's requester only",
        arguments: [
            (Permission.microphone, Call.requestMicrophone),
            (.accessibility, .requestAccessibility),
        ]
    )
    func requestCallsTheMatchingRequester(permission: Permission, expected: Call) async {
        let scripted = Probes()
        let sut = SystemPermissionsChecker(probes: scripted.probes)

        await sut.request(permission)

        #expect(scripted.calls == [expected])
    }

    @Test("a status read never raises a system prompt")
    func statusDoesNotRequest() async {
        let scripted = Probes()
        let sut = SystemPermissionsChecker(probes: scripted.probes)

        _ = await sut.status(.microphone)
        _ = await sut.status(.accessibility)

        #expect(scripted.calls.isEmpty)
    }

    @Test(
        "each permission has its own System Settings pane",
        arguments: [
            (Permission.microphone, "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"),
            (.accessibility, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
        ]
    )
    func settingsPane(permission: Permission, expected: String) {
        let sut = SystemPermissionsChecker(probes: Probes().probes)

        #expect(sut.settingsURL(for: permission).absoluteString == expected)
    }
}
