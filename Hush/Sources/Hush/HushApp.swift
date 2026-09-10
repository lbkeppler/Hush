import SwiftUI

@main
struct HushApp: App {
    @State private var controller = BoseController.live()

    var body: some Scene {
        MenuBarExtra("Hush", systemImage: "headphones") {
            MenuBarView(controller: controller)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Hush", id: "main") {
            Text("Hush")
                .frame(width: 480, height: 320)
                .task {
                    await controller.start()
                }
        }
    }
}
