import AppKit
import Composition

/// Starts the app's work when it launches and winds it down when it quits. What it does is in `AppEnvironment`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment.live

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.start()
    }

    /// Opening the app again while it runs opens its window, since the menu bar icon can be hidden behind the notch. No
    /// other reopen handling is wanted: the app has no document window to bring back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.handleReopen()
        return false
    }

    /// Quitting waits for the dictation to wind down: the capture stops and a paste has a moment to put the clipboard
    /// back. Every wait in the shutdown is bounded.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await environment.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Whatever the shutdown could not finish: a paste that is still under way gets the user's clipboard back now.
    func applicationWillTerminate(_ notification: Notification) {
        environment.willTerminate()
    }
}
