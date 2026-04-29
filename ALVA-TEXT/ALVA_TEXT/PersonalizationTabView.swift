// PersonalizationTabView.swift
// ALVA-TEXT — v2.2
//
// Der Reiter „Persönlich“ in den Settings.
//
// Im Standard-Modus zeigen wir nur den Mode-Switch an: User kann auf Pro
// upgraden. In Pro-Modus ist alles freigeschaltet:
//   - Mode-Switch (jederzeit zurück zu Standard)
//   - Profile-Picker mit Multi-Profil-Verwaltung
//   - Identitäts-Block (Name, Initialen, Rolle, Firma, Sprache)
//   - Sign-offs (formell + locker; v2.1.3-Kompat-Felder, sind erstmal die
//     wichtigste UI-Stelle, später werden sie um Pro-Channel-Editor erweitert)
//   - No-Go-Phrasen
//   - Wortschatz-Bibliothek (kompakte Liste, Add/Edit/Delete)
//
// Persistenz läuft über `PersonalizationStore.shared`. Schreibzugriffe
// werden direkt durchgeschrieben (UserDefaults-Schreibgänge sind günstig).

import SwiftUI

struct PersonalizationTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var store: PersonalizationStore = .shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modeCard
                if coordinator.proMode == .pro {
                    profilesCard
                    identityCard
                    signOffsCard
                    avoidPhrasesCard
                    vocabularyCard
                    resetCard
                } else {
                    standardModeHint
                }
            }
            .padding(16)
        }
    }

    // MARK: - Mode-Switch

    private var modeCard: some View {
        GroupBox(label: Label("Modus", systemImage: "switch.2")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: Binding(
                    get: { coordinator.proMode == .unset ? .standard : coordinator.proMode },
                    set: { coordinator.proMode = $0 }
                )) {
                    Text("Standard").tag(ProMode.standard)
                    Text("Pro").tag(ProMode.pro)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(coordinator.proMode == .pro
                     ? "Pro: Personalisierung wirkt im Adaptive-Mode. Alle Felder unten sind aktiv."
                     : "Standard: Schlanker Betrieb ohne Personalisierungs-Block im System-Prompt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var standardModeHint: some View {
        GroupBox(label: Label("Pro freischalten", systemImage: "sparkles")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Du läufst aktuell im Standard-Modus. Pro schaltet auf einen Schlag frei:")
                    .font(.callout)
                bullet("Eigene Identität, Sign-offs pro Kanal, Stil-Marker")
                bullet("Mehrere Profile parallel (privat, geschäftlich, Mandant)")
                bullet("Wortschatz-Bibliothek für Eigennamen und Korrekturen")
                bullet("Custom Dictation Modes & Prompt-Optimizer (in Folge-Releases)")
                bullet("Adaptive Learning lokal, Kontakt-/Kalender-Integration (in Folge-Releases)")

                Text("Alles bleibt lokal. Wechsel jederzeit reversibel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }

    // MARK: - Profile

    private var profilesCard: some View {
        GroupBox(label: Label("Profile", systemImage: "person.2")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Aktives Profil", selection: Binding(
                    get: { store.activeID },
                    set: { store.setActive($0) }
                )) {
                    ForEach(store.profiles) { profile in
                        Text(profileLabel(profile)).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button {
                        _ = store.addNewProfile(name: "Neues Profil")
                    } label: {
                        Label("Neues Profil", systemImage: "plus")
                    }

                    Button {
                        _ = store.duplicate(store.activeID)
                    } label: {
                        Label("Duplizieren", systemImage: "doc.on.doc")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        store.delete(store.activeID)
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    .disabled(store.profiles.count <= 1)
                }

                Text("Profil wirkt sofort — der nächste Adaptive-Mode-Hotkey nutzt automatisch das aktive Profil.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func profileLabel(_ p: PersonalizationProfile) -> String {
        if p.emoji.isEmpty {
            return p.name
        }
        return "\(p.emoji) \(p.name)"
    }

    // MARK: - Identity

    private var identityCard: some View {
        GroupBox(label: Label("Identität", systemImage: "person.crop.circle")) {
            VStack(alignment: .leading, spacing: 8) {
                profileTextField(label: "Profilname", keyPath: \.name)
                profileTextField(label: "Emoji (optional)", keyPath: \.emoji)
                profileTextField(label: "Anredename", keyPath: \.displayName,
                                 prompt: "z. B. „Alper“ oder „Alper Scheel“")
                profileTextField(label: "Initialen", keyPath: \.initials,
                                 prompt: "z. B. „AS“")
                profileTextField(label: "Rolle", keyPath: \.role,
                                 prompt: "z. B. „Geschäftsführer“")
                profileTextField(label: "Firma", keyPath: \.company,
                                 prompt: "z. B. „AdLuna GmbH“")
                profileTextField(label: "Hauptsprache (ISO)", keyPath: \.primaryLanguage,
                                 prompt: "z. B. „de“ oder „en“")

                Text("Diese Felder gelangen in den System-Prompt für den Adaptive-Mode. Niemand außer der OpenAI-API (über deinen eigenen Schlüssel) sieht sie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sign-offs

    private var signOffsCard: some View {
        GroupBox(label: Label("Sign-offs", systemImage: "signature")) {
            VStack(alignment: .leading, spacing: 8) {
                profileTextField(
                    label: "Formell",
                    keyPath: \.formalSignature,
                    prompt: "z. B. „Mit freundlichen Grüßen, Alper Scheel“")
                profileTextField(
                    label: "Locker",
                    keyPath: \.casualSignature,
                    prompt: "z. B. „LG Alper“ oder „A 👋“")
                profileTextField(
                    label: "Default-Sign-off (alle Kanäle)",
                    keyPath: \.defaultStyle.signOff,
                    prompt: "wenn formell/locker leer sind")

                Text("Sign-offs werden NUR genutzt, wenn der Diktat-Text mit einem Gruß-Hinweis endet (z. B. „lg“, „mfg“, „grüße“). Nichts wird erfunden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Avoid Phrases

    @State private var newAvoidPhrase: String = ""

    private var avoidPhrasesCard: some View {
        GroupBox(label: Label("No-Go-Phrasen", systemImage: "nosign")) {
            VStack(alignment: .leading, spacing: 8) {
                let profile = currentProfile
                if profile.avoidPhrases.isEmpty {
                    Text("Noch keine Phrasen definiert.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.avoidPhrases, id: \.self) { phrase in
                        HStack {
                            Text("„\(phrase)“")
                                .font(.callout)
                            Spacer()
                            Button {
                                removeAvoidPhrase(phrase)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    TextField("z. B. „synergistisch“, „Win-Win“", text: $newAvoidPhrase)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addAvoidPhrase() }
                    Button("Hinzufügen") {
                        addAvoidPhrase()
                    }
                    .disabled(newAvoidPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text("Diese Phrasen tauchen NIEMALS im Output auf, auch wenn sie ähnlich klingen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private func addAvoidPhrase() {
        let trimmed = newAvoidPhrase.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var profile = currentProfile
        if !profile.avoidPhrases.contains(trimmed) {
            profile.avoidPhrases.append(trimmed)
            store.upsert(profile)
        }
        newAvoidPhrase = ""
    }

    private func removeAvoidPhrase(_ phrase: String) {
        var profile = currentProfile
        profile.avoidPhrases.removeAll { $0 == phrase }
        store.upsert(profile)
    }

    // MARK: - Vocabulary

    @State private var newVocabHeard: String = ""
    @State private var newVocabWrite: String = ""

    private var vocabularyCard: some View {
        GroupBox(label: Label("Wortschatz / Eigennamen", systemImage: "text.book.closed")) {
            VStack(alignment: .leading, spacing: 8) {
                let profile = currentProfile
                if profile.vocabulary.isEmpty {
                    Text("Noch keine Einträge.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.vocabulary) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                if entry.heard.isEmpty {
                                    Text(entry.write).font(.callout)
                                } else {
                                    HStack(spacing: 6) {
                                        Text(entry.heard).foregroundStyle(.secondary)
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(entry.write).font(.callout).bold()
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                removeVocab(entry.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    TextField("Was Whisper hört (optional)", text: $newVocabHeard)
                        .textFieldStyle(.roundedBorder)
                    TextField("Was geschrieben werden soll", text: $newVocabWrite)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addVocab() }
                    Button("Hinzufügen") {
                        addVocab()
                    }
                    .disabled(newVocabWrite.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text("Erstes Feld leer lassen, wenn du nur einen Eigennamen hinterlegen willst. Maximal 30 Einträge gehen in den Prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private func addVocab() {
        let write = newVocabWrite.trimmingCharacters(in: .whitespaces)
        guard !write.isEmpty else { return }
        var profile = currentProfile
        profile.vocabulary.append(VocabEntry(
            heard: newVocabHeard.trimmingCharacters(in: .whitespaces),
            write: write
        ))
        store.upsert(profile)
        newVocabHeard = ""
        newVocabWrite = ""
    }

    private func removeVocab(_ id: UUID) {
        var profile = currentProfile
        profile.vocabulary.removeAll { $0.id == id }
        store.upsert(profile)
    }

    // MARK: - Reset

    private var resetCard: some View {
        GroupBox(label: Label("Zurücksetzen", systemImage: "arrow.counterclockwise")) {
            VStack(alignment: .leading, spacing: 8) {
                Button(role: .destructive) {
                    store.resetToDefaults()
                } label: {
                    Label("Alle Profile löschen, ein leeres Standard-Profil neu anlegen",
                          systemImage: "trash")
                }
                Text("Setzt sämtliche Personalisierungs-Daten zurück. Profile, Sign-offs, Wortschatz, alles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers für TextFields gegen das aktive Profil

    /// Liefert eine Binding gegen ein einzelnes Profil-Feld. Beim Schreiben
    /// wird das aktive Profil aktualisiert und persistiert.
    private func profileBinding(_ keyPath: WritableKeyPath<PersonalizationProfile, String>) -> Binding<String> {
        Binding(
            get: { currentProfile[keyPath: keyPath] },
            set: { newValue in
                var p = currentProfile
                p[keyPath: keyPath] = newValue
                store.upsert(p)
            }
        )
    }

    @ViewBuilder
    private func profileTextField(
        label: String,
        keyPath: WritableKeyPath<PersonalizationProfile, String>,
        prompt: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 220, alignment: .leading)
                .font(.callout)
            TextField(prompt ?? "", text: profileBinding(keyPath))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var currentProfile: PersonalizationProfile {
        store.activeProfile
    }
}
