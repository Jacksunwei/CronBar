import SwiftUI
import AppKit

@main
struct CronBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = LaunchAgentManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(manager)
        } label: {
            Image(nsImage: IconAssets.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keeps the app as a menu-bar-only accessory (no Dock icon).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
