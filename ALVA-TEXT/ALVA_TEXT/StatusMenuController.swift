import AppKit
import Combine

/// Menu-bar item with an animated template icon.
///
/// States map to the available artwork like this:
///   - idle / pasted / copied  → static `alva-idle`
///   - recording               → 6-frame pulse animation (10 fps)
///   - transcribing / rewriting / translating → 8-frame chase animation (12 fps)
///   - error                   → plain text "⚠ Fehler" (per user preference)
///   - needsAccessibility      → plain text "⚠ Bedienungshilfen fehlen"
@MainActor
final class StatusMenuController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: AppCoordinator
    private var cancellables = Set<AnyCancellable>()

    private var animationTimer: Timer?
    private var currentFrame: Int = 0

    private let recordingFrameCount = 6
    private let transcribingFrameCount = 8
    private let recordingFPS: Double = 10.0
    private let transcribingFPS: Double = 12.0
    private let iconSize = NSSize(width: 18, height: 18)

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        buildMenu()
        applyIdleIcon()
        bindStatus()
    }

    private func bindStatus() {
        coordinator.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.apply(status: status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Status → visual

    private func apply(status: AppStatus) {
        stopAnimation()

        switch status {
        case .idle, .pasted, .copied:
            applyIdleIcon()

        case .recording:
            startAnimation(frameCount: recordingFrameCount,
                           fps: recordingFPS,
                           namePrefix: "alva-recording-frame")

        case .transcribing, .rewriting, .translating:
            startAnimation(frameCount: transcribingFrameCount,
                           fps: transcribingFPS,
                           namePrefix: "alva-transcribing-frame")

        case .error:
            applyText("⚠ Fehler")

        case .needsAccessibility:
            applyText("⚠ Bedienungshilfen fehlen")
        }
    }

    private func applyIdleIcon() {
        guard let button = statusItem.button else { return }
        button.title = ""
        if let image = NSImage(named: "alva-idle") {
            image.isTemplate = true
            image.size = iconSize
            button.image = image
        }
    }

    private func applyText(_ text: String) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = text
    }

    private func startAnimation(frameCount: Int, fps: Double, namePrefix: String) {
        guard let button = statusItem.button else { return }
        button.title = ""
        currentFrame = 0

        // Render the first frame immediately so there's no flicker of the
        // previous static icon while we wait for the first timer tick.
        setFrame(button: button, frameCount: frameCount, namePrefix: namePrefix)

        let timer = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem.button else { return }
                self.currentFrame = (self.currentFrame + 1) % frameCount
                self.setFrame(button: button, frameCount: frameCount, namePrefix: namePrefix)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func setFrame(button: NSStatusBarButton, frameCount: Int, namePrefix: String) {
        let idx = String(format: "%02d", currentFrame)
        let name = "\(namePrefix)-\(idx)"
        if let image = NSImage(named: name) {
            image.isTemplate = true
            image.size = iconSize
            button.image = image
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        currentFrame = 0
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        let openSettings = NSMenuItem(title: "Einstellungen …", action: #selector(showSettings), keyEquivalent: ",")
        openSettings.target = self
        menu.addItem(openSettings)

        let openHistory = NSMenuItem(title: "Verlauf öffnen …", action: #selector(showHistory), keyEquivalent: "h")
        openHistory.target = self
        menu.addItem(openHistory)

        menu.addItem(.separator())

        let runOnboarding = NSMenuItem(title: "Einrichtung erneut starten …", action: #selector(showOnboarding), keyEquivalent: "")
        runOnboarding.target = self
        menu.addItem(runOnboarding)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "ALVA-TEXT beenden", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showSettings() {
        coordinator.openSettings()
    }

    @objc private func showHistory() {
        coordinator.openHistoryWindow()
    }

    @objc private func showOnboarding() {
        coordinator.showOnboardingWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
