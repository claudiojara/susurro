import AppKit
import Carbon.HIToolbox
import Domain
import KeyboardShortcuts

extension KeyboardShortcuts.Shortcut {
    /// The shortcut of a keyed hotkey, or nil when the combo has no key. The fn key has no Carbon modifier, so a keyed
    /// combo does not carry it.
    init?(_ combo: HotkeyCombo) {
        guard let keyCode = combo.keyCode else { return nil }
        var carbonModifiers = 0
        if combo.modifiers.contains(.control) { carbonModifiers |= controlKey }
        if combo.modifiers.contains(.option) { carbonModifiers |= optionKey }
        if combo.modifiers.contains(.shift) { carbonModifiers |= shiftKey }
        if combo.modifiers.contains(.command) { carbonModifiers |= cmdKey }
        self.init(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
    }
}

extension HotkeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: HotkeyModifiers = []
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.function) { modifiers.insert(.function) }
        self = modifiers
    }
}

/// The live transition source. A keyed hotkey goes through KeyboardShortcuts (Carbon), which needs no permission. A
/// modifier-only one listens to the modifier flags of every app, which needs Input Monitoring: the service only asks for
/// it once that is granted.
struct KeyboardShortcutsTransitionSource: KeyTransitionSource {
    func transitions(for configuration: HotkeyConfiguration) -> AsyncStream<KeyTransition> {
        switch configuration.kind {
        case .keyed: keyed(configuration.combo)
        case .modifierOnly: modifierFlags()
        }
    }

    private func keyed(_ combo: HotkeyCombo) -> AsyncStream<KeyTransition> {
        let (transitions, continuation) = AsyncStream.makeStream(of: KeyTransition.self)
        guard let shortcut = KeyboardShortcuts.Shortcut(combo) else { return transitions }  // nothing to listen to
        // KeyboardShortcuts is main-actor isolated, so the registration is made there.
        let listening = Task { @MainActor in
            for await event in KeyboardShortcuts.events(for: shortcut) {
                continuation.yield(event == .keyDown ? .down : .up)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in listening.cancel() }
        return transitions
    }

    private func modifierFlags() -> AsyncStream<KeyTransition> {
        let (transitions, continuation) = AsyncStream.makeStream(of: KeyTransition.self)
        let listening = Task { @MainActor in
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                continuation.yield(.flags(HotkeyModifiers(event.modifierFlags)))
            }
            defer { monitor.map(NSEvent.removeMonitor) }
            // The monitor lives until the stream is no longer read, which cancels this task.
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
        }
        continuation.onTermination = { _ in listening.cancel() }
        return transitions
    }
}
