// PersonalizationProfile.swift
// ALVA-TEXT
//
// Trägt User-Personalisierung in den OpenAI-System-Prompt.
// Cluster aus dem v2.2-Brainstorm:
//   - Cluster 1: Identität (displayName, initials, role, company, language)
//   - Cluster 2: Stil-Defaults pro Kanal (Du/Sie, Emoji, Sign-off, Marker)
//   - Cluster 4: Wortschatz / Eigennamen
//   - Cluster 5: Multi-Profil (jeweils eines dieser Structs = ein Profil)
//
// Persistierung läuft über `PersonalizationStore` (mehrere Profile, eines aktiv).
// Wirkt nur, wenn `ProMode.current == .pro`.
//
// Backward-Kompat: Die alten v2.1.3-Felder (`casualSignature`, `formalSignature`)
// bleiben als gespeicherte Felder erhalten. Sie werden in `promptBlock(for:)` nur
// noch als Fallback genutzt, wenn der jeweilige Kanal-Stil keinen eigenen
// Sign-off hat. Aufrufer, die die Property `promptBlock` (ohne Argument) nutzen,
// bekommen weiterhin einen sinnvollen Block geliefert.

import Foundation

// MARK: - Kanal-Klassifizierung

/// Welche Art von Ziel-App wir gerade vor uns haben. Steuert, welche
/// Stil-Defaults aus dem Profil ziehen und welcher Sign-off passt.
public enum ChannelClass: String, Codable, CaseIterable, Equatable {
    case mailFormal     // Mail, formal (Sie)
    case mailCasual     // Mail, locker (Du)
    case chat           // Slack, Teams, Discord, Messages, WhatsApp
    case docFormal      // Word, Pages, Google Docs (geschäftlich)
    case docPersonal    // Notes, Obsidian, eigene Notizblöcke
    case codeOrTerminal // Xcode, VS Code, Terminal, Cursor
    case unknown        // Default-Fallback

    public var germanLabel: String {
        switch self {
        case .mailFormal:     return "Mail (Sie)"
        case .mailCasual:     return "Mail (Du)"
        case .chat:           return "Chat (Slack, Teams, Messages)"
        case .docFormal:      return "Dokument (geschäftlich)"
        case .docPersonal:    return "Notiz / persönlich"
        case .codeOrTerminal: return "Code / Terminal"
        case .unknown:        return "Unbekannt / Default"
        }
    }
}

// MARK: - Stil-Block pro Kanal

public struct ChannelStyle: Codable, Equatable {
    public enum AddressForm: String, Codable, Equatable {
        case du
        case sie
        case auto

        public var germanLabel: String {
            switch self {
            case .du:   return "Du"
            case .sie:  return "Sie"
            case .auto: return "Automatisch"
            }
        }
    }

    public enum EmojiPolicy: String, Codable, Equatable {
        case never
        case sparingly
        case freely

        public var germanLabel: String {
            switch self {
            case .never:      return "Nie"
            case .sparingly:  return "Sparsam"
            case .freely:     return "Großzügig"
            }
        }
    }

    public var addressForm: AddressForm = .auto
    public var emojiPolicy: EmojiPolicy = .never
    /// Bevorzugter Sign-off (z. B. „Mit freundlichen Grüßen, Alper").
    /// Leerstring = kein Sign-off.
    public var signOff: String = ""
    /// Stil-Marker (z. B. „nüchtern", „warm", „sachlich").
    public var styleMarkers: [String] = []

    public init() {}

    /// True, wenn der Kanal-Stil etwas konkretes festlegt.
    public var hasAnyValue: Bool {
        addressForm != .auto
            || emojiPolicy != .never
            || !signOff.isEmpty
            || !styleMarkers.isEmpty
    }
}

// MARK: - Wortschatz

/// Ein Eintrag der Wortschatz-Bibliothek. Entweder ein Eigenname, der
/// korrekt geschrieben werden soll, oder ein Korrektur-Mapping
/// (Whisper-Fehl-Output → Soll-Schreibweise).
public struct VocabEntry: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    /// Was Whisper transkribiert (leer = reiner Eigenname-Eintrag).
    public var heard: String = ""
    /// Was geschrieben werden soll.
    public var write: String = ""
    /// Optionaler Hinweis (z. B. „Kollege", „Firma", „Produkt").
    public var note: String = ""

    public init(heard: String = "", write: String = "", note: String = "") {
        self.heard = heard
        self.write = write
        self.note = note
    }
}

// MARK: - Personalisierungs-Profil

/// Ein einzelnes Profil. Mehrere Profile leben parallel im
/// `PersonalizationStore`, eines davon ist aktiv.
public struct PersonalizationProfile: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    /// Profilname für die UI.
    public var name: String = "Standard"
    /// Optional: Emoji für den Menübar-Picker (z. B. „💼").
    public var emoji: String = ""

    // ── Cluster 1: Identität ──────────────────────────────────────────
    public var displayName: String = ""        // z. B. „Alper" oder „Alper Scheel"
    public var initials: String = ""           // z. B. „AS"
    public var role: String = ""               // z. B. „Geschäftsführer"
    public var company: String = ""            // z. B. „AdLuna GmbH"
    public var primaryLanguage: String = "de"  // ISO-Code

    // ── v2.1.3-Backward-Kompat ───────────────────────────────────────
    /// Bevorzugte Grußformel für lockere Kanäle (WhatsApp, Signal, iMessage, SMS).
    public var casualSignature: String = ""
    /// Bevorzugte Grußformel für formelle Kanäle (E-Mail im Sie).
    public var formalSignature: String = ""

    // ── Cluster 2: Stil-Defaults pro Kanal ────────────────────────────
    public var stylesPerChannel: [ChannelClass: ChannelStyle] = [:]
    /// Globaler Fallback-Stil. Wird genutzt, wenn der Kanal keinen eigenen Stil hat.
    public var defaultStyle: ChannelStyle = ChannelStyle()
    /// Phrasen, die NIEMALS im Output stehen dürfen.
    public var avoidPhrases: [String] = []

    // ── Cluster 4: Wortschatz ─────────────────────────────────────────
    public var vocabulary: [VocabEntry] = []

    public init(name: String = "Standard") {
        self.name = name
    }

    // MARK: - Codable (Dictionary<Enum,Value>-Workaround)

    /// SwiftPM/Foundation kodiert `[ChannelClass: ChannelStyle]` JSON-konform
    /// als Object — das funktioniert seit Swift 5.x dank `RawRepresentable`-
    /// Keys. Wir geben explizit alle Property-Names an, damit auch ältere
    /// Settings-Dateien mit fehlenden Feldern decodierbar bleiben.
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case displayName, initials, role, company, primaryLanguage
        case casualSignature, formalSignature
        case stylesPerChannel, defaultStyle, avoidPhrases
        case vocabulary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Standard"
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        initials = try c.decodeIfPresent(String.self, forKey: .initials) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        primaryLanguage = try c.decodeIfPresent(String.self, forKey: .primaryLanguage) ?? "de"
        casualSignature = try c.decodeIfPresent(String.self, forKey: .casualSignature) ?? ""
        formalSignature = try c.decodeIfPresent(String.self, forKey: .formalSignature) ?? ""
        defaultStyle = try c.decodeIfPresent(ChannelStyle.self, forKey: .defaultStyle) ?? ChannelStyle()
        avoidPhrases = try c.decodeIfPresent([String].self, forKey: .avoidPhrases) ?? []
        vocabulary = try c.decodeIfPresent([VocabEntry].self, forKey: .vocabulary) ?? []

        // stylesPerChannel ist optional und wird über String-Keys persistiert.
        if let raw = try c.decodeIfPresent([String: ChannelStyle].self, forKey: .stylesPerChannel) {
            var dict: [ChannelClass: ChannelStyle] = [:]
            for (key, value) in raw {
                if let channel = ChannelClass(rawValue: key) {
                    dict[channel] = value
                }
            }
            stylesPerChannel = dict
        } else {
            stylesPerChannel = [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(emoji, forKey: .emoji)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(initials, forKey: .initials)
        try c.encode(role, forKey: .role)
        try c.encode(company, forKey: .company)
        try c.encode(primaryLanguage, forKey: .primaryLanguage)
        try c.encode(casualSignature, forKey: .casualSignature)
        try c.encode(formalSignature, forKey: .formalSignature)
        try c.encode(defaultStyle, forKey: .defaultStyle)
        try c.encode(avoidPhrases, forKey: .avoidPhrases)
        try c.encode(vocabulary, forKey: .vocabulary)

        // stylesPerChannel als String-Keyed Dict speichern
        let raw: [String: ChannelStyle] = stylesPerChannel.reduce(into: [:]) { acc, pair in
            acc[pair.key.rawValue] = pair.value
        }
        try c.encode(raw, forKey: .stylesPerChannel)
    }

    // MARK: - Convenience

    /// True, sobald irgendein Personalisierungs-Feld gefüllt ist —
    /// nur dann fügt der OpenAI-System-Prompt einen Personalisierungs-Block ein.
    public var hasAnyValue: Bool {
        !displayName.isEmpty
            || !initials.isEmpty
            || !role.isEmpty
            || !company.isEmpty
            || !casualSignature.isEmpty
            || !formalSignature.isEmpty
            || !defaultStyle.signOff.isEmpty
            || defaultStyle.hasAnyValue
            || stylesPerChannel.values.contains(where: { $0.hasAnyValue })
            || !avoidPhrases.isEmpty
            || !vocabulary.isEmpty
    }

    /// Liefert den effektiven Stil für einen gegebenen Kanal — Profil-Spezifisch
    /// wenn vorhanden, sonst Default-Stil des Profils.
    public func style(for channel: ChannelClass) -> ChannelStyle {
        stylesPerChannel[channel] ?? defaultStyle
    }

    // MARK: - System-Prompt-Block

    /// Backward-kompatibler Property-Aufruf — liefert den Block für `.unknown`.
    /// Aufrufer aus v2.1.3 bleiben funktionsfähig.
    public var promptBlock: String {
        promptBlock(for: .unknown)
    }

    /// Markdown-Block, der in den System-Prompt der Adaptive-Message-Funktion
    /// (oder in Custom-Mode-Prompts) eingebettet wird.
    public func promptBlock(for channel: ChannelClass = .unknown) -> String {
        var lines: [String] = []

        // Identität
        if !displayName.isEmpty {
            lines.append("- Anredename des Nutzers: „\(displayName)\"")
        }
        if !initials.isEmpty {
            lines.append("- Bevorzugte Kurzform / Initialen: „\(initials)\"")
        }
        if !role.isEmpty {
            lines.append("- Rolle des Nutzers: \(role)")
        }
        if !company.isEmpty {
            lines.append("- Firmenkontext: \(company)")
        }

        // Effektiver Stil für diesen Kanal
        let style = self.style(for: channel)
        if style.addressForm != .auto {
            lines.append("- Anredeform: \(style.addressForm.germanLabel)")
        }
        if style.emojiPolicy != .never {
            lines.append("- Emoji-Verwendung: \(style.emojiPolicy.germanLabel)")
        }

        // Sign-off: zuerst Kanal-spezifisch, dann v2.1.3-Backward-Kompat-Felder.
        let effectiveSignOff: String = {
            if !style.signOff.isEmpty { return style.signOff }
            switch channel {
            case .mailFormal, .docFormal:
                return formalSignature
            case .mailCasual, .chat, .docPersonal:
                return casualSignature
            default:
                return ""
            }
        }()
        if !effectiveSignOff.isEmpty {
            lines.append("- Bevorzugter Sign-off: „\(effectiveSignOff)\"")
        }

        if !style.styleMarkers.isEmpty {
            lines.append("- Stil-Marker: " + style.styleMarkers.joined(separator: ", "))
        }

        // No-Go-Phrasen
        if !avoidPhrases.isEmpty {
            let joined = avoidPhrases.map { "„\($0)\"" }.joined(separator: ", ")
            lines.append("- Phrasen, die NIE benutzt werden dürfen: \(joined)")
        }

        // Wortschatz (max. 30 Einträge in den Prompt, sonst wird's zu lang)
        if !vocabulary.isEmpty {
            let entries = vocabulary.prefix(30).compactMap { entry -> String? in
                let write = entry.write.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !write.isEmpty else { return nil }
                let heard = entry.heard.trimmingCharacters(in: .whitespacesAndNewlines)
                if heard.isEmpty {
                    return "  • \(write)"
                } else {
                    return "  • \(heard) → \(write)"
                }
            }
            if !entries.isEmpty {
                lines.append("- Wortschatz / Eigennamen (genau so schreiben):")
                lines.append(contentsOf: entries)
            }
        }

        // Channel-Hinweis
        if channel != .unknown {
            lines.append("- Aktueller Kanal-Kontext: \(channel.germanLabel)")
        }

        return lines.joined(separator: "\n")
    }
}
