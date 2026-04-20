import AppKit
import Combine

final class StatusMenuController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: AppCoordinator
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        buildMenu()
        bindStatus()
    }

    private func bindStatus() {
        coordinator.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.statusItem.button?.title = "ALVA \(status.rawValue)"
            }
            .store(in: &cancellables)
    }

    private func buildMenu() {
        statusItem.button?.title = "ALVA idle"
        let menu = NSMenu()

        let openSettings = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        openSettings.target = self
        menu.addItem(openSettings)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ALVA-TEXT", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showSettings() {
        coordinator.openSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
