import SwiftUI

// MARK: - Root

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }

            ModesTab()
                .tabItem { Label("Modi & Kürzel", systemImage: "keyboard") }

            TranslationTab()
                .tabItem { Label("Sprachübersetzung", systemImage: "character.bubble") }

            AccessibilityTab()
                .tabItem { Label("Bedienungshilfen", systemImage: "hand.tap") }

            StatusTab()
                .tabItem { Label("Status", systemImage: "waveform.badge.magnifyingglass") }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 600)
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

private struct GeneralTab: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "OpenAI", subtitle: "API-Schlüssel für Whisper & GPT", icon: "key.fill", accent: .blue) {
                    SecureField("sk-…", text: $coordinator.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Wird im macOS-Schlüsselbund gespeichert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card(title: "Verhalten", subtitle: "Standardaktionen nach der Transkription", icon: "gearshape.2.fill", accent: .gray) {
                    Toggle("Nach Transkription automatisch einfügen", isOn: $coordinator.autoPaste)
                    Toggle("Höfliche Umformulierung im Höflich-Modus", isOn: $coordinator.rewriteEnabled)
                }

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

                Card(title: "Verlauf", subtitle: "Transkript-Historie (letzte \(AppCoordinator.maxHistoryEntries))", icon: "clock.fill", accent: .indigo) {
                    Toggle("Transkripte speichern", isOn: $coordinator.historyEnabled)
                    HStack {
                        Button("Verlauf öffnen …") {
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

                Card(title: "App beenden", icon: "power", accent: .red) {
                    Button("ALVA-TEXT beenden") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(2)
        }
    }
}

// MARK: - Modi & Kürzel

private struct ModesTab: View {
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

// MARK: - Sprachübersetzung

private struct TranslationTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var inputMonitoringTick: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                InputMonitoringCard(tick: $inputMonitoringTick)

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

    var body: some View {
        let trusted = coordinator.isInputMonitoringTrusted()
        Card(title: "Eingabeüberwachung",
             subtitle: trusted ? "Freigegeben" : "Muss freigegeben werden — sonst funktionieren weder F-Tasten noch Rückwärtsübersetzung",
             icon: "keyboard.fill",
             accent: trusted ? .green : .orange) {
            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(trusted ? .green : .orange)
                VStack(alignment: .leading) {
                    Text(trusted ? "Eingabeüberwachung aktiv" : "Eingabeüberwachung fehlt")
                        .fontWeight(.semibold)
                    Text(trusted
                         ? "F-Tasten für Sprachwahl und ⌃⌥Return für Rückwärtsübersetzung werden erkannt."
                         : "Ohne diese Erlaubnis sehen wir keine Tasten-Events von anderen Apps. Jedes Sprach-F-Taste, jeder Any-Key-Stop im Toggle und die Rückwärtsübersetzung bleiben stumm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .id(tick)

            HStack {
                Button("Systemdialog anfordern") {
                    coordinator.requestInputMonitoringPrompt()
                    tick &+= 1
                }
                Button("Systemeinstellungen öffnen") {
                    coordinator.openInputMonitoringSettings()
                }
                Button("Erneut prüfen") {
                    tick &+= 1
                }
            }
            .buttonStyle(.bordered)

            Text("Hinweis: Systemeinstellungen → Datenschutz & Sicherheit → Eingabeüberwachung. ALVA-TEXT hinzufügen und aktivieren. Nach jedem Rebuild ggf. alten Eintrag entfernen und neu hinzufügen (selbe Logik wie bei den Bedienungshilfen).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                // Big live preview of the configured combo
                Text(currentComboPreview)
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
                    Text("Text in einer beliebigen App markieren, dann die eingestellte Kombination drücken. ALVA kopiert die Auswahl, übersetzt sie ins Deutsche und zeigt das Ergebnis in einem Popup mit Kopieren-Button. Die Zwischenablage wird danach wieder auf ihren ursprünglichen Inhalt zurückgesetzt.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Divider().padding(.vertical, 2)

            Toggle("Rückwärtsübersetzung aktivieren", isOn: $coordinator.reverseTranslateEnabled)

            HStack(spacing: 18) {
                Toggle("⌃ Control", isOn: $coordinator.reverseTranslateModifiers.control)
                Toggle("⌥ Option", isOn: $coordinator.reverseTranslateModifiers.option)
                Toggle("⇧ Shift", isOn: $coordinator.reverseTranslateModifiers.shift)
                Toggle("⌘ Command", isOn: $coordinator.reverseTranslateModifiers.command)
            }
            .toggleStyle(.checkbox)
            .disabled(!coordinator.reverseTranslateEnabled)

            HStack {
                Text("Taste")
                    .foregroundStyle(.secondary)
                Picker("", selection: $coordinator.reverseTranslateKeyCode) {
                    ForEach(TriggerKeyCatalog.options, id: \.code) { opt in
                        Text(opt.label).tag(opt.code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer()
                Button("Zurücksetzen") {
                    coordinator.resetReverseTranslateDefaults()
                }
            }
            .disabled(!coordinator.reverseTranslateEnabled)

            if !coordinator.reverseTranslateModifiers.isValid {
                Label("Die Kombination braucht mindestens einen Modifier — sonst löst sie nicht aus.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Text("Hinweis: ⌃⌥Leertaste ist bei macOS systemweit für die Eingabequellen-Umschaltung reserviert und funktioniert daher oft nicht. Der Schrägstrich „/\" ist die ergonomische Standardempfehlung.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentComboPreview: String {
        let mods = coordinator.reverseTranslateModifiers.displaySymbols
        let key  = TriggerKeyCatalog.label(for: coordinator.reverseTranslateKeyCode)
        if mods == "—" { return "—" }
        return "\(mods)\u{2009}\(key)"
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

private struct AccessibilityTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var tick: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "Accessibility-Status", icon: "hand.tap", accent: coordinator.isAccessibilityTrusted() ? .green : .orange) {
                    statusRow
                }

                Card(title: "Aktionen", icon: "wrench.and.screwdriver.fill", accent: .blue) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Systemdialog anzeigen (Erlaubnis anfordern)") {
                            coordinator.requestAccessibilityPrompt()
                            tick &+= 1
                        }
                        Button("Systemeinstellungen öffnen") {
                            coordinator.openAccessibilitySettings()
                        }
                        Button("Erneut prüfen") {
                            tick &+= 1
                        }
                        Button("Testeinfügung (in vorher fokussierte App)") {
                            coordinator.runPasteSelfTest()
                        }
                        .disabled(!coordinator.isAccessibilityTrusted())
                    }
                    .buttonStyle(.bordered)
                }

                Card(title: "Warum wird das benötigt?", icon: "questionmark.circle", accent: .gray) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Das automatische Einfügen schickt einen simulierten ⌘V-Tastendruck über die Accessibility-API. macOS erlaubt das nur Apps, die ausdrücklich unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen freigegeben sind.")
                        Text("Nach jedem Neu-Build in Xcode erhält das Programm eine neue Signatur. macOS kann die Erlaubnis dann zurücksetzen. In dem Fall: alten ALVA-TEXT-Eintrag per Minus-Button entfernen und die neu gebaute App erneut hinzufügen.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(2)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        let trusted = coordinator.isAccessibilityTrusted()
        HStack(spacing: 10) {
            Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(trusted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(trusted ? "Bedienungshilfen freigegeben" : "Bedienungshilfen fehlen")
                    .fontWeight(.semibold)
                Text(trusted ? "Auto-Einfügen ist aktiv."
                             : "Auto-Einfügen ist deaktiviert — Texte landen nur in der Zwischenablage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .id(tick)
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

// MARK: - Reverse Translate Popup

struct ReverseTranslatePopup: View {
    let originalChunks: [LanguageChunk]
    let translated: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: just "ALVA-TEXT", nothing else
            HStack {
                Text("ALVA-TEXT")
                    .font(.headline)
                Spacer()
            }
            .padding(.top, 2)

            // Original split by detected language
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(originalChunks) { chunk in
                        LanguageBlock(
                            label: chunk.displayName,
                            text: chunk.text,
                            accent: .blue
                        )
                    }

                    Divider().padding(.vertical, 2)

                    LanguageBlock(
                        label: "Deutsch",
                        text: translated,
                        accent: .green
                    )
                }
            }
        }
        .padding(18)
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 800,
               minHeight: 300, idealHeight: 440, maxHeight: 700)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .onExitCommand {
            onClose()
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var step: Int = 0
    @State private var accessibilityTick: Int = 0
    @State private var inputMonitoringTick: Int = 0

    let onFinish: () -> Void

    private let totalSteps = 4

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
                    case 0: welcomePage
                    case 1: apiKeyPage
                    case 2: accessibilityPage
                    case 3: inputMonitoringPage
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
        switch step {
        case 1: return !coordinator.apiKey.isEmpty
        default: return true
        }
    }

    // Pages

    @ViewBuilder
    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Willkommen bei ALVA-TEXT")
                .font(.title2)
                .bold()
            Text("In vier Schritten ist die App einsatzbereit:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                bullet(number: 1, text: "OpenAI-API-Schlüssel eintragen.")
                bullet(number: 2, text: "Bedienungshilfen freigeben (für das automatische Einfügen).")
                bullet(number: 3, text: "Eingabeüberwachung freigeben (für Sprach-F-Tasten und Rückwärtsübersetzung).")
            }
            .padding(.top, 4)

            Text("Danach kannst du loslegen: Control gedrückt halten und diktieren → sauberes Transkript. Option → höfliche Umformulierung. Command → lockerer Chat-Stil.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var apiKeyPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schritt 1 — OpenAI-Schlüssel")
                .font(.title2)
                .bold()
            Text("ALVA-TEXT nutzt Whisper (Transkription) und GPT-4o-mini (Umformulierung/Übersetzung). Du brauchst einen eigenen API-Schlüssel von platform.openai.com — der Schlüssel wird lokal im macOS-Schlüsselbund gespeichert.")
                .foregroundStyle(.secondary)

            SecureField("sk-…", text: $coordinator.apiKey)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)

            if coordinator.apiKey.isEmpty {
                Label("Ohne Schlüssel kann ALVA keine Transkription durchführen.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Label("Schlüssel gespeichert.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var accessibilityPage: some View {
        let trusted = coordinator.isAccessibilityTrusted()
        VStack(alignment: .leading, spacing: 12) {
            Text("Schritt 2 — Bedienungshilfen")
                .font(.title2)
                .bold()
            Text("Für das automatische Einfügen in die fokussierte App simuliert ALVA ⌘V. Das braucht die Berechtigung \"Bedienungshilfen\".")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(trusted ? .green : .orange)
                Text(trusted ? "Bedienungshilfen sind freigegeben." : "Bedienungshilfen fehlen.")
                    .fontWeight(.semibold)
            }
            .id(accessibilityTick)

            HStack {
                Button("Systemdialog anzeigen") {
                    coordinator.requestAccessibilityPrompt()
                    accessibilityTick &+= 1
                }
                Button("Systemeinstellungen öffnen") {
                    coordinator.openAccessibilitySettings()
                }
                Button("Erneut prüfen") {
                    accessibilityTick &+= 1
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var inputMonitoringPage: some View {
        let trusted = coordinator.isInputMonitoringTrusted()
        VStack(alignment: .leading, spacing: 12) {
            Text("Schritt 3 — Eingabeüberwachung")
                .font(.title2)
                .bold()
            Text("Für Sprach-F-Tasten während der Aufnahme und für die Rückwärtsübersetzung muss ALVA Tastaturereignisse anderer Apps mitlesen. Das braucht die Berechtigung \"Eingabeüberwachung\".")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(trusted ? .green : .orange)
                Text(trusted ? "Eingabeüberwachung ist freigegeben." : "Eingabeüberwachung fehlt.")
                    .fontWeight(.semibold)
            }
            .id(inputMonitoringTick)

            HStack {
                Button("Systemdialog anzeigen") {
                    coordinator.requestInputMonitoringPrompt()
                    inputMonitoringTick &+= 1
                }
                Button("Systemeinstellungen öffnen") {
                    coordinator.openInputMonitoringSettings()
                }
                Button("Erneut prüfen") {
                    inputMonitoringTick &+= 1
                }
            }
            .buttonStyle(.bordered)

            Text("Wenn die Ampel nach dem Freigeben in den Systemeinstellungen nicht sofort grün wird: ALVA-TEXT einmal beenden und neu starten.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
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
