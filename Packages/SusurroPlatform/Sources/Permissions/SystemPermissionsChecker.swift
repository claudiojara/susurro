import AVFoundation
import ApplicationServices
import Domain
import Foundation

/// What the checker asks the system. Tests script these; `live` calls the real APIs.
struct PermissionProbes: Sendable {
    var microphoneAuthorization: @Sendable () -> AVAuthorizationStatus
    var isAccessibilityTrusted: @Sendable () -> Bool
    var requestMicrophone: @Sendable () async -> Void
    /// Shows the system's Accessibility prompt, which links to System Settings.
    var requestAccessibility: @Sendable () -> Void

    static let live = PermissionProbes(
        microphoneAuthorization: { AVCaptureDevice.authorizationStatus(for: .audio) },
        isAccessibilityTrusted: { AXIsProcessTrusted() },
        requestMicrophone: { _ = await AVCaptureDevice.requestAccess(for: .audio) },
        requestAccessibility: {
            // `kAXTrustedCheckOptionPrompt` is a mutable global, which Swift 6 rejects, so its value is spelled out.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    )
}

/// Reads and requests the Microphone and Accessibility permissions from the system. Statuses are read on every call,
/// so a change made in System Settings shows without a relaunch.
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
            @unknown default: .notDetermined
            }
        // Accessibility reports only trusted or not, so an untrusted process cannot be told from one that was
        // never asked, and both are denied.
        case .accessibility: probes.isAccessibilityTrusted() ? .granted : .denied
        }
    }

    public func request(_ permission: Permission) async {
        switch permission {
        case .microphone: await probes.requestMicrophone()
        case .accessibility: probes.requestAccessibility()
        }
    }

    /// The System Settings pane where the user changes the permission.
    public func settingsURL(for permission: Permission) -> URL {
        let pane =
            switch permission {
            case .microphone: "Privacy_Microphone"
            case .accessibility: "Privacy_Accessibility"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}
