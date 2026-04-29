// ProMode.swift
// ALVA-TEXT
//
// Schaltet die Personalisierungs-Schicht (Identität, Stil, Wortschatz,
// Multi-Profil, Custom Modes, Adaptive Learning, Kontakte/Kalender)
// frei oder aus. Standard = aus, Pro = an.
//
// Eingeführt mit v2.2 zur Self-Selection beim Onboarding:
//   - Standard: schlanke App, kein Personalisierungs-Block im System-Prompt.
//   - Pro:      vollausgebaute Personalisierung, alle Settings-Tabs sichtbar.
//
// Persistierung: UserDefaults-Key `alva.proMode`. Default beim ersten
// Start ist `.unset`, was das Onboarding zur Modus-Wahl erzwingt.

import Foundation

public enum ProMode: String, Codable, Equatable {
    /// Noch keine Wahl getroffen — Onboarding muss zur Modus-Auswahl führen.
    case unset
    /// Schlanke Variante: Roh-Diktat, Adaptive-Mode mit nüchternem Default,
    /// Reverse-Übersetzung, Mehrsprachigkeit. Keine Personalisierungs-Tabs.
    case standard
    /// Vollausstattung: Identität, Stil, Wortschatz, Profile, Custom Modes,
    /// Cloud-Privacy-Feinsteuerung, Adaptive Learning (opt-in), Kontakte/Kalender.
    case pro

    public var germanLabel: String {
        switch self {
        case .unset:    return "Nicht gesetzt"
        case .standard: return "Standard"
        case .pro:      return "Pro"
        }
    }

    public var germanShortLabel: String {
        switch self {
        case .unset:    return "—"
        case .standard: return "ALVA-TEXT"
        case .pro:      return "ALVA-TEXT Pro"
        }
    }

    /// True, sobald der User sich entschieden hat (egal ob Standard oder Pro).
    public var hasChosen: Bool {
        self != .unset
    }

    /// True für Pro — bestimmt, ob Personalisierungs-Tabs in den Settings
    /// sichtbar sind und ob der Personalisierungs-Block in System-Prompts
    /// eingebaut wird.
    public var isPro: Bool {
        self == .pro
    }
}

/// Persistierte Mode-Wahl. UserDefaults-gestützt, eine Single-Source-of-Truth.
public enum ProModeStore {
    private static let key = "alva.proMode"

    public static var current: ProMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let mode = ProMode(rawValue: raw) else {
                return .unset
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    /// Setzt die Mode-Wahl auf den Initialzustand zurück. Nur für Debug /
    /// "Onboarding wiederholen" — niemals automatisch aufrufen.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
