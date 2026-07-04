import SwiftUI
import AppKit

@main
struct DesktopPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Minimal menu bar icon and settings popover
        MenuBarExtra("Desktop Pet", systemImage: "pawprint.fill") {
            Button("Settings") {
                // Settings action if needed later
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
