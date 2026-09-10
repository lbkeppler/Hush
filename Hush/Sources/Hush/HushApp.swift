import SwiftUI

/// Runs `NSApp` as a menu-bar-only (accessory) app and connects the shared `BoseController`
/// exactly once at launch — independent of whether/when any SwiftUI window is opened. This is
/// the single trigger for `BoseController.start()`; scenes below must never call it themselves,
/// or a second `discover()` would compete with this connection for the device's one SPP channel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            await BoseController.shared.start()
        }
    }
}

@main
struct HushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = BoseController.shared

    var body: some Scene {
        MenuBarExtra("Hush", systemImage: "headphones") {
            MenuBarView(controller: controller)
        }
        .menuBarExtraStyle(.window)

        // Opened on demand via "Open Hush" (openWindow(id: "main")); never triggers a
        // connection itself — the shared controller was already started at launch.
        WindowGroup("Hush", id: "main") {
            MainWindow(controller: controller)
                .frame(minWidth: 900, minHeight: 640)
        }
    }
}
