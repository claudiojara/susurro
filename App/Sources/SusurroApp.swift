import SwiftUI

@main
struct SusurroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Susurro", systemImage: "waveform") {
            Text("Susurro")
            Divider()
            Button("Quit Susurro") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
