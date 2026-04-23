import AppKit
import Combine
import SwiftUI

/// Menu-bar item with an animated template icon.
///
/// States map to the available artwork like this:
///   - idle / pasted / copied  → static `alva-idle`
///   - recording               → 6-frame pulse animation (10 fps)
///   - transcribing / rewriting / translating → 8-frame chase animation (12 fps)
///   - error                   → plain text "⚠ Fehler" (per user preference)
///   - needsAccessibility      → plain text "⚠ Bedienungshilfen fehlen"
@MainActor
final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: AppCoordinator
    private var cancellables = Set<AnyCancellable>()
    private let menu = NSMenu()
    /// Tag marker for the dynamic "language F-key quick-reference" section.
    /// Items carrying this tag get rebuilt every time the menu opens.
    private let languageSectionTag = 0xF00D
    /// Hosting-Controller für den SwiftUI-Header (Avatar + Email + Toggle).
    /// Bleibt für die Lebenszeit des Menus erhalten, damit SwiftUI-State
    /// (z.B. geladenes Gravatar-Bild) nicht bei jedem Menu-Öffnen verloren geht.
    private var headerHostingController: NSHostingController<MenuHeaderView>?
    private var headerMenuItem: NSMenuItem?

    private var animationTimer: Timer?
    private var currentFrame: Int = 0

    private let recordingFrameCount = 6
    private let transcribingFrameCount = 8
    private let recordingFPS: Double = 10.0
    private let transcribingFPS: Double = 12.0
    private let iconSize = NSSize(width: 18, height: 18)

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
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
        // 1) SwiftUI-Header (Avatar / Email / Aktiv-Toggle) als erstes Item.
        installHeaderItem()

        // 2) Separator zwischen Header und Hauptaktionen.
        menu.addItem(.separator())

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

        // The dynamic language-binding quick-reference (Fn+F1 → Englisch, …)
        // is appended every time the menu opens, via NSMenuDelegate.
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Baut den SwiftUI-Header (Avatar + Email + Aktiv-Toggle) als NSMenuItem
    /// mit Custom-View. Der Hosting-Controller bleibt in `headerHostingController`
    /// gehalten, damit SwiftUI-State erhalten bleibt.
    private func installHeaderItem() {
        let view = MenuHeaderView(
            coordinator: coordinator,
            license: LicenseState.shared,
            onActivate: { [weak self] in
                self?.coordinator.openSettings()
            }
        )
        let host = NSHostingController(rootView: view)
        // Pflicht-Size für Menu-Custom-Views: intrinsic ist nicht ausreichend.
        host.view.frame = NSRect(x: 0, y: 0, width: 300, height: 58)
        host.view.autoresizingMask = [.width]

        let item = NSMenuItem()
        item.view = host.view
        menu.addItem(item)

        self.headerHostingController = host
        self.headerMenuItem = item
    }

    /// Removes every menu entry that was tagged as part of the language
    /// quick-reference section (including its leading header + separator).
    private func clearLanguageSection() {
        for item in menu.items where item.tag == languageSectionTag {
            menu.removeItem(item)
        }
    }

    /// Appends the current language-binding quick-reference to the bottom
    /// of the menu. Called on `menuWillOpen` so the list always reflects the
    /// latest user configuration without needing a Combine subscription.
    private func rebuildLanguageSection() {
        clearLanguageSection()

        let bindings = coordinator.languageBindings.sorted { $0.fKey < $1.fKey }
        guard !bindings.isEmpty else { return }

        let separator = NSMenuItem.separator()
        separator.tag = languageSectionTag
        menu.addItem(separator)

        let header = NSMenuItem(title: "Während der Aufnahme", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.tag = languageSectionTag
        header.attributedTitle = NSAttributedString(
            string: "Während der Aufnahme",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(header)

        for binding in bindings {
            let title = "Fn+F\(binding.fKey)  →  \(binding.displayName)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = languageSectionTag
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.systemFontSize(for: .small),
                        weight: .regular
                    ),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            menu.addItem(item)
        }
    }

    @objc private func showSettings() {
        coordinator.openSettings()
    }

    @objc private func showHistory() {
        coordinator.openHistoryWindow()
    }

    @objc private func showOnboarding() {
        print("ALVA: menu -> showOnboarding click received")
        coordinator.showOnboardingWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension StatusMenuController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildLanguageSection()
    }
}
