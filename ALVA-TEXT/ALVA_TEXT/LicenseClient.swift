import Foundation
import os.log

/// HTTP-Client für die AdLuna Platform API.
///
/// Verantwortlich für:
///   * Anfordern + Einlösen eines Aktivierungs-Codes
///   * Täglicher Status-Check mit Bearer-Device-Token
///   * Device-UUID + Token-Persistenz via `KeychainStore`
///
/// Alle Netzwerk-Calls sind `async throws` und blockieren niemals den Main-Actor.
/// `LicenseState` (ObservableObject) konsumiert die Ergebnisse und informiert die UI.
struct LicenseClient {

    // MARK: - Config

    /// Basis-URL der Platform-API. Kommt per Info.plist-Key
    /// `ADLunaPlatformAPIURL`, damit DEV/STAGING/PROD über separate Builds
    /// schaltbar sind. Fallback: Produktions-URL.
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ADLunaPlatformAPIURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://api.adluna.de")!
    }

    /// Produkt-ID wie im `products`-Table der Platform-API.
    static let productID = "alva-text"

    /// Keychain-Accounts — Namen bleiben stabil, damit Token bei App-Updates erhalten bleiben.
    private enum Account {
        static let deviceToken = "adluna.device.token"
        static let deviceUUID = "adluna.device.uuid"
        static let lastCheckISO = "adluna.last_check_iso"
        static let lastStatus = "adluna.last_status"
        static let lastTier = "adluna.last_tier"
        static let userEmail = "adluna.user.email"
    }

    private static let log = Logger(subsystem: "com.adserica.alvatext", category: "LicenseClient")

    // MARK: - Errors

    enum LicenseError: LocalizedError {
        case invalidURL
        case notActivated
        case httpStatus(Int, String?)
        case decodeFailed(String)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Interne URL-Konfiguration ungültig."
            case .notActivated: return "Dieses Gerät ist noch nicht aktiviert."
            case .httpStatus(let code, let detail):
                return "Server-Antwort \(code)" + (detail.map { ": \($0)" } ?? "")
            case .decodeFailed(let what):
                return "Server-Antwort nicht verarbeitbar: \(what)"
            case .transport(let err):
                return "Verbindung fehlgeschlagen: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Device-UUID

    /// Erzeugt (oder liest) eine stabile Device-UUID. Wird bei Erst-Start
    /// generiert und ab dann im Keychain gehalten, damit sie Neuinstallationen
    /// der App überlebt — der Nutzer muss dann nicht erneut aktivieren.
    static func deviceUUID() -> String {
        if let existing = KeychainStore.get(Account.deviceUUID), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        KeychainStore.set(fresh, for: Account.deviceUUID)
        log.info("Generated new device UUID")
        return fresh
    }

    /// Gerätename (Hostname) für anzeigbare Device-Listen im Account.
    static var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// App-Version aus dem Bundle (für `app_version` im License-Check).
    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    // MARK: - Token-Handling

    /// Liefert `true`, wenn ein Device-Token im Keychain liegt.
    static var isActivated: Bool {
        (KeychainStore.get(Account.deviceToken)?.isEmpty == false)
    }

    /// Löscht Token + gecachten Status. Nutzt man beim User-initiierten Logout.
    static func deactivateLocally() {
        KeychainStore.delete(account: Account.deviceToken)
        KeychainStore.delete(account: Account.lastStatus)
        KeychainStore.delete(account: Account.lastTier)
        KeychainStore.delete(account: Account.lastCheckISO)
        KeychainStore.delete(account: Account.userEmail)
        log.info("Local deactivation complete")
    }

    // MARK: - Endpoints

    /// `POST /v1/activation/request` — sendet 6-stelligen Code an `email`.
    static func requestActivationCode(email: String) async throws -> ActivationRequestResponse {
        let body: [String: Any] = [
            "email": email,
            "product": productID,
            "device_uuid": deviceUUID()
        ]
        return try await post("/v1/activation/request", body: body, auth: nil)
    }

    /// `POST /v1/activation/verify` — tauscht Code gegen Device-Token.
    /// Speichert Token + Status + Tier direkt im Keychain.
    static func verifyActivation(email: String, code: String) async throws -> ActivationVerifyResponse {
        let body: [String: Any] = [
            "email": email,
            "product": productID,
            "device_uuid": deviceUUID(),
            "code": code
        ]
        let resp: ActivationVerifyResponse = try await post("/v1/activation/verify", body: body, auth: nil)
        KeychainStore.set(resp.token, for: Account.deviceToken)
        KeychainStore.set(resp.status, for: Account.lastStatus)
        KeychainStore.set(resp.tier, for: Account.lastTier)
        KeychainStore.set(email, for: Account.userEmail)
        KeychainStore.set(ISO8601DateFormatter().string(from: .init()), for: Account.lastCheckISO)
        log.info("Activation verified; token stored")
        return resp
    }

    /// Liefert die aktivierte E-Mail-Adresse (Keychain-Cache), oder `nil`
    /// wenn das Gerät nicht aktiviert wurde.
    static func cachedEmail() -> String? {
        let v = KeychainStore.get(Account.userEmail)
        return (v?.isEmpty ?? true) ? nil : v
    }

    /// `POST /v1/license/check` — täglicher Ping mit Bearer-Auth.
    /// Aktualisiert Keychain-Cache. Wirft `notActivated`, wenn kein Token da ist.
    static func performDailyCheck() async throws -> LicenseCheckResponse {
        guard let token = KeychainStore.get(Account.deviceToken), !token.isEmpty else {
            throw LicenseError.notActivated
        }
        let body: [String: Any] = [
            "product": productID,
            "device_uuid": deviceUUID(),
            "app_version": appVersion
        ]
        let resp: LicenseCheckResponse = try await post("/v1/license/check", body: body, auth: token)
        KeychainStore.set(resp.status, for: Account.lastStatus)
        KeychainStore.set(resp.tier, for: Account.lastTier)
        KeychainStore.set(ISO8601DateFormatter().string(from: .init()), for: Account.lastCheckISO)
        log.debug("License check: status=\(resp.status) tier=\(resp.tier)")
        return resp
    }

    /// Letzter gecachter Status (für Offline-Start der UI, bevor ein frischer Check läuft).
    static func cachedStatus() -> (status: String, tier: String, lastCheck: Date?)? {
        guard let st = KeychainStore.get(Account.lastStatus),
              let ti = KeychainStore.get(Account.lastTier) else { return nil }
        let lc = KeychainStore.get(Account.lastCheckISO).flatMap { ISO8601DateFormatter().date(from: $0) }
        return (st, ti, lc)
    }

    // MARK: - Core HTTP

    private static func post<T: Decodable>(_ path: String, body: [String: Any], auth: String?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw LicenseError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ALVA-TEXT/\(appVersion)", forHTTPHeaderField: "User-Agent")
        if let auth { req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw LicenseError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.decodeFailed("non-HTTP response")
        }

        if !(200..<300).contains(http.statusCode) {
            let detail = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.detail
            throw LicenseError.httpStatus(http.statusCode, detail)
        }

        do {
            return try JSONDecoder.licenseDecoder.decode(T.self, from: data)
        } catch {
            throw LicenseError.decodeFailed(String(describing: error))
        }
    }
}

// MARK: - DTOs

struct ActivationRequestResponse: Decodable {
    let ok: Bool
    let message: String
}

struct ActivationVerifyResponse: Decodable {
    let ok: Bool
    let token: String
    let status: String   // beta|trial|active|expired|revoked
    let tier: String     // full|limited|paid
    let message: String?
}

struct LicenseCheckResponse: Decodable {
    let status: String
    let tier: String
    let message: String?
    let checkAgainIn: Int
    let trialExpiresAt: Date?
}

private struct ErrorEnvelope: Decodable {
    let detail: String?
}

private extension JSONDecoder {
    static let licenseDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()
        isoNoFraction.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = iso.date(from: s) ?? isoNoFraction.date(from: s) { return date }
            // Fallback: naive ISO ohne Zone (Server liefert `datetime.utcnow().isoformat()`)
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .iso8601)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss[.SSSSSS]"
            if let date = df.date(from: s) { return date }
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = df.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unparseable date: \(s)"))
        }
        return d
    }()
}
