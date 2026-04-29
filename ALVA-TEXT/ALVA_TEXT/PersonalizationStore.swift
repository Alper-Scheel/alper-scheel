// PersonalizationStore.swift
// ALVA-TEXT
//
// Multi-Profil-Manager für die v2.2-Personalisierung (Cluster 5).
// Hält N Profile parallel, eines davon ist aktiv, wechselbar über den
// Menübar-Picker oder die Settings.
//
// Persistierung: UserDefaults — `alva.profiles` (JSON-encoded Array)
// und `alva.activeProfileID` (UUID-String).
//
// Wirkt nur, wenn `ProMode.current == .pro`. Im Standard-Modus liefert
// `activeProfile` zwar weiterhin ein Profil, der `OpenAIService` ignoriert
// es aber, weil der Coordinator dann gar kein Personalization-Argument
// durchreicht.

import Foundation
import SwiftUI

@MainActor
public final class PersonalizationStore: ObservableObject {
    public static let shared = PersonalizationStore()

    // MARK: - Persistierte Schlüssel

    private static let profilesKey = "alva.profiles"
    private static let activeIDKey = "alva.activeProfileID"

    // MARK: - Published State

    @Published public private(set) var profiles: [PersonalizationProfile]
    @Published public private(set) var activeID: UUID

    // MARK: - Init

    public init() {
        let loaded = PersonalizationStore.loadProfilesFromDefaults()
        if loaded.isEmpty {
            // Erstinitialisierung: ein leeres Default-Profil.
            let seed = PersonalizationProfile(name: "Standard")
            self.profiles = [seed]
            self.activeID = seed.id
            PersonalizationStore.saveProfilesToDefaults([seed])
            UserDefaults.standard.set(seed.id.uuidString, forKey: PersonalizationStore.activeIDKey)
        } else {
            self.profiles = loaded
            // Aktive ID laden, oder auf erstes Profil fallen.
            if let raw = UserDefaults.standard.string(forKey: PersonalizationStore.activeIDKey),
               let parsed = UUID(uuidString: raw),
               loaded.contains(where: { $0.id == parsed }) {
                self.activeID = parsed
            } else {
                self.activeID = loaded[0].id
                UserDefaults.standard.set(loaded[0].id.uuidString, forKey: PersonalizationStore.activeIDKey)
            }
        }
    }

    // MARK: - Active Profile

    /// Gibt das aktive Profil zurück. Fällt auf das erste Profil zurück,
    /// falls die `activeID` ungültig geworden ist (sollte nicht passieren,
    /// aber defensives Handling für korrupte UserDefaults).
    public var activeProfile: PersonalizationProfile {
        if let p = profiles.first(where: { $0.id == activeID }) {
            return p
        }
        return profiles.first ?? PersonalizationProfile(name: "Standard")
    }

    public func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        UserDefaults.standard.set(id.uuidString, forKey: PersonalizationStore.activeIDKey)
    }

    // MARK: - CRUD

    /// Aktualisiert ein bestehendes Profil. Falls das Profil nicht (mehr)
    /// in der Liste ist, wird es als neues angefügt.
    public func upsert(_ profile: PersonalizationProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        persist()
    }

    /// Erzeugt ein neues, leeres Profil und setzt es als aktiv.
    @discardableResult
    public func addNewProfile(name: String = "Neues Profil", emoji: String = "") -> PersonalizationProfile {
        var p = PersonalizationProfile(name: name)
        p.emoji = emoji
        profiles.append(p)
        activeID = p.id
        persist()
        UserDefaults.standard.set(p.id.uuidString, forKey: PersonalizationStore.activeIDKey)
        return p
    }

    /// Dupliziert ein bestehendes Profil mit neuem Namen.
    @discardableResult
    public func duplicate(_ id: UUID) -> PersonalizationProfile? {
        guard let original = profiles.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " (Kopie)"
        profiles.append(copy)
        persist()
        return copy
    }

    /// Löscht ein Profil. Verhindert das Löschen des letzten verbliebenen
    /// Profils — es muss immer mindestens eines existieren.
    public func delete(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeID == id, let first = profiles.first {
            activeID = first.id
            UserDefaults.standard.set(first.id.uuidString, forKey: PersonalizationStore.activeIDKey)
        }
        persist()
    }

    public func rename(_ id: UUID, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        persist()
    }

    /// Setzt alle Profile auf den Initialzustand zurück (ein leeres
    /// „Standard"-Profil). Nur für Reset-Buttons in den Einstellungen.
    public func resetToDefaults() {
        let seed = PersonalizationProfile(name: "Standard")
        profiles = [seed]
        activeID = seed.id
        persist()
        UserDefaults.standard.set(seed.id.uuidString, forKey: PersonalizationStore.activeIDKey)
    }

    // MARK: - Persistence

    private func persist() {
        PersonalizationStore.saveProfilesToDefaults(profiles)
    }

    private static func loadProfilesFromDefaults() -> [PersonalizationProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey) else { return [] }
        do {
            return try JSONDecoder().decode([PersonalizationProfile].self, from: data)
        } catch {
            // Defensive: Bei Decode-Fehler (z. B. bei Format-Migration) lieber
            // mit leerer Liste starten, als die App crashen zu lassen.
            print("ALVA PersonalizationStore: profile decode failed:", error.localizedDescription)
            return []
        }
    }

    private static func saveProfilesToDefaults(_ profiles: [PersonalizationProfile]) {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: profilesKey)
        } catch {
            print("ALVA PersonalizationStore: profile encode failed:", error.localizedDescription)
        }
    }
}
