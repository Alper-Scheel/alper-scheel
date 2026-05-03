import AppKit
import ApplicationServices
import CoreGraphics

/// Callback für den Warm-Up-CGEventTap. Bewusst auf File-Ebene (nicht
/// als Inline-Closure innerhalb der `@MainActor`-Klasse), damit Swift
/// keinen Actor-Kontext mit der C-Convention-Signatur in Konflikt
/// bringt. Tap ist `.listenOnly` — wir leiten den Event unverändert
/// weiter, der einzige Zweck ist die TCC-Registrierung.
private func alvaWarmUpTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    return Unmanaged.passUnretained(event)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private var menuController: StatusMenuController?

    /// UserDefaults-Key. Wird vom InputMonitoringCard / PermissionCard
    /// gesetzt, sobald der User „Jetzt freigeben" geklickt hat — und beim
    /// nächsten App-Start (nach „Beenden & erneut öffnen") hier ausgewertet.
    /// Mögliche Werte: "inputMonitoring", "accessibility".
    static let pendingPermissionKey = "ALVA.pendingPermissionRequest"

    /// Lebt nur kurz: ~3 s nach App-Start, danach baut HotkeyManager den
    /// produktiven Event-Tap. Siehe `warmUpInputMonitoringTap()`.
    private var warmUpTap: CFMachPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOlderInstances()

        // Clean up obsolete UserDefaults keys from when the reverse-
        // translate hotkey was user-configurable. Now fixed to ⌃⌥⌘L.
        AppCoordinator.migrateReverseTranslateDefaults()

        // v2.1.6.1: Mac-Wake-Notification — re-hydratisiert User-Settings,
        // falls macOS den App-Prozess während Sleep terminiert hat. Sonst
        // sprang der Transkriptions-Modus nach Wake auf den Default zurück
        // (#B-Wake).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleMacDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Warm-Up-Tap so früh wie möglich — VOR `coordinator.requestPermissions()`.
        // Registriert ALVA-TEXT in der TCC-Datenbank, sodass sie in
        // Systemeinstellungen → Eingabeüberwachung sofort mit Toggle
        // erscheint (statt nur per „+"-Knopf hinzufügbar).
        warmUpInputMonitoringTap()

        NSApp.setActivationPolicy(.accessory)
        coordinator.requestPermissions()

        menuController = StatusMenuController(coordinator: coordinator)
        coordinator.start()

        // License-Status hydratieren + täglichen Check starten. Blockiert
        // den Launch nicht — Ergebnis landet via LicenseState in der UI.
        LicenseState.shared.start()

        // v2.1.4: Linearer Onboarding-Flow.
        //
        // Onboarding zeigen, wenn:
        //   (a) noch nie gezeigt (Erst-Start), ODER
        //   (b) keine Aktivierung vorhanden — auch dann brauchen wir die
        //       Aktivierungs-Page als Pflicht-Schritt, statt den User in
        //       ein Settings-Fenster zu schicken (das parallel zum Onboarding
        //       laufen und das ganze UI verwirren würde).
        //
        // Die Aktivierungs-Logik selbst lebt jetzt im Onboarding-Schritt 2.
        // Der Account-Tab in den Settings bleibt für nachträglichen Logout
        // / Re-Aktivierung erreichbar, aber wird nicht mehr automatisch beim
        // App-Start geöffnet.
        let needsOnboarding = coordinator.shouldShowOnboarding || !LicenseClient.isActivated
        if needsOnboarding {
            // Falls eine alte hasSeenOnboarding=true-Markierung gesetzt war
            // aber die Aktivierung weg ist: Flag zurücksetzen, damit der
            // User wieder durch das volle Onboarding läuft.
            if !LicenseClient.isActivated {
                coordinator.resetOnboarding()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.coordinator.showOnboardingWindow()
            }
        }

        // Smart-Restart: Wenn die App gerade durch macOS' „Beenden & erneut
        // öffnen"-Dialog neu gestartet wurde (typischerweise nach einer
        // Eingabeüberwachung-Permission-Erteilung), führen wir den User
        // direkt zurück in den passenden Systemeinstellungs-Pane + öffnen
        // das Settings-Fenster auf dem „Systemfreigaben"-Tab. Damit er nicht
        // alleingelassen ist mit der Frage „und jetzt?".
        handlePendingPermissionResume()
    }

    // MARK: - Warm-Up-Tap (TCC-Registrierung Eingabeüberwachung)

    /// Erstellt einen passiven CGEvent-Tap mit `.listenOnly`. Der Tap fängt
    /// keine Tasten ab und tut nichts mit ihnen — sein einziger Zweck ist,
    /// dass macOS die App in der TCC-Datenbank für Eingabeüberwachung
    /// registriert. Ohne diesen Schritt würde ALVA-TEXT in der Permission-
    /// Liste nicht aufgeführt, und der User müsste sie manuell per „+"-Knopf
    /// hinzufügen, was dann zusätzlich den „Beenden & erneut öffnen"-Dialog
    /// auslöst.
    ///
    /// Der Tap wird nach 3 Sekunden zerstört — den eigentlichen produktiven
    /// Event-Tap (für F-Tasten-Sprachwahl, Rückwärtsübersetzung) baut der
    /// HotkeyManager später auf, sobald die Permission da ist.
    private func warmUpInputMonitoringTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: alvaWarmUpTapCallback,
            userInfo: nil
        ) else {
            // `tapCreate` kann nil zurückgeben, wenn die Permission noch
            // nicht erteilt ist — genau dieser Aufruf-Versuch ist es, der
            // macOS triggert, ALVA-TEXT in der TCC-Liste zu registrieren.
            // Beim nächsten Start (nachdem der User den Toggle gesetzt hat)
            // wird dieser Aufruf gelingen.
            print("ALVA: warm-up tap could not be created (permission pending — this is expected on first launch)")
            return
        }
        warmUpTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Nach 3 s wieder abbauen — der produktive Tap im HotkeyManager
        // übernimmt von hier ab.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, let tap = self.warmUpTap else { return }
            CGEvent.tapEnable(tap: tap, enable: false)
            self.warmUpTap = nil
        }
    }

    // MARK: - Smart-Restart (Permission-Workflow-Resume)

    /// Wertet das Pending-Permission-Flag aus UserDefaults aus. Wird gesetzt,
    /// wenn der User „Jetzt freigeben" für Bedienungshilfen oder
    /// Eingabeüberwachung geklickt hat. Wenn nach App-Restart das Flag noch
    /// gesetzt ist und die jeweilige Permission noch nicht erteilt wurde:
    /// Systemeinstellungs-Pane wieder öffnen + Settings-Fenster auf
    /// „Systemfreigaben"-Tab. Damit landet der User nach „Beenden & erneut
    /// öffnen" wieder in dem Kontext, aus dem er kam.
    private func handlePendingPermissionResume() {
        let key = Self.pendingPermissionKey
        guard let pending = UserDefaults.standard.string(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)

        // Kleines Delay, damit das Settings-Fenster und der Permission-State
        // hydratisiert sind (sonst zeigt er noch den alten Status).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            switch pending {
            case "inputMonitoring":
                if !self.coordinator.inputMonitoringTrusted {
                    self.coordinator.openInputMonitoringSettings()
                    self.coordinator.openSettings(initialTab: "system")
                }
            case "accessibility":
                if !self.coordinator.accessibilityTrusted {
                    self.coordinator.openAccessibilitySettings()
                    self.coordinator.openSettings(initialTab: "system")
                }
            default:
                break
            }
        }
    }

    // MARK: - Mac Wake Handling (v2.1.6.1)

    /// macOS sendet `NSWorkspace.didWakeNotification` an alle registrierten
    /// Observer, sobald der Mac aus dem Sleep zurückkehrt. Wir nutzen das,
    /// um sicherzustellen, dass User-Settings — speziell der vom User
    /// gewählte Transkriptions-Modus — korrekt aus UserDefaults restauriert
    /// werden. Vorher konnte es passieren, dass nach Wake der Modus auf
    /// .local zurücksprang, weil der App-Prozess während Sleep terminiert
    /// und neu gestartet wurde.
    @objc private func handleMacDidWake(_ notification: Notification) {
        print("ALVA: Mac did wake — re-hydrating user preferences")
        Task { @MainActor in
            coordinator.rehydrateUserPreferences()
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
