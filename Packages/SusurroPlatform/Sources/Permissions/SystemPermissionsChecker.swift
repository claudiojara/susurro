import AVFoundation
import ApplicationServices
import Domain
import Foundation
import IOKit.hid

/// What the checker asks the system. Tests script these; `live` calls the real APIs.
struct PermissionProbes: Sendable {
    var microphoneAuthorization: @Sendable () -> AVAuthorizationStatus
    var isAccessibilityTrusted: @Sendable () -> Bool
    var requestMicrophone: @Sendable () async -> Void
    /// Shows the system's Accessibility prompt, which links to System Settings.
    var requestAccessibility: @Sendable () -> Void
    /// What the system says about listening to keyboard events, without raising a prompt.
    var inputMonitoringAccess: @Sendable () -> IOHIDAccessType
    /// Whether the screen capture preflight lets this process in, without raising a prompt.
    var isScreenRecordingGranted: @Sendable () -> Bool
    /// Asks to listen to keyboard events, which shows the system prompt the first time.
    var requestInputMonitoring: @Sendable () -> Void
    /// Asks to capture the screen, which shows the system prompt the first time.
    var requestScreenRecording: @Sendable () -> Void

    static let live = PermissionProbes(
        microphoneAuthorization: { AVCaptureDevice.authorizationStatus(for: .audio) },
        isAccessibilityTrusted: { AXIsProcessTrusted() },
        requestMicrophone: { _ = await AVCaptureDevice.requestAccess(for: .audio) },
        requestAccessibility: {
            // `kAXTrustedCheckOptionPrompt` is a mutable global, which Swift 6 rejects, so its value is spelled out.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        },
        inputMonitoringAccess: { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) },
        isScreenRecordingGranted: { CGPreflightScreenCaptureAccess() },
        requestInputMonitoring: { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) },
        requestScreenRecording: { _ = CGRequestScreenCaptureAccess() }
    )
}

/// Reads and requests the Microphone, Accessibility, Input Monitoring and Screen Recording permissions from the
/// system. Statuses are read on every call, so a change made in System Settings shows without a relaunch.
public struct SystemPermissionsChecker: PermissionsChecker {
    private let probes: PermissionProbes

    public init() {
        self.init(probes: .live)
    }

    init(probes: PermissionProbes) {
        self.probes = probes
    }

    public func status(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            switch probes.microphoneAuthorization() {
            case .notDetermined: .notDetermined
            case .authorized: .granted
            // A restricted device cannot be granted by the user, so it counts as denied.
            case .denied, .restricted: .denied
            // A status added by a later SDK is not known to be granted, and the user has not been shown to refuse it,
            // so it reads as not determined and asking again is safe.
            @unknown default: .notDetermined
            }
        // Accessibility reports only trusted or not, so an untrusted process cannot be told from one that was
        // never asked, and both are denied.
        case .accessibility: probes.isAccessibilityTrusted() ? .granted : .denied
        case .inputMonitoring:
            switch probes.inputMonitoringAccess() {
            case kIOHIDAccessTypeGranted: .granted
            case kIOHIDAccessTypeDenied: .denied
            // Unknown means the user has not been asked. Any other value is not known to be granted, and asking again
            // is safe.
            default: .notDetermined
            }
        // The preflight, like Accessibility, answers only yes or no, so a process that was never asked is denied too.
        case .screenRecording: probes.isScreenRecordingGranted() ? .granted : .denied
        }
    }

    public func request(_ permission: Permission) async {
        switch permission {
        case .microphone: await probes.requestMicrophone()
        case .accessibility: probes.requestAccessibility()
        case .inputMonitoring: probes.requestInputMonitoring()
        case .screenRecording: probes.requestScreenRecording()
        }
    }

    /// The System Settings pane where the user changes the permission, as an `x-apple.systempreferences:` URL that
    /// opens the Privacy & Security pane at the permission's anchor. It belongs to this concrete checker and not to the
    /// `PermissionsChecker` port, so only code that holds the live checker can ask for it.
    public func settingsURL(for permission: Permission) -> URL {
        let pane =
            switch permission {
            case .microphone: "Privacy_Microphone"
            case .accessibility: "Privacy_Accessibility"
            case .inputMonitoring: "Privacy_ListenEvent"
            case .screenRecording: "Privacy_ScreenCapture"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}
