import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator.requestPermissions()

        menuController = StatusMenuController(coordinator: coordinator)
        coordinator.start()
    }
}
