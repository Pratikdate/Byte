import SwiftUI
import AppKit

@main
struct DesktopPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use AppDelegate to create the UI (NSWindow and NSStatusItem).
        // This Settings scene is just a dummy to satisfy SwiftUI App requirements without creating a second menu bar icon.
        Settings {
            EmptyView()
        }
    }
}
