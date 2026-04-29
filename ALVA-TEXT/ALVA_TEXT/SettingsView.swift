import SwiftUI

// MARK: - Root

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTab: String = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tag("general")
                .tabItem { Label("Allgemein", systemImage: "gearshape") }

            SystemTab()
                .tag("system")
                .tabItem { Label("Systemfreigaben", systemImage: "lock.shield") }

            ShortcutsTab()
                .tag("shortcuts")
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            LanguagesTab()
                .tag("languages")
                .tabItem { Label("Sprachen", systemImage: "character.bubble") }

            PersonalizationTab()
                .tag("personalization")
                .tabItem { Label("Persönlich", systemImage: "person.text.rectangle") }

            HistoryTab()
                .tag("history")
                .tabItem { Label("Verlauf", systemImage: "clock.arrow.circlepath") }

            AccountTab()
                .tag("account")
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 600)
        .onAppear {
            // Wenn beim Öffnen ein spezieller Tab gewünscht wurde
            // (z.B. beim ersten Launch automatisch "account"), dorthin
            // springen und den Wunsch zurücksetzen.
            if let requested = coordinator.settingsRequestedTab {
                selectedTab = requested
                coordinator.settingsRequestedTab = nil
            }
        }
        .onChange(of: coordinator.settingsRequestedTab) { _, new in
            if let new {
                selectedTab = new
                coordinator.settingsRequestedTab = nil
            }
        }
    }
}

// MARK: - Card Container

private struct Card<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var accent: Color = .accentColor
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(accent)
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Allgemein

/// Allgemein-Tab. Übersichts-Seite analog zum About-Tab in Tailscale:
/// Logo, Version, Lizenz-Links, Status der Aktivierung, Hinweise zum
/// lokalen Betrieb. Die eigentliche Konfiguration wandert in den
/// Systemfreigaben-Tab — hier ist nur Lesen, keine Verhaltens-
/// Einstellungen.
private struct GeneralTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var license = LicenseState.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AboutCard()
                AccountStatusHeader()
                if license.currentEmail != nil {
                    GravatarHintRow()
                }
                LocalProcessingHintCard()
                TranscriptionBackendCard()
            }
            .padding(2)
        }
    }
}

// MARK: - About-Block + Hinweise (im Allgemein-Tab)

/// Über-Block oben im Allgemein-Tab — analog zum About-Pane in
/// Tailscale. Zeigt Logo, App-Name, Version + Build, Notarisierung
/// und Links zu Datenschutz/AGB/Open-Source-Lizenzen. In v1.2.0
/// kommt hier zusätzlich der Auto-Update-Toggle (Sparkle) dazu —
/// die Card-Struktur ist darauf vorbereitet.
private struct AboutCard: View {
    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(v) (Build \(b))"
    }

    /// macOS füllt `applicationIconImage` für Menu-Bar-Apps nicht
    /// immer zuverlässig — daher zuerst aus dem Asset-Catalog laden,
    /// dann fallback.
    private var appIconImage: NSImage? {
        if let asset = NSImage(named: "AppIcon") { return asset }
        return NSApp.applicationIconImage
    }

    var body: some View {
        Card(title: "Über ALVA-TEXT",
             subtitle: "Version, Datenschutz und Lizenzbedingungen",
             icon: "info.circle.fill",
             accent: .blue) {
            HStack(alignment: .top, spacing: 16) {
                if let icon = appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ALVA-TEXT")
                        .font(.title3.weight(.semibold))
                    Text(versionText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Apple-notarisiert · signiert von AdPolis GmbH")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            Divider().padding(.vertical, 4)

            HStack(spacing: 16) {
                Link("Datenschutz",
                     destination: URL(string: "https://adluna.de/datenschutz")!)
                Link("AGB",
                     destination: URL(string: "https://adluna.de/agb")!)
                Link("Lizenzen Dritter",
                     destination: URL(string: "https://adluna.de/lizenzen")!)
                Spacer()
                Text("© 2026 AdLuna GmbH")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}

/// Kompakter Gravatar-Hinweis direkt unter der Account-Statuszeile.
/// Nur sichtbar wenn der Nutzer aktiviert ist (sonst gibt es keinen
/// Avatar zu konfigurieren). Vorher als prominente Card im Account-
/// Tab — dort entfernt, hier kompakt platziert.
private struct GravatarHintRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.crop.circle.dashed")
                .foregroundStyle(.secondary)
                .font(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dein Profilbild kommt von Gravatar — einem weltweiten Avatar-Dienst, der dein Bild mit deiner E-Mail verknüpft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Eigenes Bild bei gravatar.com einrichten",
                     destination: URL(string: "https://gravatar.com")!)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

/// Erklär-Kachel zum lokalen Betrieb. Adressiert die wichtigste
/// Sorge der Zielgruppe („Wo gehen meine Daten hin?") direkt im
/// Allgemein-Tab und macht klar, wofür Internet überhaupt benötigt
/// wird.
private struct LocalProcessingHintCard: View {
    var body: some View {
        Card(title: "Lokal auf deinem Mac",
             subtitle: "Internet nur für Aktivierung und Updates",
             icon: "lock.shield.fill",
             accent: .green) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Komplett lokal über Whisper:", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Text("Deutsches Diktat (Standard-Modus) und die direkte Übersetzung ins Englische funktionieren komplett offline — die Audio-Daten verlassen deinen Mac nicht.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.vertical, 2)

                Label("Internet-Verbindung wird benötigt für:", systemImage: "network")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("die einmalige Aktivierung, optionale OpenAI-Funktionen (Höflich-/Nachrichten-Modus, Übersetzung in andere Zielsprachen außer Englisch) und die Update-Prüfung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ModeCard(
                    title: "Standard",
                    subtitle: "Direktes Transkript, leicht geglättet",
                    description: "Halten, diktieren, loslassen. Der Text wird 1:1 transkribiert und nur leicht bereinigt. Für schnelle Notizen und Rohtext.",
                    icon: "mic.fill",
                    accent: .blue,
                    config: $coordinator.standardHotkey
                )

                ModeCard(
                    title: "Höflich",
                    subtitle: "Knapp und verbindlich umformuliert",
                    description: "Für E-Mails und freundliche Nachrichten. Der Text wird auf gepflegtes, nachrichtentaugliches Deutsch gebracht.",
                    icon: "hand.wave.fill",
                    accent: .green,
                    config: $coordinator.politeHotkey
                )

                ModeCard(
                    title: "Nachricht",
                    subtitle: "Adaptiver Chat- und Social-Media-Stil",
                    description: "Passt sich dem Ton des Diktats an (Du/Sie, locker/formell). Keine KI-Floskeln, keine Semikolons, keine erfundenen Höflichkeiten. Für WhatsApp, Signal, kurze Mails.",
                    icon: "bubble.left.and.bubble.right.fill",
                    accent: .orange,
                    config: $coordinator.messageHotkey
                )

                Card(title: "Timing", subtitle: "Feinabstimmung Aufnahme & Toggle", icon: "timer", accent: .purple) {
                    LabeledSlider(
                        label: "Doppeldruck-Fenster",
                        value: $coordinator.doublePressWindow,
                        range: 0.15...0.80,
                        step: 0.05,
                        unit: "ms",
                        scale: 1000
                    )
                    LabeledSlider(
                        label: "Mindest-Aufnahmedauer",
                        value: $coordinator.minimumRecordingDuration,
                        range: 0.1...1.5,
                        step: 0.05,
                        unit: "ms",
                        scale: 1000
                    )
                }

                Card(title: "Defaults", icon: "arrow.uturn.backward", accent: .gray) {
                    HStack {
                        Button("Modi-Kürzel zurücksetzen") {
                            coordinator.resetHotkeyDefaults()
                        }
                        Spacer()
                    }

                    ForEach(warnings(), id: \.self) { msg in
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
            .padding(2)
        }
    }

    /// Lists all validation / collision warnings for the current configuration.
    private func warnings() -> [String] {
        var msgs: [String] = []
        let s = coordinator.standardHotkey
        let p = coordinator.politeHotkey
        let m = coordinator.messageHotkey

        if !s.isValid || !p.isValid || !m.isValid {
            msgs.append("Ein Modus hat keinen Modifier gesetzt — dieser Modus löst nie aus.")
        }
        if s.isValid && p.isValid && s.modifierFlags == p.modifierFlags {
            msgs.append("Standard und Höflich verwenden dieselbe Kombination — nur Standard löst aus.")
        }
        if s.isValid && m.isValid && s.modifierFlags == m.modifierFlags {
            msgs.append("Standard und Nachricht verwenden dieselbe Kombination — nur Standard löst aus.")
        }
        if p.isValid && m.isValid && p.modifierFlags == m.modifierFlags {
            msgs.append("Höflich und Nachricht verwenden dieselbe Kombination — nur Höflich löst aus.")
        }
        return msgs
    }
}

// MARK: - Sprachen

/// Sprachen-Tab. Konfiguriert Sprach-Zuweisungen für die F-Tasten-
/// Schnellumschaltung und die Rückwärtsübersetzung. Der frühere
/// Permission-Block ganz oben wurde nach v2.1.2 in den Tab
/// „Systemfreigaben" verschoben — dort ist die Einrichtung der
/// Eingabeüberwachung zentral mit allen anderen System-Setups
/// gebündelt.
private struct LanguagesTab: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LanguageBindingsCard()

                Card(title: "Defaults", icon: "arrow.uturn.backward", accent: .gray) {
                    HStack {
                        Button("Sprach-Zuweisungen zurücksetzen") {
                            coordinator.resetLanguageBindings()
                        }
                        Spacer()
                    }
                }

                ReverseTranslateCard()
            }
            .padding(2)
        }
    }
}

private struct InputMonitoringCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Binding var tick: Int
    @State private var showHelp: Bool = false

    var body: some View {
        PermissionCard(
            title: "Eingabeüberwachung",
            subtitle: "Ermöglicht F-Tasten-Sprachwahl und Rückwärtsübersetzung",
            trusted: coordinator.inputMonitoringTrusted,
            trustedLabel: "F-Tasten für Sprachwahl und ⌃⌥Return für Rückwärtsübersetzung werden erkannt.",
            missingLabel: "Ohne diese Erlaubnis sehen wir keine Tasten-Events anderer Apps. F-Tasten, Any-Key-Stop und Rückwärtsübersetzung bleiben stumm.",
            primaryAction: {
                // Pending-Flag setzen — falls macOS die App jetzt mit
                // „Beenden & erneut öffnen" beendet, führt der nächste
                // Start den User zurück in diesen Permission-Pane.
                UserDefaults.standard.set("inputMonitoring",
                                          forKey: AppDelegate.pendingPermissionKey)
                coordinator.requestInputMonitoringPrompt()
                coordinator.openInputMonitoringSettings()
            },
            primaryLabel: "Jetzt freigeben",
            secondaryAction: nil,
            secondaryLabel: "",
            helpExpanded: $showHelp,
            helpText: "Systemeinstellungen → Datenschutz & Sicherheit → Eingabeüberwachung. ALVA-TEXT hinzufügen und aktivieren. Nach Xcode-Rebuilds ggf. alten Eintrag entfernen und die neu gebaute App erneut hinzufügen."
        )
    }
}

private struct TranscriptionBackendCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var loadTick: Int = 0

    var body: some View {
        let isLocalAvailable = coordinator.localWhisper.isAvailable
        Card(title: "Transkriptions-Modus",
             subtitle: "Wo die Sprache-zu-Text-Umwandlung passiert",
             icon: "waveform",
             accent: .teal) {

            Picker("Modus", selection: $coordinator.transcriptionBackend) {
                ForEach(TranscriptionBackend.allCases, id: \.self) { backend in
                    Text(backend.germanLabel).tag(backend)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(coordinator.transcriptionBackend.germanDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Divider().padding(.vertical, 2)

            // Local model status row
            HStack(spacing: 10) {
                Image(systemName: localStatusIcon(isAvailable: isLocalAvailable))
                    .font(.title3)
                    .foregroundStyle(localStatusColor(isAvailable: isLocalAvailable))
                VStack(alignment: .leading, spacing: 2) {
                    Text(localStatusTitle(isAvailable: isLocalAvailable))
                        .fontWeight(.medium)
                    Text(localStatusDetail(isAvailable: isLocalAvailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Prüfen") { loadTick &+= 1 }
                    .buttonStyle(.bordered)
            }
            .id(loadTick)

            if !isLocalAvailable {
                Label("So fügst du WhisperKit hinzu: Xcode → File → Add Package Dependencies → https://github.com/argmaxinc/WhisperKit → Add Package → WhisperKit anhaken → Add. Dann Clean Build Folder (⌘⇧K) und erneut bauen.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func localStatusIcon(isAvailable: Bool) -> String {
        if !isAvailable { return "exclamationmark.triangle.fill" }
        if coordinator.localWhisper.isReady { return "checkmark.circle.fill" }
        return "arrow.down.circle"
    }

    private func localStatusColor(isAvailable: Bool) -> Color {
        if !isAvailable { return .orange }
        if coordinator.localWhisper.isReady { return .green }
        return .blue
    }

    private func localStatusTitle(isAvailable: Bool) -> String {
        if !isAvailable { return "Lokales Modell nicht eingebunden" }
        if coordinator.localWhisper.isReady { return "Whisper-Small geladen" }
        return "Whisper-Small — wird beim ersten Lokal-Transkript geladen"
    }

    private func localStatusDetail(isAvailable: Bool) -> String {
        if !isAvailable {
            return "WhisperKit-Swift-Package noch nicht zum Xcode-Projekt hinzugefügt. Siehe Anleitung unten."
        }
        if coordinator.localWhisper.isReady {
            return "Ready. Läuft mit Metal-Beschleunigung direkt auf deinem Mac."
        }
        return "Einmaliger Download ca. 466 MB, wird nach Application Support abgelegt."
    }
}

private struct ReverseTranslateCard: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Card(title: "Rückwärtsübersetzung",
             subtitle: "Markierten Text ins Deutsche übersetzen",
             icon: "character.book.closed.fill",
             accent: .purple) {

            HStack(alignment: .top, spacing: 16) {
                // Fixed shortcut preview: ⌃⌥⌘L — not configurable.
                Text("⌃⌥⌘\u{2009}L")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .frame(minWidth: 150, minHeight: 56)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(coordinator.reverseTranslateEnabled ? 0.10 : 0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.purple.opacity(coordinator.reverseTranslateEnabled ? 0.3 : 0.1), lineWidth: 1)
                    )
                    .foregroundStyle(coordinator.reverseTranslateEnabled ? .primary : .secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text in einer beliebigen App markieren, dann **⌃⌥⌘L** drücken. ALVA kopiert die Auswahl, übersetzt sie ins Deutsche und zeigt das Ergebnis in einem Popup mit Kopieren-Button. Die Zwischenablage wird danach wieder auf ihren ursprünglichen Inhalt zurückgesetzt.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Divider().padding(.vertical, 2)

            Toggle("Rückwärtsübersetzung aktivieren", isOn: $coordinator.reverseTranslateEnabled)

            Text("Das Kürzel ist fest auf ⌃⌥⌘L gelegt (L wie Language). Drei Modifier zusammen sind die einzige Kombination, die garantiert in allen Apps funktioniert — auch in Word, Excel, Keynote und Mail, wo einfachere Kürzel wie ⌃⌥Return oder ⌥⇧Return von App-eigenen Bindings (Kontextmenü, Zeilenumbruch) geschluckt werden.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LanguageBindingsCard: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Card(title: "Zielsprachen",
             subtitle: "F-Tasten während Aufnahme für Übersetzung",
             icon: "character.bubble.fill",
             accent: .indigo) {

            VStack(alignment: .leading, spacing: 6) {
                Text("Während einer laufenden Aufnahme die Aufnahme-Taste gehalten lassen und zusätzlich **Fn + F-Taste** kurz antippen. Nach Aufnahmeende wird der Text in die gewählte Sprache übersetzt — die deutsche Fassung wird ersetzt, nicht angehängt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Beispiel: ⌃ halten, sprechen, Fn+F1 antippen, ⌃ loslassen → englische Version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.top, 2)
            }

            if coordinator.languageBindings.isEmpty {
                Text("Keine Sprach-Zuweisungen konfiguriert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(spacing: 6) {
                    ForEach($coordinator.languageBindings) { $binding in
                        LanguageBindingRow(binding: $binding) {
                            coordinator.languageBindings.removeAll { $0.id == binding.id }
                        }
                    }
                }
            }

            HStack {
                Button("Sprache hinzufügen") {
                    let used = Set(coordinator.languageBindings.map(\.fKey))
                    let nextF = (1...12).first { !used.contains($0) } ?? 1
                    coordinator.languageBindings.append(
                        LanguageBinding(isoCode: "es", fKey: nextF)
                    )
                }
                .disabled(coordinator.languageBindings.count >= 12)
                Spacer()
            }

            if hasDuplicateFKeys {
                Label("Zwei Einträge teilen sich dieselbe F-Taste — nur der erste greift.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    private var hasDuplicateFKeys: Bool {
        let fkeys = coordinator.languageBindings.map(\.fKey)
        return Set(fkeys).count != fkeys.count
    }
}

private struct LanguageBindingRow: View {
    @Binding var binding: LanguageBinding
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("", selection: $binding.isoCode) {
                ForEach(LanguageCatalog.supported, id: \.iso) { lang in
                    Text(lang.name).tag(lang.iso)
                }
            }
            .labelsHidden()
            .frame(minWidth: 200)

            Spacer(minLength: 8)

            Text("F-Taste")
                .foregroundStyle(.secondary)
                .font(.caption)
            Picker("", selection: $binding.fKey) {
                ForEach(1...12, id: \.self) { n in
                    Text("F\(n)").tag(n)
                }
            }
            .labelsHidden()
            .frame(width: 70)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }
}

private struct ModeCard: View {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let accent: Color
    @Binding var config: HotkeyConfig

    var body: some View {
        Card(title: title, subtitle: subtitle, icon: icon, accent: accent) {
            HStack(alignment: .center, spacing: 16) {
                // Big symbol capsule
                Text(config.isValid ? config.displaySymbols : "—")
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .frame(minWidth: 110, minHeight: 60)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accent.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(accent.opacity(0.3), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 18) {
                Toggle("⌃ Control", isOn: $config.control)
                Toggle("⌥ Option", isOn: $config.option)
                Toggle("⇧ Shift", isOn: $config.shift)
                Toggle("⌘ Command", isOn: $config.command)
            }
            .toggleStyle(.checkbox)
        }
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: TimeInterval
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value * scale)) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - Bedienungshilfen

/// Systemfreigaben-Tab. Bündelt alle einmalig nötigen Setup-Schritte:
/// macOS-Permissions (Bedienungshilfen, Eingabeüberwachung) plus die
/// Konfigurations-Kacheln (Transkriptions-Modus, OpenAI-Key, Autostart,
/// Verhalten, Verlauf-Aufzeichnung). Ziel: Ein einziger Tab beantwortet
/// die Frage „Was muss ich an meinem Rechner einrichten, damit ALVA
/// volle Funktionalität bietet?"
private struct SystemTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showAccessibilityHelp: Bool = false
    @State private var inputMonitoringTick: Int = 0

    var body: some View {
        let accessibilityTrusted = coordinator.accessibilityTrusted
        let inputMonitoringTrusted = coordinator.inputMonitoringTrusted
        let anyMissing = !accessibilityTrusted || !inputMonitoringTrusted

        ScrollView {
            VStack(spacing: 14) {
                // Setup-Erklärtext
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("Damit ALVA-TEXT alle Funktionen nutzen kann, sind einige systemseitige Freigaben und Konfigurationen nötig. Sie werden einmal eingerichtet und gelten dauerhaft.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)

                if anyMissing {
                    PermissionIntroBanner(
                        title: "Wir brauchen deine Mithilfe",
                        text: "Aktiviere die noch fehlenden Freigaben unten. Bei der Eingabeüberwachung kann macOS nach dem Aktivieren um einen Neustart der App bitten — das ist normal."
                    )
                }

                // 1) Eingabeüberwachung (für F-Tasten + Rückwärtsübersetzung)
                InputMonitoringCard(tick: $inputMonitoringTick)

                // 2) Bedienungshilfen (für Auto-Einfügen)
                PermissionCard(
                    title: "Bedienungshilfen",
                    subtitle: "Ermöglicht automatisches Einfügen",
                    trusted: accessibilityTrusted,
                    trustedLabel: "Auto-Einfügen ist aktiv.",
                    missingLabel: "Auto-Einfügen deaktiviert — Texte landen nur in der Zwischenablage.",
                    primaryAction: {
                        // Pending-Flag setzen — falls die App nach Permission
                        // erneut starten muss, kommt der User zurück in diesen
                        // Pane (Bedienungshilfen braucht den Restart selten,
                        // aber für Konsistenz machen wir es einheitlich).
                        UserDefaults.standard.set("accessibility",
                                                  forKey: AppDelegate.pendingPermissionKey)
                        coordinator.requestAccessibilityPrompt()
                        coordinator.openAccessibilitySettings()
                    },
                    primaryLabel: "Jetzt freigeben",
                    secondaryAction: accessibilityTrusted ? { coordinator.runPasteSelfTest() } : nil,
                    secondaryLabel: "Testeinfügung",
                    helpExpanded: $showAccessibilityHelp,
                    helpText: "ALVA simuliert beim automatischen Einfügen einen ⌘V-Tastendruck über die Accessibility-API. macOS erlaubt das nur Apps, die ausdrücklich unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen freigegeben sind. Nach Xcode-Rebuilds ändert sich die App-Signatur; dann den alten Eintrag mit „−\" entfernen und die neu gebaute App erneut hinzufügen."
                )

                // 3) OpenAI-Schlüssel
                Card(title: "OpenAI-Schlüssel (optional)",
                     subtitle: "Nur für Höflich, Nachricht und Sprach-Übersetzung",
                     icon: "key.fill",
                     accent: .blue) {
                    SecureField("sk-… (leer lassen für reinen Lokalbetrieb)", text: $coordinator.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Ohne Schlüssel funktioniert der Standard-Modus (reines Transkript) vollständig lokal. Für Umformulierungen und Übersetzungen wird ein Schlüssel von platform.openai.com benötigt. Der Schlüssel wird lokal im macOS-Schlüsselbund gespeichert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 4) Beim Start (Autostart)
                Card(title: "Beim Start", subtitle: "Autostart und Einrichtung", icon: "power.circle.fill", accent: .teal) {
                    Toggle("ALVA-TEXT bei Login automatisch starten", isOn: Binding(
                        get: { coordinator.isLaunchAtLoginEnabled },
                        set: { coordinator.setLaunchAtLogin($0) }
                    ))
                    HStack {
                        Button("Einrichtung erneut starten …") {
                            coordinator.showOnboardingWindow()
                        }
                        Spacer()
                    }
                }

                // 5) Verhalten
                Card(title: "Verhalten", subtitle: "Standardaktionen nach der Transkription", icon: "gearshape.2.fill", accent: .gray) {
                    Toggle("Nach Transkription automatisch einfügen", isOn: $coordinator.autoPaste)
                    Toggle("Höfliche Umformulierung im Höflich-Modus", isOn: $coordinator.rewriteEnabled)
                }
            }
            .padding(2)
        }
    }
}

/// Friendly banner shown above a permission card when the user still has
/// work to do. Avoids the "looks broken" feeling by naming the need as
/// a cooperative task ("Wir brauchen deine Mithilfe") rather than an
/// error.
private struct PermissionIntroBanner: View {
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Uniform permission card with auto-updating status, single primary
/// button and an optional expandable help section. Auto-detects
/// "stale entry" case: if the user clicked the primary button and the
/// status still hasn't flipped after 4s, show an extra hint that the
/// OS has probably kept an older signature and the entry needs to be
/// removed and re-added.
private struct PermissionCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let title: String
    let subtitle: String
    let trusted: Bool
    let trustedLabel: String
    let missingLabel: String
    let primaryAction: () -> Void
    let primaryLabel: String
    let secondaryAction: (() -> Void)?
    let secondaryLabel: String
    @Binding var helpExpanded: Bool
    let helpText: String

    @State private var primaryClickedAt: Date?
    @State private var staleTicks: Int = 0   // forces re-render every second

    /// True once we're confident the user granted permission via the UI
    /// but the ALVA entry in System Settings points to an older binary
    /// signature and the OS is still denying.
    private var isStale: Bool {
        guard let clicked = primaryClickedAt, !trusted else { return false }
        return Date().timeIntervalSince(clicked) > 4
    }

    var body: some View {
        Card(title: title, subtitle: subtitle,
             icon: trusted ? "checkmark.seal.fill" : "exclamationmark.shield.fill",
             accent: trusted ? .green : .orange) {

            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(trusted ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trusted ? "Freigegeben" : "Freigabe erforderlich")
                        .fontWeight(.semibold)
                    Text(trusted ? trustedLabel : missingLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if isStale {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Toggle ist gesetzt, wird aber nicht erkannt?")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Möglich 1: Der Eintrag stammt von einer älteren App-Version — einmal per „−\" entfernen und die aktuelle App per „+\" wieder hinzufügen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Möglich 2: macOS hat den frischen Berechtigungs-Status noch nicht zur App durchgereicht — einmal ALVA-TEXT neu starten.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        Button("ALVA-TEXT neu starten") {
                            coordinator.restartApp()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }

            HStack {
                if !trusted {
                    Button(primaryLabel) {
                        primaryClickedAt = Date()
                        primaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let action = secondaryAction {
                    Button(secondaryLabel, action: action)
                        .buttonStyle(.bordered)
                }
                Spacer()
            }

            DisclosureGroup(isExpanded: $helpExpanded) {
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } label: {
                Label("Warum wird das benötigt?", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            staleTicks &+= 1
        }
        .onChange(of: trusted) { _, newValue in
            if newValue {
                primaryClickedAt = nil
            }
        }
    }
}

// MARK: - Status

private struct StatusTab: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "Aktuell", icon: "dot.radiowaves.left.and.right", accent: .accentColor) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(germanStatus(coordinator.status))
                            .foregroundStyle(.secondary)
                    }
                }

                CostCard()

                if let errorMessage = coordinator.lastErrorMessage {
                    Card(title: "Letzter Fehler",
                         subtitle: coordinator.lastErrorDate.map { $0.formatted(date: .omitted, time: .standard) } ?? "",
                         icon: "exclamationmark.triangle.fill",
                         accent: .orange) {
                        Text(errorMessage)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Meldung verwerfen") {
                                coordinator.clearError()
                            }
                            Spacer()
                        }
                    }
                }

                Card(title: "Letztes Transkript", icon: "doc.plaintext", accent: .blue) {
                    TextEditor(text: $coordinator.lastTranscript)
                        .font(.body.monospaced())
                        .frame(minHeight: 90)
                }

                Card(title: "Letzte Umformulierung", icon: "text.badge.checkmark", accent: .green) {
                    TextEditor(text: $coordinator.lastRewrittenText)
                        .font(.body.monospaced())
                        .frame(minHeight: 90)
                }
            }
            .padding(2)
        }
    }

    private func germanStatus(_ status: AppStatus) -> String {
        switch status {
        case .idle: return "bereit"
        case .recording: return "Aufnahme läuft"
        case .transcribing: return "transkribiere …"
        case .rewriting: return "formuliere um …"
        case .translating: return "übersetze …"
        case .pasted: return "eingefügt"
        case .copied: return "in Zwischenablage kopiert"
        case .needsAccessibility: return "Bedienungshilfen fehlen"
        case .error: return "Fehler"
        }
    }
}

// MARK: - Cost tracking card

private struct CostCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showRecent: Bool = false

    var body: some View {
        Card(title: "OpenAI-API-Kosten",
             subtitle: "Nur Cloud-Aufrufe — Lokalbetrieb ist gratis",
             icon: "dollarsign.circle.fill",
             accent: .yellow) {

            HStack(spacing: 18) {
                costColumn("Heute", amount: coordinator.costToday, tint: .blue)
                Divider().frame(height: 40)
                costColumn("Diesen Monat", amount: coordinator.costThisMonth, tint: .green)
                Divider().frame(height: 40)
                costColumn("Gesamt", amount: coordinator.costAllTime, tint: .gray)
                Spacer()
            }

            DisclosureGroup(isExpanded: $showRecent) {
                if coordinator.costEntries.isEmpty {
                    Text("Noch keine Einträge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 2) {
                        ForEach(coordinator.costEntries.prefix(10)) { entry in
                            HStack(spacing: 8) {
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(entry.kind.germanLabel)
                                    .font(.caption2)
                                    .foregroundStyle(colorFor(entry.kind))
                                    .frame(width: 85, alignment: .leading)
                                Text(entry.usageDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatUSD(entry.costUSD))
                                    .font(.caption2.monospacedDigit())
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(.top, 6)
                }
                HStack {
                    Button("Alle löschen") {
                        coordinator.clearCostEntries()
                    }
                    .foregroundStyle(.red)
                    .disabled(coordinator.costEntries.isEmpty)
                    Spacer()
                    Text("\(coordinator.costEntries.count) Einträge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Label("Letzte Einträge anzeigen", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func costColumn(_ title: String, amount: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatUSD(amount))
                .font(.title3.monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private func formatUSD(_ amount: Double) -> String {
        // Cent-precision below 1$, then 2 decimals. Always in USD.
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = amount < 0.01 ? 4 : 2
        formatter.maximumFractionDigits = amount < 0.01 ? 4 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func colorFor(_ kind: CostEntry.Kind) -> Color {
        switch kind {
        case .transcribe: return .blue
        case .rewrite:    return .green
        case .translate:  return .orange
        }
    }
}

extension CostEntry.Kind {
    var germanLabel: String {
        switch self {
        case .transcribe: return "Transkribe"
        case .rewrite:    return "Umformulie"
        case .translate:  return "Übersetzung"
        }
    }
}

extension CostEntry {
    var usageDescription: String {
        if let audio = audioSeconds {
            return String(format: "%.1fs Audio", audio)
        }
        if let p = promptTokens, let c = completionTokens {
            return "\(p + c) Tokens"
        }
        return ""
    }
}

// MARK: - Reverse Translate Popup

struct ReverseTranslatePopup: View {
    let originalChunks: [LanguageChunk]
    let translated: String
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(originalChunks) { chunk in
                    LanguageBlock(
                        label: chunk.displayName,
                        text: chunk.text,
                        accent: .blue
                    )
                }

                if !originalChunks.isEmpty {
                    Divider().padding(.vertical, 1)
                }

                LanguageBlock(
                    label: "Deutsch",
                    text: translated,
                    accent: .green
                )
            }
            .padding(14)
        }
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 760,
               minHeight: 220, idealHeight: 360, maxHeight: 680)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        // Dedicated Escape-to-close binding. `.onExitCommand` only fires
        // when the SwiftUI hierarchy owns first responder, which isn't
        // reliable inside a borderless/fullSizeContentView NSWindow. A
        // zero-sized Button with an explicit keyboard shortcut is always
        // active in the window's responder chain.
        .background(
            Button(action: onClose) { EmptyView() }
                .frame(width: 0, height: 0)
                .opacity(0)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityHidden(true)
        )
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var step: Int = 0
    @State private var accessibilityTick: Int = 0
    @State private var inputMonitoringTick: Int = 0

    let onFinish: () -> Void

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ALVA-TEXT")
                    .font(.headline)
                Spacer()
                Text("Schritt \(step + 1) von \(totalSteps)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(16)

            Divider()

            // Page content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: modePage
                    case 1: welcomePage
                    case 2: apiKeyPage
                    case 3: accessibilityPage
                    case 4: inputMonitoringPage
                    default: EmptyView()
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer navigation
            HStack {
                if step > 0 {
                    Button("Zurück") { step -= 1 }
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button(step == 0 ? "Los geht's" : "Weiter") {
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                } else {
                    Button("Fertig") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 500)
    }

    private var canAdvance: Bool {
        // Schritt 0 ist die Modus-Wahl (Standard vs. Pro). Erst weitergehen,
        // wenn der User sich entschieden hat — sonst ist v2.2 nicht initialisiert.
        // Die übrigen Schritte sind frei (API-Key bleibt optional).
        if step == 0 {
            return coordinator.proMode != .unset
        }
        return true
    }

    // Pages

    @ViewBuilder
    private var modePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wie magst du es lieber?")
                .font(.title2)
                .bold()
            Text("ALVA-TEXT gibt es in zwei Geschmäckern. Beide kostenfrei. Du kannst jederzeit umschalten — die Frage ist nur, womit du startest.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                modeCard(
                    title: "Standard",
                    subtitle: "Schlank · sofort einsatzbereit",
                    bullets: [
                        "Sauber diktieren in jede App",
                        "Lokal über Whisper, kein Account nötig",
                        "Adaptive-Mode mit nüchternem Default",
                        "Mehrsprachigkeit über F-Tasten"
                    ],
                    selected: coordinator.proMode == .standard,
                    action: { coordinator.proMode = .standard }
                )

                modeCard(
                    title: "Pro",
                    subtitle: "Volle Personalisierung",
                    bullets: [
                        "Eigene Identität, Stil, Sign-offs",
                        "Wortschatz & Eigennamen",
                        "Mehrere Profile in der Menüleiste",
                        "Adaptive Learning, Custom Modes, Prompt-Optimizer"
                    ],
                    selected: coordinator.proMode == .pro,
                    action: { coordinator.proMode = .pro }
                )
            }
            .padding(.top, 4)

            if coordinator.proMode == .unset {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left.fill")
                    Text("Wähle eine Variante, dann geht's weiter.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Gewählt: \(coordinator.proMode.germanShortLabel) — du kannst das später jederzeit ändern.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
    }

    /// Eine der zwei Mode-Kacheln auf der Mode-Page.
    @ViewBuilder
    private func modeCard(
        title: String,
        subtitle: String,
        bullets: [String],
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.title3)
                        .bold()
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                    }
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(line)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.18),
                            lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Willkommen bei ALVA-TEXT")
                .font(.title2)
                .bold()
            Text("ALVA funktioniert direkt nach der Installation — mit lokaler Transkription, ohne Internet, ohne API-Schlüssel. Optional kannst du später OpenAI einschalten, um Umformulierungen und Übersetzungen zu nutzen.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                bullet(number: 1, text: "OpenAI-Schlüssel (optional) — nur für Höflich, Nachricht und Sprach-Übersetzung.")
                bullet(number: 2, text: "Bedienungshilfen freigeben — für das automatische Einfügen.")
                bullet(number: 3, text: "Eingabeüberwachung freigeben — für Sprach-F-Tasten und Rückwärtsübersetzung.")
            }
            .padding(.top, 4)

            Text("Sofort nutzbar: Control gedrückt halten und diktieren → sauberes Transkript auf Deutsch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var apiKeyPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenAI-Schlüssel")
                .font(.title2)
                .bold()
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("Optional — du kannst diesen Schritt überspringen.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("Der Standard-Modus (reines Transkript auf Deutsch) funktioniert lokal und benötigt keinen Schlüssel. Für folgende Funktionen wird ein OpenAI-Schlüssel benötigt:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                bullet(number: 1, text: "Höflich-Modus (umformulierte E-Mails)")
                bullet(number: 2, text: "Nachricht-Modus (adaptiver Chat-Stil)")
                bullet(number: 3, text: "Sprach-Übersetzung via F-Tasten (EN/FR/IT/…)")
                bullet(number: 4, text: "Rückwärtsübersetzung fremdsprachiger Texte")
            }
            .padding(.vertical, 2)

            Text("Den Schlüssel gibt es auf platform.openai.com. Er wird ausschließlich im macOS-Schlüsselbund gespeichert.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            SecureField("sk-… (leer lassen für Lokalbetrieb)", text: $coordinator.apiKey)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)

            if coordinator.apiKey.isEmpty {
                Label("Kein Schlüssel gespeichert — nur Standard-Modus aktiv.",
                      systemImage: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            } else {
                Label("Schlüssel gespeichert — alle Features freigeschaltet.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var accessibilityPage: some View {
        let trusted = coordinator.isAccessibilityTrusted()
        VStack(alignment: .leading, spacing: 12) {
            Text("Bedienungshilfen")
                .font(.title2)
                .bold()
            Text("Für das automatische Einfügen in die fokussierte App simuliert ALVA ⌘V. Das erfordert die Berechtigung Bedienungshilfen.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(trusted ? .green : .orange)
                Text(trusted ? "Bedienungshilfen sind freigegeben." : "Bedienungshilfen fehlen.")
                    .fontWeight(.semibold)
            }
            .id(accessibilityTick)

            if !trusted {
                permissionSteps(steps: [
                    "Auf „Erlaubnis erteilen\" klicken — Systemeinstellungen öffnen sich bei „Bedienungshilfen\".",
                    "In der Liste ALVA-TEXT finden und den Schalter rechts aktivieren.",
                    "Falls ALVA-TEXT nicht in der Liste steht: unten auf „+\" klicken und im Finder ALVA-TEXT.app auswählen.",
                    "Zurück zu diesem Fenster → „Erneut prüfen\" → Ampel wird grün."
                ])

                tccCacheRestartHint()
            }

            HStack {
                Button(trusted ? "Systemeinstellungen öffnen" : "Erlaubnis erteilen") {
                    if !trusted {
                        coordinator.requestAccessibilityPrompt()
                    }
                    coordinator.openAccessibilitySettings()
                    accessibilityTick &+= 1
                }
                .buttonStyle(.borderedProminent)
                Button("Erneut prüfen") {
                    accessibilityTick &+= 1
                }
            }
            .buttonStyle(.bordered)
        }
    }

    /// Erklär-Block, der bei TCC-Permissions-Pages erscheint, falls die
    /// Permission noch nicht erkannt wurde. macOS' `AXIsProcessTrusted()`
    /// (und analog der Input-Monitoring-Check) cached den Trust-Status pro
    /// Prozess — selbst wenn der User in den Systemeinstellungen den Toggle
    /// umlegt, sieht der laufende ALVA-Prozess das oft nicht zuverlässig.
    /// Workaround: einmal die App neu starten.
    @ViewBuilder
    private func tccCacheRestartHint() -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("Toggle ist gesetzt, aber wird nicht erkannt?")
                    .font(.caption.weight(.semibold))
                Text("macOS aktualisiert den Berechtigungs-Status manchmal erst nach einem App-Neustart. Klick einmal auf „ALVA-TEXT neu starten\" — danach erkennt die App die Berechtigung sofort.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("ALVA-TEXT neu starten") {
                    coordinator.restartApp()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var inputMonitoringPage: some View {
        let trusted = coordinator.isInputMonitoringTrusted()
        VStack(alignment: .leading, spacing: 12) {
            Text("Eingabeüberwachung")
                .font(.title2)
                .bold()
            Text("Für Sprach-F-Tasten während der Aufnahme und für die Rückwärtsübersetzung muss ALVA Tastaturereignisse anderer Apps mitlesen. Das erfordert die Berechtigung Eingabeüberwachung.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(trusted ? .green : .orange)
                Text(trusted ? "Eingabeüberwachung ist freigegeben." : "Eingabeüberwachung fehlt.")
                    .fontWeight(.semibold)
            }
            .id(inputMonitoringTick)

            if !trusted {
                permissionSteps(steps: [
                    "Auf „Systemeinstellungen öffnen\" klicken — landet bei „Eingabeüberwachung\".",
                    "Schalter rechts neben ALVA-TEXT aktivieren (sollte dort schon mit Toggle gelistet sein).",
                    "Falls macOS „Beenden & erneut öffnen\" anbietet → bestätigen.",
                    "Zurück zu diesem Fenster → „Erneut prüfen\" → Ampel wird grün."
                ])

                tccCacheRestartHint()
            }

            HStack {
                Button("Systemeinstellungen öffnen") {
                    coordinator.openInputMonitoringSettings()
                }
                .buttonStyle(.borderedProminent)
                Button("Erneut prüfen") {
                    inputMonitoringTick &+= 1
                }
            }
            .buttonStyle(.bordered)

            if trusted {
                // macOS-Inkonsistenz: IOHIDCheckAccess() liefert "granted",
                // aber die UI-Liste in Systemeinstellungen → Eingabe-
                // überwachung kann trotzdem leer sein. Beide lesen aus
                // der gleichen TCC-DB, aber die UI-Liste filtert manchmal
                // alte/migrierte Einträge raus. Funktional ist das egal —
                // wenn die App "freigegeben" zeigt, klappt das Mitlesen.
                Label("macOS zeigt Eingabeüberwachung-Apps in der Systemeinstellungs-Liste manchmal nicht an, obwohl die Berechtigung erteilt ist. Solange ALVA „Eingabeüberwachung ist freigegeben\" anzeigt, funktioniert alles.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                Text("Hinweis: Nach dem Aktivieren in den Systemeinstellungen muss ALVA-TEXT einmal beendet und neu gestartet werden. Bei Dev-Builds (aus Xcode) kann es nötig sein, einen bereits vorhandenen alten ALVA-TEXT-Eintrag per „−\" zu entfernen und neu hinzuzufügen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func permissionSteps(steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("So geht's:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "\(idx + 1).circle.fill")
                        .foregroundStyle(.blue)
                    Text(text)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    private func bullet(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.blue)
            Text(text)
        }
    }
}

// MARK: - History window

struct HistoryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var search: String = ""
    @State private var selectedID: UUID?

    var body: some View {
        HSplitView {
            // Left: list of entries
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Suchen", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                if filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Noch keine Einträge")
                            .foregroundStyle(.secondary)
                        if !coordinator.historyEnabled {
                            Text("Der Verlauf ist aktuell deaktiviert.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(selection: $selectedID) {
                        ForEach(filteredEntries) { entry in
                            HistoryRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 260)

            // Right: detail
            if let entry = filteredEntries.first(where: { $0.id == selectedID }) {
                HistoryDetailView(entry: entry)
            } else {
                VStack {
                    Spacer()
                    Text("Wähle links einen Eintrag aus.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private var filteredEntries: [TranscriptEntry] {
        guard !search.isEmpty else { return coordinator.history }
        let needle = search.lowercased()
        return coordinator.history.filter {
            $0.original.lowercased().contains(needle)
                || $0.final.lowercased().contains(needle)
        }
    }
}

private struct HistoryRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(modeLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(modeColor)
                if let iso = entry.targetLanguageISO {
                    Text(" → \(LanguageCatalog.germanName(for: iso))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.date.formatted(.dateTime.hour().minute().day().month()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.final)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    private var modeLabel: String {
        entry.mode?.germanLabel ?? "?"
    }

    private var modeColor: Color {
        switch entry.mode {
        case .standard: return .blue
        case .polite:   return .green
        case .message:  return .orange
        default:        return .secondary
        }
    }
}

private struct HistoryDetailView: View {
    let entry: TranscriptEntry
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var didCopy: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    Text(entry.mode?.germanLabel ?? "Unbekannt")
                        .font(.headline)
                    if let iso = entry.targetLanguageISO {
                        Text("→ \(LanguageCatalog.germanName(for: iso))")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.date.formatted(.dateTime.day().month().year().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Original
                labeledBox(label: "Transkript", text: entry.original, accent: .gray)

                // Final
                labeledBox(label: "Ergebnis (eingefügt)", text: entry.final, accent: .blue)

                // Actions
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.final, forType: .string)
                        didCopy = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            didCopy = false
                        }
                    } label: {
                        Label(didCopy ? "Kopiert ✓" : "Ergebnis in Zwischenablage",
                              systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(didCopy ? .green : .blue)

                    Button("Eintrag löschen") {
                        coordinator.deleteHistoryEntry(entry)
                    }
                    .foregroundStyle(.red)

                    Spacer()
                }
            }
            .padding(18)
        }
    }

    private func labeledBox(label: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
        }
    }
}

/// A labelled text box with a copy icon in the top-right corner.
private struct LanguageBlock: View {
    let label: String
    let text: String
    let accent: Color

    @State private var didCopy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topTrailing) {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .padding(.trailing, 34)
                }
                .frame(minHeight: 60, maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accent.opacity(0.3), lineWidth: 1)
                )

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(didCopy ? Color.green : Color.secondary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                        )
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(didCopy ? "Kopiert" : "Text kopieren")
            }
        }
    }
}

// MARK: - Account

/// Zeigt den AdLuna-Lizenzstatus, ermöglicht Aktivierung/Abmeldung und
/// einen manuellen Refresh. Trial-Countdown wird live aus `trialExpiresAt`
/// gerechnet. Der Activation-Flow öffnet sich als Sheet.
private struct AccountTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var license = LicenseState.shared
    @State private var showActivation = false
    @State private var isRefreshing = false
    @State private var feedback: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isActivated && coordinator.hasIncompletePermissions {
                    nextStepCard
                }
                statusCard
                trialCard
                actionsCard
                avatarCard
                infoCard
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showActivation) {
            ActivationView(state: license)
        }
        .onChange(of: license.phase) { oldPhase, newPhase in
            // Direkt nach erfolgreicher Aktivierung: Wenn noch Permissions
            // fehlen, das Onboarding-Window zeigen — es führt den User
            // aktiv durch Bedienungshilfen + Eingabeüberwachung. Ohne
            // diesen Trigger landet der User im Account-Tab mit „Beta
            // aktiv" und merkt erst beim ersten Hotkey-Versuch, dass
            // noch Setup nötig ist.
            //
            // Trigger nur beim echten Wechsel non-active → active, nicht
            // bei active-internen Updates (z.B. periodischer Refresh des
            // Status-Strings, wenn schon aktiv).
            let wasActive: Bool = { if case .active = oldPhase { return true } else { return false } }()
            let isActive: Bool = { if case .active = newPhase { return true } else { return false } }()
            if !wasActive && isActive && coordinator.hasIncompletePermissions {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    coordinator.showOnboardingWindow()
                }
            }
        }
    }

    /// Auffälliger Block im Account-Tab, wenn die App aktiviert ist, aber
    /// Bedienungshilfen oder Eingabeüberwachung noch fehlen. Backup falls
    /// der User das Onboarding-Window geschlossen hat oder Permissions
    /// später durch macOS-Updates / `tccutil reset` verloren gegangen sind.
    private var nextStepCard: some View {
        Card(title: "Nächster Schritt: Berechtigungen erteilen",
             subtitle: "Setup ist noch nicht vollständig",
             icon: "exclamationmark.shield.fill",
             accent: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Du bist aktiviert — aber damit ALVA Auto-Einfügen, F-Tasten-Sprachwahl und Rückwärtsübersetzung tatsächlich nutzen kann, müssen noch zwei macOS-Berechtigungen freigegeben werden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    permissionStatusRow(label: "Bedienungshilfen",
                                        granted: coordinator.accessibilityTrusted)
                    permissionStatusRow(label: "Eingabeüberwachung",
                                        granted: coordinator.inputMonitoringTrusted)
                }

                HStack {
                    Button {
                        coordinator.settingsRequestedTab = "system"
                    } label: {
                        Label("Zu Systemfreigaben", systemImage: "shield.lefthalf.filled")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Einrichtungs-Assistent öffnen") {
                        coordinator.showOnboardingWindow()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func permissionStatusRow(label: String, granted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(granted ? .secondary : .primary)
        }
    }

    private var isActivated: Bool {
        if case .active = license.phase { return true }
        return false
    }

    // MARK: Cards

    private var statusCard: some View {
        Card(title: "Lizenzstatus",
             subtitle: subtitle,
             icon: iconName,
             accent: accentColor) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusHeadline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accentColor)
                Spacer()
                if case .active(_, let tier, _) = license.phase {
                    tierBadge(tier: tier)
                }
            }

            if let msg = currentMessage, !msg.isEmpty {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let fb = feedback {
                Label(fb, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var trialCard: some View {
        if let expires = license.trialExpiresAt, expires > .init() {
            Card(title: "Testzeitraum", icon: "hourglass", accent: .blue) {
                HStack {
                    Text("Läuft ab")
                    Spacer()
                    Text(expires, format: .dateTime.day().month().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Verbleibend")
                    Spacer()
                    Text(remainingTrial(until: expires))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsCard: some View {
        Card(title: "Aktionen", icon: "bolt.fill", accent: .orange) {
            HStack(spacing: 10) {
                if LicenseClient.isActivated {
                    Button {
                        Task { await doRefresh() }
                    } label: {
                        Label(isRefreshing ? "Prüfe…" : "Jetzt prüfen",
                              systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)

                    Button(role: .destructive) {
                        license.signOut()
                        feedback = "Abgemeldet. Device-Token lokal gelöscht."
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        showActivation = true
                    } label: {
                        Label("Aktivieren", systemImage: "key.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Spacer()
            }
        }
    }

    private var infoCard: some View {
        Card(title: "Technische Details", icon: "info.circle", accent: .gray) {
            VStack(alignment: .leading, spacing: 6) {
                detailRow("API-Host", LicenseClient.baseURL.host ?? "—")
                detailRow("Produkt", LicenseClient.productID)
                detailRow("Gerätename", LicenseClient.deviceName)
                detailRow("Gerät-UUID", String(LicenseClient.deviceUUID().prefix(8)) + "…")
                if let last = license.lastCheck {
                    detailRow("Letzter Check", last.formatted(date: .abbreviated, time: .shortened))
                }
                detailRow("App-Version", LicenseClient.appVersion)
            }
        }
    }

    @ViewBuilder private var avatarCard: some View {
        if license.currentEmail != nil {
            Card(title: "Profilbild", icon: "person.crop.square", accent: .purple) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dein Avatar im Menü kommt von **Gravatar** — einem weltweiten, kostenlosen Avatar-Dienst, der dein Bild mit deiner E-Mail verknüpft. Aktuell wird ein automatisch generiertes Muster (Identicon) angezeigt, weil für diese E-Mail kein Gravatar hinterlegt ist.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Eigenes Bild bei gravatar.com einrichten",
                         destination: URL(string: "https://gravatar.com")!)
                        .font(.callout)
                }
            }
        }
    }

    // MARK: Helpers

    private var statusHeadline: String {
        switch license.phase {
        case .loading:         return "Wird geprüft…"
        case .needsActivation: return "Nicht aktiviert"
        case .active(let status, _, _):
            // Backend liefert technische Status-Strings ("beta", "trial",
            // "active"). Im UI nutzen wir neutralere Begriffe — "Beta"
            // klingt nach Entwicklungsphase, was ALVA-TEXT inhaltlich
            // schon längst verlassen hat.
            switch status {
            case "beta":   return "Aktiv"
            case "trial":  return "Testzeitraum aktiv"
            case "active": return "Lizenz aktiv"
            default:       return status.capitalized
            }
        case .expired:         return "Testzeitraum abgelaufen"
        case .revoked:         return "Zugang widerrufen"
        case .error(let msg):  return "Fehler: \(msg)"
        }
    }

    private var subtitle: String {
        switch license.phase {
        case .loading:         return "Status wird geladen"
        case .needsActivation: return "Mit deiner E-Mail freischalten"
        case .active(_, _, _): return "AdLuna Platform"
        case .expired:         return "Bitte Lizenz erwerben"
        case .revoked:         return "Support kontaktieren"
        case .error:           return "Verbindung prüfen"
        }
    }

    private var iconName: String {
        switch license.phase {
        case .active:          return "checkmark.seal.fill"
        case .loading:         return "clock.arrow.circlepath"
        case .needsActivation: return "key"
        case .expired:         return "exclamationmark.triangle.fill"
        case .revoked:         return "xmark.seal.fill"
        case .error:           return "wifi.slash"
        }
    }

    private var accentColor: Color {
        switch license.phase {
        case .active(_, .full, _), .active(_, .paid, _): return .green
        case .active(_, .limited, _):                    return .yellow
        case .loading:                                   return .blue
        case .needsActivation:                           return .accentColor
        case .expired, .error:                           return .orange
        case .revoked:                                   return .red
        }
    }

    private var currentMessage: String? {
        if case .active(_, _, let msg) = license.phase { return msg }
        if case .expired(let msg) = license.phase { return msg }
        if case .revoked(let msg) = license.phase { return msg }
        return nil
    }

    @ViewBuilder private func tierBadge(tier: LicenseState.Tier) -> some View {
        let (label, color): (String, Color) = {
            switch tier {
            case .full:    return ("Voller Funktionsumfang", .green)
            case .paid:    return ("Bezahlt", .green)
            case .limited: return ("Eingeschränkt", .yellow)
            }
        }()
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color.opacity(0.18))
            )
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
            .foregroundStyle(color)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
        }
    }

    private func remainingTrial(until end: Date) -> String {
        let s = Int(end.timeIntervalSinceNow)
        guard s > 0 else { return "abgelaufen" }
        let days = s / 86400
        let hours = (s % 86400) / 3600
        if days > 0 { return "\(days) Tage, \(hours) Std." }
        if hours > 0 { return "\(hours) Std." }
        return "< 1 Std."
    }

    private func doRefresh() async {
        isRefreshing = true
        feedback = nil
        await license.refresh()
        isRefreshing = false
        if case .error(let msg) = license.phase {
            feedback = "Check fehlgeschlagen: \(msg)"
        } else {
            feedback = "Status aktualisiert."
        }
    }
}

// MARK: - Verlauf

/// Verlauf-Tab. Zeigt den Master-Toggle für die Verlaufs-Aufzeichnung,
/// gefolgt vom letzten Transkript, der letzten Umformulierung und einem
/// Button zum vollständigen Verlauf-Fenster. Wird in v2.1.2 schrittweise
/// gefüllt — der Inhalt wandert aus StatusTab + GeneralTab hierher.
private struct HistoryTab: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Master-Toggle ganz oben — ein/aus für die gesamte
                // Protokollierung. Wenn aus, werden keine neuen Einträge
                // angelegt (alte bleiben aber bestehen, bis der Nutzer
                // sie löscht).
                Card(title: "Aufzeichnung",
                     subtitle: "Letzte \(AppCoordinator.maxHistoryEntries) Einträge",
                     icon: "clock.fill",
                     accent: .indigo) {
                    Toggle("Transkripte und Umformulierungen aufzeichnen",
                           isOn: $coordinator.historyEnabled)
                    HStack {
                        Button("Vollständigen Verlauf öffnen …") {
                            coordinator.openHistoryWindow()
                        }
                        Button("Verlauf komplett löschen") {
                            coordinator.clearHistory()
                        }
                        .foregroundStyle(.red)
                        .disabled(coordinator.history.isEmpty)
                        Spacer()
                        Text("\(coordinator.history.count) Einträge")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                // Letztes Transkript
                Card(title: "Letztes Transkript",
                     icon: "doc.plaintext",
                     accent: .blue) {
                    if !coordinator.lastTranscript.isEmpty {
                        Text(coordinator.lastTranscript)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Noch kein Transkript in dieser Sitzung.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Letzte Umformulierung
                Card(title: "Letzte Umformulierung",
                     icon: "text.badge.checkmark",
                     accent: .green) {
                    if !coordinator.lastRewrittenText.isEmpty {
                        Text(coordinator.lastRewrittenText)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Noch keine Umformulierung in dieser Sitzung.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(2)
        }
    }
}

// MARK: - AccountStatusHeader (oben im Allgemein-Tab)

/// Zeigt oben im Allgemein-Tab den Lizenz-Status in kompakter Form.
///
/// Bei NICHT aktiviert: grosser Call-to-Action mit „Aktivieren"-Button,
/// der direkt zum Account-Tab springt.
/// Bei aktiviert: schmale Info-Zeile mit Avatar, E-Mail und Status, plus
/// „Konto verwalten"-Link.
///
/// Zweck: Der Nutzer soll den Aktivierungs-Status sofort sehen, ohne erst
/// durch die Tabs navigieren zu muessen. Das war eine der wichtigsten
/// UX-Beschwerden des ersten Releases.
private struct AccountStatusHeader: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var license = LicenseState.shared
    @State private var showActivation = false

    var body: some View {
        switch license.phase {
        case .needsActivation:
            notActivatedCard
        case .active(let status, let tier, _):
            activatedRow(status: status, tier: tier)
        case .expired:
            expiredCard
        case .revoked:
            revokedCard
        case .loading, .error:
            loadingRow
        }
    }

    // MARK: Not activated — grosser Call-to-Action

    private var notActivatedCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "key.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Jetzt kostenlos aktivieren")
                    .font(.headline)
                Text("Einmalig Ihre E-Mail hinterlegen. Kostenfrei in der Beta-Phase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                coordinator.settingsRequestedTab = "account"
            } label: {
                Text("Aktivieren")
                    .fontWeight(.semibold)
                    .frame(minWidth: 90)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Activated — kompakte Info-Zeile

    @ViewBuilder private func activatedRow(status: String, tier: LicenseState.Tier) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(email: license.currentEmail)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(license.currentEmail ?? "ALVA-TEXT")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Circle()
                        .fill(tierColor(tier))
                        .frame(width: 6, height: 6)
                    Text(statusText(status: status, tier: tier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Konto verwalten") {
                coordinator.settingsRequestedTab = "account"
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: Expired / Revoked — Warnung

    private var expiredCard: some View {
        statusBanner(
            icon: "exclamationmark.triangle.fill",
            iconColor: .orange,
            title: "Testzeitraum abgelaufen",
            subtitle: "Zur Weiternutzung bitte eine Lizenz erwerben.",
            actionTitle: "Konto ansehen",
            background: Color.orange.opacity(0.08),
            border: Color.orange.opacity(0.35)
        )
    }

    private var revokedCard: some View {
        statusBanner(
            icon: "xmark.seal.fill",
            iconColor: .red,
            title: "Zugang wurde widerrufen",
            subtitle: "Bitte Support kontaktieren: support@adluna.de",
            actionTitle: "Konto ansehen",
            background: Color.red.opacity(0.08),
            border: Color.red.opacity(0.35)
        )
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Lizenzstatus wird geladen …")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Helpers

    @ViewBuilder private func statusBanner(icon: String, iconColor: Color, title: String, subtitle: String, actionTitle: String, background: Color, border: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle) {
                coordinator.settingsRequestedTab = "account"
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1)
        )
    }

    private func tierColor(_ tier: LicenseState.Tier) -> Color {
        switch tier {
        case .full, .paid: return .green
        case .limited:     return .yellow
        }
    }

    private func statusText(status: String, tier: LicenseState.Tier) -> String {
        let statusPart: String = {
            // Identisch zu `AccountTab.statusHeadline`: backend-Strings
            // ("beta") werden im UI auf neutrale Begriffe gemappt, damit
            // der User die App nicht als „in Entwicklung" wahrnimmt.
            switch status {
            case "beta":   return "Aktiv"
            case "trial":  return "Testzeitraum"
            case "active": return "Lizenz aktiv"
            default:       return status.capitalized
            }
        }()
        let tierPart: String = {
            switch tier {
            case .full:    return "Voller Funktionsumfang"
            case .paid:    return "Bezahlt"
            case .limited: return "Eingeschränkt"
            }
        }()
        return "\(statusPart) · \(tierPart)"
    }
}

