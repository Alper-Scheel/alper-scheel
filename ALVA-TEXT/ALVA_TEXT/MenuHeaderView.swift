import SwiftUI
import AppKit
import CryptoKit

/// SwiftUI-Header, der als erstes Item in das Status-Bar-Menu eingefügt wird.
///
/// Layout analog zu Tailscale: links der Avatar (Gravatar, fallback initiale
/// Buchstaben), daneben Registrierungs-Zustand + E-Mail-Adresse, rechts ein
/// Toggle, das `AppCoordinator.isPaused` flippt.
///
/// Die View bleibt funktional, auch wenn noch keine Aktivierung stattgefunden
/// hat — sie zeigt dann „Nicht aktiviert" und bietet einen Klick-Hook, der
/// die Settings → Account-Tab öffnet.
struct MenuHeaderView: View {

    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var license: LicenseState

    /// Wird gesetzt, wenn der Header auf „Aktivieren"-Klick reagieren soll.
    var onActivate: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AvatarView(email: license.currentEmail)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(secondaryLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { !coordinator.isPaused },
                set: { coordinator.isPaused = !$0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(coordinator.isPaused ? "ALVA-TEXT ist pausiert — Hotkeys inaktiv"
                                        : "ALVA-TEXT ist aktiv — Hotkeys reagieren")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            // Klick auf den Text-Bereich öffnet Settings (wenn nicht aktiviert:
            // als Einladung zur Aktivierung). Der Toggle schluckt seine eigenen
            // Klicks, also wird die Geste nur auf der Textfläche ausgelöst.
            if license.currentEmail == nil { onActivate() }
        }
    }

    // MARK: - Beschriftung
    //
    // Zwei Zeilen: primary ist die wichtigste Info (App-Name wenn aktiviert,
    // Status wenn nicht), secondary ist der Kontext darunter. Beide strikt
    // einzeilig und kurz, damit bei begrenzter Menü-Breite nichts abgeschnitten
    // wird.

    private var primaryLabel: String {
        if license.currentEmail != nil { return "ALVA-TEXT" }
        switch license.phase {
        case .needsActivation: return "Nicht aktiviert"
        case .revoked:         return "Zugang widerrufen"
        case .expired:         return "Trial abgelaufen"
        case .loading:         return "Wird geprüft…"
        case .error:           return "Verbindungsfehler"
        case .active:          return "ALVA-TEXT"
        }
    }

    private var secondaryLabel: String {
        if let email = license.currentEmail {
            return email
        }
        switch license.phase {
        case .needsActivation: return "Jetzt aktivieren"
        case .revoked:         return "Support kontaktieren"
        case .expired:         return "Lizenz erwerben"
        case .loading:         return "Status wird geladen"
        case .error:           return "Netzwerk prüfen"
        case .active:          return ""
        }
    }
}

// MARK: - Avatar

/// Zeigt das Gravatar-Bild der E-Mail-Adresse. Fallback: runder Kreis mit
/// dem Großbuchstaben-Initial (oder einem generischen Person-Symbol, wenn
/// keine E-Mail bekannt ist).
///
/// Gravatar: SHA-256-Hash der getrimmten, kleingeschriebenen E-Mail.
/// `d=identicon` liefert hübsche generative Bilder für unbekannte E-Mails.
struct AvatarView: View {
    let email: String?

    @State private var image: NSImage?
    @State private var loadFailed: Bool = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.22))
                if let mail = email, !mail.isEmpty {
                    Text(initial(for: mail))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay(
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
        .task(id: email ?? "") {
            await loadGravatar()
        }
    }

    private func initial(for email: String) -> String {
        let first = email.first { $0.isLetter } ?? email.first ?? "?"
        return String(first).uppercased()
    }

    private func loadGravatar() async {
        guard let raw = email?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            image = nil
            return
        }
        let hash = sha256Hex(raw)
        // `d=identicon` = generatives Fallback bei unbekannten E-Mails;
        // so sieht auch ein „Gravatar-loser" Nutzer nicht nackt aus.
        let urlString = "https://gravatar.com/avatar/\(hash)?s=72&d=identicon"
        guard let url = URL(string: urlString) else { return }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 4
            req.setValue("ALVA-TEXT/\(LicenseClient.appVersion)", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                await MainActor.run { loadFailed = true }
                return
            }
            if let ns = NSImage(data: data) {
                await MainActor.run { self.image = ns }
            }
        } catch {
            await MainActor.run { loadFailed = true }
        }
    }

    private func sha256Hex(_ s: String) -> String {
        let data = Data(s.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
