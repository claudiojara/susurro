import Presentation
import SwiftUI

@main
struct SusurroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Susurro", systemImage: "waveform") {
            SkeletonMenuView(model: appDelegate.environment.menu)
        }
    }
}
