import AVFoundation
import Domain
import IOKit.hid
import Synchronization
import Testing

@testable import Permissions

@Suite("System permissions checker", .timeLimit(.minutes(1)))
struct SystemPermissionsCheckerTests {
    enum Call: Sendable, Equatable {
        case requestMicrophone
        case requestAccessibility
        case requestInputMonitoring
        case requestScreenRecording
    }

    /// Scripted system answers. Every request the checker makes is logged, in order.
    private final class Probes: Sendable {
        private let microphone: Mutex<AVAuthorizationStatus>
        private let trusted: Mutex<Bool>
        private let inputMonitoring: Mutex<IOHIDAccessType>
        private let screenRecording: Mutex<Bool>
        private let log = Mutex<[Call]>([])

        init(
            microphone: AVAuthorizationStatus = .notDetermined,
            accessibilityTrusted: Bool = false,
            inputMonitoring: IOHIDAccessType = kIOHIDAccessTypeUnknown,
            screenRecordingGranted: Bool = false
        ) {
            self.microphone = Mutex(microphone)
            trusted = Mutex(accessibilityTrusted)
            self.inputMonitoring = Mutex(inputMonitoring)
            screenRecording = Mutex(screenRecordingGranted)
        }

        var calls: [Call] { log.withLock { $0 } }

        func setMicrophone(_ status: AVAuthorizationStatus) { microphone.withLock { $0 = status } }
        func setAccessibilityTrusted(_ value: Bool) { trusted.withLock { $0 = value } }
        func setInputMonitoring(_ access: IOHIDAccessType) { inputMonitoring.withLock { $0 = access } }
        func setScreenRecordingGranted(_ value: Bool) { screenRecording.withLock { $0 = value } }

        var probes: PermissionProbes {
            PermissionProbes(
                microphoneAuthorization: { self.microphone.withLock { $0 } },
                isAccessibilityTrusted: { self.trusted.withLock { $0 } },
                requestMicrophone: { self.log.withLock { $0.append(.requestMicrophone) } },
                requestAccessibility: { self.log.withLock { $0.append(.requestAccessibility) } },
                inputMonitoringAccess: { self.inputMonitoring.withLock { $0 } },
                isScreenRecordingGranted: { self.screenRecording.withLock { $0 } },
                requestInputMonitoring: { self.log.withLock { $0.append(.requestInputMonitoring) } },
                requestScreenRecording: { self.log.withLock { $0.append(.requestScreenRecording) } }
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

    @Test(
        "the Input Monitoring access maps to a permission status, and an access the system does not know is not determined",
        arguments: [
            (kIOHIDAccessTypeGranted, PermissionStatus.granted),
            (kIOHIDAccessTypeDenied, .denied),
            (kIOHIDAccessTypeUnknown, .notDetermined),
            (IOHIDAccessType(rawValue: 99), .notDetermined),
        ]
    )
    func inputMonitoringStatus(access: IOHIDAccessType, expected: PermissionStatus) async {
        let sut = SystemPermissionsChecker(probes: Probes(inputMonitoring: access).probes)

        #expect(await sut.status(.inputMonitoring) == expected)
    }

    @Test(
        "a process the screen capture preflight lets in has Screen Recording and one it does not has not",
        arguments: [(true, PermissionStatus.granted), (false, .denied)]
    )
    func screenRecordingStatus(granted: Bool, expected: PermissionStatus) async {
        let sut = SystemPermissionsChecker(probes: Probes(screenRecordingGranted: granted).probes)

        #expect(await sut.status(.screenRecording) == expected)
    }

    @Test("each permission reads its own probe")
    func permissionsAreIndependent() async {
        let sut = SystemPermissionsChecker(
            probes: Probes(
                microphone: .authorized,
                accessibilityTrusted: false,
                inputMonitoring: kIOHIDAccessTypeGranted,
                screenRecordingGranted: false
            ).probes
        )

        #expect(await sut.status(.microphone) == .granted)
        #expect(await sut.status(.accessibility) == .denied)
        #expect(await sut.status(.inputMonitoring) == .granted)
        #expect(await sut.status(.screenRecording) == .denied)
    }

    @Test("a change in System Settings shows on the next read, without a relaunch")
    func statusIsReadEveryTime() async {
        let scripted = Probes(microphone: .denied, accessibilityTrusted: false)
        let sut = SystemPermissionsChecker(probes: scripted.probes)
        #expect(await sut.status(.microphone) == .denied)
        #expect(await sut.status(.accessibility) == .denied)

        #expect(await sut.status(.inputMonitoring) == .notDetermined)
        #expect(await sut.status(.screenRecording) == .denied)

        scripted.setMicrophone(.authorized)
        scripted.setAccessibilityTrusted(true)
        scripted.setInputMonitoring(kIOHIDAccessTypeGranted)
        scripted.setScreenRecordingGranted(true)

        #expect(await sut.status(.microphone) == .granted)
        #expect(await sut.status(.accessibility) == .granted)
        #expect(await sut.status(.inputMonitoring) == .granted)
        #expect(await sut.status(.screenRecording) == .granted)
    }

    @Test(
        "a request goes to that permission's requester only",
        arguments: [
            (Permission.microphone, Call.requestMicrophone),
            (.accessibility, .requestAccessibility),
            (.inputMonitoring, .requestInputMonitoring),
            (.screenRecording, .requestScreenRecording),
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

        for permission in Permission.allCases { _ = await sut.status(permission) }

        #expect(scripted.calls.isEmpty)
    }

    @Test(
        "each permission has its own System Settings pane",
        arguments: [
            (Permission.microphone, "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"),
            (.accessibility, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            (.inputMonitoring, "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"),
            (.screenRecording, "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
        ]
    )
    func settingsPane(permission: Permission, expected: String) {
        let sut = SystemPermissionsChecker(probes: Probes().probes)

        #expect(sut.settingsURL(for: permission).absoluteString == expected)
    }
}
