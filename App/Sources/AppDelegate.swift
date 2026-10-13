import AppKit
import OSLog
import Presentation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dev.claudiojara.susurro", category: "app")

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("launched; features module: \(SusurroFeaturesModule.name, privacy: .public)")
    }
}
