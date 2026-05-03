import SwiftUI

/// Zwei-stufiger Aktivierungs-Flow (Email → Code). Wird als Sheet aus dem
/// Settings-Fenster präsentiert, wenn `LicenseState.phase == .needsActivation`.
struct ActivationView: View {

    @ObservedObject var state: LicenseState
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .email
    @State private var email: String = ""
    @State private var code: String = ""
    @State private var infoMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    private enum Step { case email, code, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            switch step {
            case .email: emailStep
            case .code:  codeStep
            case .done:  doneStep
            }

            Spacer(minLength: 0)

            // v2.1.5: Im Done-Step keine Error/Info-Messages mehr anzeigen.
            // Nach erfolgreicher Aktivierung können Background-Checks
            // (License-Refresh, Daily-Heartbeat) noch HTTP-Errors werfen
            // (z.B. 500 wegen DB-Race) — die User-Bedeutung ist aber Null,
            // die Aktivierung selbst ist durch. Den User mit „Server-Antwort
            // 500" in Rot zu konfrontieren ist UX-Killer (#B13).
            if step != .done {
                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                if let info = infoMessage {
                    Label(info, systemImage: "info.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 320)
    }

    // MARK: Steps

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ALVA-TEXT aktivieren")
                .font(.title2.weight(.semibold))
            // v2.1.5: kein „Beta-Zugang"-Wording mehr (#B12)
            Text("Vollzugang mit deiner E-Mail freischalten.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("E-Mail")
                .font(.callout.weight(.medium))
            TextField("du@beispiel.de", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .disableAutocorrection(true)
                .onSubmit { Task { await requestCode() } }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Code senden") {
                    Task { await requestCode() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidEmail || isBusy)
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("6-stelliger Code")
                .font(.callout.weight(.medium))
            Text("Eine E-Mail an **\(email)** mit deinem Code wurde gesendet. Gültig 15 Minuten.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("123456", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced))
                .onChange(of: code) { _, new in
                    // Nur Ziffern zulassen, max 6
                    let digits = new.filter(\.isNumber).prefix(6)
                    if String(digits) != new { code = String(digits) }
                    if code.count == 6 { Task { await submitCode() } }
                }

            HStack {
                Button("Andere E-Mail") { step = .email; errorMessage = nil; infoMessage = nil }
                    .buttonStyle(.link)
                Spacer()
                Button("Erneut senden") { Task { await requestCode() } }
                    .disabled(isBusy)
                Button("Aktivieren") { Task { await submitCode() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.count != 6 || isBusy)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .frame(width: 56, height: 56)
                .foregroundStyle(.green)
            Text("Aktivierung abgeschlossen")
                .font(.title3.weight(.semibold))
            // v2.1.5: keine technischen Server-Strings („Status: beta · Tier: full")
            // mehr im UI — die sind für den Endnutzer Kauderwelsch (#B12).
            // Stattdessen nur die geschäftlich relevante Aussage.
            if case .active(_, let tier, _) = state.phase, tier != .limited {
                Text("Voller Funktionsumfang freigeschaltet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Logic

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    private func requestCode() async {
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await state.requestCode(for: email.trimmingCharacters(in: .whitespacesAndNewlines))
            infoMessage = "Code gesendet. Schau in dein Postfach."
            step = .code
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func submitCode() async {
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await state.submitCode(email: email, code: code)
            step = .done
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            code = ""
        }
    }
}

#Preview {
    ActivationView(state: .shared)
}
