import Domain
import Testing

@Suite("Hotkey status")
struct HotkeyStatusTests {
    private static let fn = HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: .function))

    @Test("the default hotkey is a keyed combination that needs no Input Monitoring", arguments: [
        PermissionStatus.granted, .denied, .notDetermined,
    ])
    func defaultNeedsNoPermission(inputMonitoring: PermissionStatus) {
        let status = HotkeyStatus.evaluate(.standard, inputMonitoring: inputMonitoring, secureInputActive: false)

        #expect(HotkeyConfiguration.standard.kind == .keyed)
        #expect(!HotkeyConfiguration.standard.needsInputMonitoring)
        #expect(status.arming == .armed)
    }

    @Test("a modifier-only hotkey is not armed until Input Monitoring is granted", arguments: [
        PermissionStatus.denied, .notDetermined,
    ])
    func modifierOnlyWaitsForTheGrant(missing: PermissionStatus) {
        #expect(HotkeyStatus.evaluate(Self.fn, inputMonitoring: missing, secureInputActive: false).arming == .needsInputMonitoring)
        #expect(HotkeyStatus.evaluate(Self.fn, inputMonitoring: .granted, secureInputActive: false).arming == .armed)
    }

    @Test("Secure Event Input exposes a warning, whatever the hotkey")
    func secureInputWarns() {
        #expect(HotkeyStatus.evaluate(.standard, inputMonitoring: .granted, secureInputActive: true).secureInputWarning)
        #expect(HotkeyStatus.evaluate(Self.fn, inputMonitoring: .granted, secureInputActive: true).secureInputWarning)
        #expect(!HotkeyStatus.evaluate(.standard, inputMonitoring: .granted, secureInputActive: false).secureInputWarning)
    }
}
