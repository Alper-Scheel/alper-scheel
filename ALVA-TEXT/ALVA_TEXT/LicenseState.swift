import Foundation
import Combine
import SwiftUI
import os.log

/// Zentraler Observable-Zustand für alles Lizenzbezogene.
///
/// Die App liest `state.phase` beim Start:
///  - `.needsActivation` → Aktivierungs-Flow anzeigen
///  - `.active(.full)`   → Alle Funktionen freischalten
///  - `.active(.limited)`→ Kostenpflichtige Funktionen sperren, Paywall anzeigen
///  - `.revoked`         → Hart sperren, Aktivierung erneut anfordern
///
/// Startet automatisch einen Daily-Check, wenn der letzte Check älter als
/// `refreshInterval` ist, und wiederholt ihn alle 24 h über einen Timer.
@MainActor
final class LicenseState: ObservableObject {

    // MARK: Public state

    enum Tier: String { case full, limited, paid }

    enum Phase: Equatable {
        case loading                      // Initialer Hydrate aus Keychain
        case needsActivation              // Kein Token
        case active(status: String, tier: Tier, message: String?)
        case expired(message: String?)    // Trial abgelaufen, nicht mehr erlaubt
        case revoked(message: String?)    // Von Admin oder User widerrufen
        case error(String)                // Netzwerk/Server-Fehler, mit Cache-Fallback

        var isUsable: Bool {
            switch self {
            case .active(_, let tier, _):
                return tier != .limited
            case .loading:
                return true   // Optimistisch: nicht blocken, bevor der Check läuft
            default:
                return false
            }
        }
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lastCheck: Date?
    @Published private(set) var trialExpiresAt: Date?
    /// Registrierte E-Mail-Adresse (für Menu-Bar-Header / Avatar). `nil`,
    /// solange keine erfolgreiche Aktivierung stattgefunden hat.
    @Published private(set) var currentEmail: String?

    static let shared = LicenseState()

    private static let log = Logger(subsystem: "com.adserica.alvatext", category: "LicenseState")
    private let refreshInterval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?

    // MARK: Bootstrapping

    private init() {
        hydrateFromCache()
    }

    /// App-Delegate ruft das beim Launch auf. Setzt den Phase anhand Keychain-Cache
    /// und startet sofort einen echten Check im Hintergrund (nicht blockierend).
    func start() {
        hydrateFromCache()
        Task { await performCheckIfDue(force: true) }
        scheduleDailyTimer()
    }

    private func hydrateFromCache() {
        currentEmail = LicenseClient.cachedEmail()
        guard LicenseClient.isActivated else {
            phase = .needsActivation
            return
        }
        if let cached = LicenseClient.cachedStatus() {
            lastCheck = cached.lastCheck
            phase = mapPhase(status: cached.status, tier: cached.tier, message: nil)
        } else {
            phase = .loading
        }
    }

    private func scheduleDailyTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.performCheckIfDue(force: false) }
        }
    }

    // MARK: Actions

    /// Fordert einen Code an. UI zeigt danach einen Code-Input-Screen.
    func requestCode(for email: String) async throws {
        _ = try await LicenseClient.requestActivationCode(email: email)
    }

    /// Löst Code ein. Bei Erfolg: neuer Token im Keychain, Phase aktualisiert.
    func submitCode(email: String, code: String) async throws {
        let resp = try await LicenseClient.verifyActivation(email: email, code: code)
        lastCheck = Date()
        currentEmail = email
        phase = mapPhase(status: resp.status, tier: resp.tier, message: resp.message)
        Self.log.info("Activation verified → status=\(resp.status) tier=\(resp.tier)")
    }

    /// Manueller Refresh — z.B. wenn User „Jetzt prüfen" klickt.
    func refresh() async {
        await performCheckIfDue(force: true)
    }

    /// User-initiierter Logout (löscht lokalen Token).
    func signOut() {
        LicenseClient.deactivateLocally()
        trialExpiresAt = nil
        lastCheck = nil
        currentEmail = nil
        phase = .needsActivation
    }

    // MARK: Network

    private func performCheckIfDue(force: Bool) async {
        guard LicenseClient.isActivated else {
            phase = .needsActivation
            return
        }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < refreshInterval { return }

        do {
            let resp = try await LicenseClient.performDailyCheck()
            lastCheck = Date()
            trialExpiresAt = resp.trialExpiresAt
            phase = mapPhase(status: resp.status, tier: resp.tier, message: resp.message)
        } catch LicenseClient.LicenseError.notActivated {
            phase = .needsActivation
        } catch LicenseClient.LicenseError.httpStatus(let code, let detail) {
            // 401 = Token ungültig → neu aktivieren lassen
            if code == 401 {
                LicenseClient.deactivateLocally()
                phase = .needsActivation
            } else {
                phase = .error("HTTP \(code)" + (detail.map { " — \($0)" } ?? ""))
            }
            Self.log.error("License check HTTP error: \(code)")
        } catch {
            // Netzwerk-Fehler: Cache-Phase behalten, damit der User offline weiterarbeiten kann
            Self.log.error("License check failed: \(error.localizedDescription)")
            if case .loading = phase {
                phase = .error(error.localizedDescription)
            }
        }
    }

    // MARK: Mapping

    private func mapPhase(status: String, tier: String, message: String?) -> Phase {
        let t = Tier(rawValue: tier) ?? .limited
        switch status {
        case "beta", "trial", "active":
            return .active(status: status, tier: t, message: message)
        case "expired":
            return .expired(message: message)
        case "revoked":
            return .revoked(message: message)
        default:
            return .error("Unbekannter Server-Status: \(status)")
        }
    }
}
