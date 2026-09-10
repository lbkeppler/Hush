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
            MainWindow(controller: controller)
                .frame(minWidth: 900, minHeight: 640)
                .task {
                    await controller.start()
                }
        }
    }
}
