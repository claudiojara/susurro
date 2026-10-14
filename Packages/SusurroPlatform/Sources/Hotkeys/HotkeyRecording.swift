import AppKit
import Domain
import KeyboardShortcuts

extension HotkeyCaptureInput {
    /// The input an event of the keyboard gives, or nil for one a recording does not look at: a key going up, or a key
    /// that repeats while it is held.
    init?(_ event: NSEvent) {
        switch event.type {
        case .keyDown where !event.isARepeat:
            self = .key(code: Int(event.keyCode), modifiers: HotkeyModifiers(event.modifierFlags))
        case .flagsChanged:
            self = .modifiers(HotkeyModifiers(event.modifierFlags))
        default:
            return nil
        }
    }
}

/// The live source of a recording: the keys that go to the app while the settings window is the one in front.
///
/// Keys are heard by a monitor of the app's own events, so the recording needs no permission and hears nothing from other
/// apps. A key goes to the recording and to nothing else, so ⌘Q does not quit and a letter does not type while the user
/// is pressing their shortcut. The hotkeys of the app are switched off meanwhile, since the system hands a registered
/// shortcut to its hotkey and the recording would never hear the user press the one they have now. The stream ends by
/// itself when a window of the app stops being the key one or the app stops being the one in front, so a recording the
/// user walked away from is not left deaf to the hotkey.
public final class NSEventHotkeyCaptureSource: HotkeyCaptureSource {
    public init() {}

    public func inputs() -> AsyncStream<HotkeyCaptureInput> {
        let (inputs, continuation) = AsyncStream.makeStream(of: HotkeyCaptureInput.self)
        let listening = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let listener = KeyListener(continuation)
            defer { listener.stop() }
            // The listener lives until the stream is no longer read, which cancels this task.
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
        }
        continuation.onTermination = { _ in listening.cancel() }
        return inputs
    }
}

/// One listening: the monitor, the hotkeys switched off, and what ends it.
@MainActor
private final class KeyListener {
    private var monitor: Any?
    private var observers: [any NSObjectProtocol] = []

    init(_ continuation: AsyncStream<HotkeyCaptureInput>.Continuation) {
        KeyboardShortcuts.isEnabled = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if let input = HotkeyCaptureInput(event) { continuation.yield(input) }
            // A key is kept from the rest of the app. A change of modifiers is not a key and goes on.
            return event.type == .keyDown ? nil : event
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in continuation.finish() })
        }
    }

    func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        KeyboardShortcuts.isEnabled = true
    }
}
