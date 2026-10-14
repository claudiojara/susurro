import Domain
import SusurroUI

extension SettingsViewModel {
    var hotkeyState: HotkeySettingsState {
        let hotkey = dependencies.hotkey()
        // A hotkey of modifier keys only stays unarmed until Input Monitoring is granted, and the settings say so.
        let permissionWarning: HotkeyWarning? =
            hotkey.isModifierOnly && inputMonitoring != .granted
            ? HotkeyWarning(
                message: SettingsCopy.inputMonitoringWarning, actionTitle: SettingsCopy.allowInputMonitoring)
            : nil
        return HotkeySettingsState(
            shortcut: hotkey.keys,
            isModifierOnly: hotkey.isModifierOnly,
            permissionWarning: permissionWarning,
            secureInputWarning: secureInputActive ? SettingsCopy.secureInputWarning : nil
        )
    }

    public func requestInputMonitoring() async {
        await dependencies.permissions.request(.inputMonitoring)
        inputMonitoring = await dependencies.permissions.status(.inputMonitoring)
        changed()
    }
}
