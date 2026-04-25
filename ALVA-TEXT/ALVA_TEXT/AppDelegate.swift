import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOlderInstances()

        // Clean up obsolete UserDefaults keys from when the reverse-
        // translate hotkey was user-configurable. Now fixed to ⌃⌥⌘L.
        AppCoordinator.migrateReverseTranslateDefaults()

        NSApp.setActivationPolicy(.accessory)
        coordinator.requestPermissions()

        menuController = StatusMenuController(coordinator: coordinator)
        coordinator.start()

        // License-Status hydratieren + täglichen Check starten. Blockiert
        // den Launch nicht — Ergebnis landet via LicenseState in der UI.
        LicenseState.shared.start()

        // First-run onboarding: a guided setup for API key, Accessibility
        // and Input-Monitoring. Skipped if the user has seen it before.
        // Can be re-launched from the status menu.
        if coordinator.shouldShowOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.coordinator.showOnboardingWindow()
            }
        } else if !LicenseClient.isActivated {
            // Kein Onboarding mehr noetig, aber noch nicht aktiviert: direkt
            // in die Settings und den Account-Tab aufrufen, damit der User
            // nicht erst das Menu-Bar-Icon finden muss.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.coordinator.openSettings(initialTab: "account")
            }
        }
    }

    /// On dev builds (running ⌘R in Xcode) the previous instance is sometimes
    /// not torn down. We'd end up with two ALVA icons in the menu bar and
    /// both firing on every keystroke. This kills any older instances so the
    /// newest run wins.
    private func terminateOlderInstances() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBundleID = Bundle.main.bundleIdentifier
        guard let myBundleID else { return }
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == myBundleID && $0.processIdentifier != myPID
        }
        for app in others {
            print("ALVA: terminating stale instance pid=\(app.processIdentifier)")
            app.terminate()
        }
    }
}
