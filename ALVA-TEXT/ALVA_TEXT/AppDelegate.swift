import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator.requestPermissions()

        menuController = StatusMenuController(coordinator: coordinator)
        coordinator.start()

        // First-run onboarding: a guided 4-step setup that asks for API key,
        // Accessibility and Input-Monitoring. Skipped if the user has seen
        // it before. Can be re-launched from the status menu.
        if coordinator.shouldShowOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.coordinator.showOnboardingWindow()
            }
        }
    }
}
