import SwiftUI

@main
struct HushApp: App {
    var body: some Scene {
        MenuBarExtra("Hush", systemImage: "headphones") {
            Text("Hush")
                .padding()
        }
        .menuBarExtraStyle(.window)

        WindowGroup {
            Text("Hush")
                .frame(width: 480, height: 320)
        }
    }
}
