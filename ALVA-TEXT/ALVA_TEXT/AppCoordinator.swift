import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

enum AppStatus: String {
    case idle
    case recording
    case transcribing
    case rewriting
    case translating     // reserved for Chunk 2: language override via F-keys
    case pasted
    case copied          // transcript landed in clipboard but auto-paste was off / failed
    case needsAccessibility  // Accessibility permission missing — can't auto-paste
    case error
}

enum HotkeyMode: String {
    case standard    // direct transcript, light cleanup
    case polite      // polite German reformulation
    case message     // adaptive chat/social-media style (tone mirrors input)

    var germanLabel: String {
        switch self {
        case .standard: return "Standard"
        case .polite:   return "Höflich"
        case .message:  return "Nachricht"
        }
    }

    /// True if the mode needs an OpenAI call (rewrite or translate).
    /// If no API key is set, falling back to plain transcript.
    var requiresCloud: Bool {
        switch self {
        case .standard: return false
        case .polite, .message: return true
        }
    }
}

/// Which backend performs the speech-to-text step.
enum TranscriptionBackend: String, CaseIterable {
    case local  // on-device WhisperKit (default, no API key needed)
    case cloud  // OpenAI Whisper (better quality, costs API credits)
    case auto   // cloud if API key + internet, else local fallback

    var germanLabel: String {
        switch self {
        case .local: return "Lokal (ohne Internet)"
        case .cloud: return "Cloud (OpenAI)"
        case .auto:  return "Automatisch (Cloud wenn möglich)"
        }
    }

    var germanDescription: String {
        switch self {
        case .local: return "Whisper-Small läuft direkt auf deinem Mac. Kein Internet, kein API-Schlüssel, kein Datenaustausch. Etwas geringere Qualität als Cloud-Whisper, aber für deutsche Diktate sehr solide."
        case .cloud: return "OpenAI-Whisper via Cloud. Beste Qualität, sehr schnell. Benötigt gültigen API-Schlüssel und Internet. Audio-Dateien werden an OpenAI gesendet."
        case .auto:  return "Automatisch Cloud wenn Schlüssel + Internet verfügbar sind, sonst lokal. Empfohlen, wenn du beides möchtest."
        }
    }
}

/// One entry in the transcript history. Stored as JSON in UserDefaults.
struct TranscriptEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let date: Date
    let modeRawValue: String
    let targetLanguageISO: String?
    let original: String    // raw Whisper transcript
    let final: String       // what got pasted (after rewrite/translate)

    var mode: HotkeyMode? { HotkeyMode(rawValue: modeRawValue) }
}

/// One billable OpenAI-API call. Stored as JSON in UserDefaults so we can
/// show the user a running tally of cloud-API spending.
struct CostEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let date: Date
    let kind: Kind
    let model: String
    let audioSeconds: Double?      // set for transcription
    let promptTokens: Int?         // set for chat completions
    let completionTokens: Int?     // set for chat completions
    let costUSD: Double

    enum Kind: String, Codable {
        case transcribe
        case rewrite
        case translate
    }
}

/// Central price list so we can compute `costUSD` deterministically. Values
/// are USD per unit (per minute for audio, per 1M tokens for chat).
/// Updated 2026-04-22 from OpenAI's public pricing page.
enum OpenAIPricing {
    static func transcriptionCost(audioSeconds: Double, model: String) -> Double {
        // $0.006/min for whisper-1 + gpt-4o-mini-transcribe (as of 2026-04).
        let perMinute: Double
        switch model {
        case "gpt-4o-mini-transcribe", "whisper-1": perMinute = 0.006
        case "gpt-4o-transcribe":                   perMinute = 0.012
        default:                                    perMinute = 0.006
        }
        return audioSeconds / 60.0 * perMinute
    }

    static func chatCost(model: String, promptTokens: Int, completionTokens: Int) -> Double {
        let inputPerMillion: Double
        let outputPerMillion: Double
        switch model {
        case "gpt-4o-mini":
            inputPerMillion  = 0.15
            outputPerMillion = 0.60
        case "gpt-4o":
            inputPerMillion  = 2.50
            outputPerMillion = 10.00
        default:
            inputPerMillion  = 0.15
            outputPerMillion = 0.60
        }
        return Double(promptTokens) / 1_000_000.0 * inputPerMillion
             + Double(completionTokens) / 1_000_000.0 * outputPerMillion
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var status: AppStatus = .idle
    /// Live-updated mirror of `AXIsProcessTrusted()`. Refreshed every 2s by
    /// a background timer so the Settings UI reflects reality without the
    /// user having to click a "re-check" button.
    @Published var accessibilityTrusted: Bool = AXIsProcessTrusted()
    /// Live-updated mirror of Input-Monitoring permission.
    @Published var inputMonitoringTrusted: Bool = false
    @Published var lastTranscript: String = UserDefaults.standard.string(forKey: "lastTranscript") ?? ""
    @Published var lastRewrittenText: String = UserDefaults.standard.string(forKey: "lastRewritten") ?? ""
    @Published var apiKey: String = AppCoordinator.loadInitialAPIKey() {
        didSet {
            KeychainStore.set(apiKey, for: "openaiApiKey")
            // v2.1.6: API-Key-Validation (#B14)
            // Bei jeder Key-Änderung asynchron gegen OpenAI testen, damit
            // ungültige/abgelaufene Keys sofort sichtbar gemacht werden.
            // Vorher hat die App den Key wortlos gespeichert und ist erst
            // beim ersten Cloud-Aufruf gefailt — der User kannte die Ursache
            // nie und glaubte, die App sei kaputt.
            apiKeyValidation = apiKey.isEmpty ? .empty : .checking
            if !apiKey.isEmpty {
                Task { await validateAPIKey(apiKey) }
            }
        }
    }

    // v2.1.6: Validation-Status für den OpenAI-Key.
    enum APIKeyValidation: Equatable {
        case empty           // kein Key gesetzt — Lokal-Modus reicht
        case checking        // läuft gerade ein Test-Request
        case valid           // OpenAI hat den Key bestätigt
        case invalid(String) // 401 — Key abgelehnt
        case quotaExceeded   // 429 — Account-Quota oder Rate-Limit
        case networkError    // konnte nicht prüfen, Key gespeichert aber Status unklar
    }

    @Published private(set) var apiKeyValidation: APIKeyValidation = .empty

    /// Prüft den Key gegen OpenAI's `/v1/models`-Endpoint. 200 → valid,
    /// 401 → invalid, 429 → quota, alles andere → networkError.
    private func validateAPIKey(_ key: String) async {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                apiKeyValidation = .networkError
                return
            }
            switch http.statusCode {
            case 200:
                apiKeyValidation = .valid
            case 401:
                apiKeyValidation = .invalid("Schlüssel von OpenAI abgelehnt (401). Auf platform.openai.com prüfen oder neu generieren.")
            case 429:
                apiKeyValidation = .quotaExceeded
            default:
                apiKeyValidation = .networkError
            }
        } catch {
            apiKeyValidation = .networkError
        }
    }

    /// Wird einmal beim Coordinator-Start aufgerufen, damit ein bereits
    /// im Keychain liegender Key direkt beim App-Launch validiert wird.
    func validateStoredAPIKeyOnLaunch() {
        if apiKey.isEmpty {
            apiKeyValidation = .empty
        } else {
            apiKeyValidation = .checking
            Task { await validateAPIKey(apiKey) }
        }
    }

    /// One-time migration: if the key still lives in UserDefaults (from
    /// earlier builds), copy it into the Keychain and wipe the plaintext
    /// copy. After migration, the Keychain is the sole source of truth.
    private static func loadInitialAPIKey() -> String {
        if let keychainValue = KeychainStore.get("openaiApiKey"), !keychainValue.isEmpty {
            return keychainValue
        }
        if let legacy = UserDefaults.standard.string(forKey: "openaiApiKey"), !legacy.isEmpty {
            KeychainStore.set(legacy, for: "openaiApiKey")
            UserDefaults.standard.removeObject(forKey: "openaiApiKey")
            return legacy
        }
        return ""
    }
    @Published var autoPaste: Bool = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var rewriteEnabled: Bool = UserDefaults.standard.object(forKey: "rewriteEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rewriteEnabled, forKey: "rewriteEnabled") }
    }

    /// Master-Switch aus dem Menu-Bar-Header. Wenn `true`, ignoriert der
    /// Coordinator neue Hotkey-Trigger (Recording-Start, Reverse-Translate,
    /// Sprachwechsel). Aktive Aufnahmen dürfen weiterlaufen und normal
    /// beendet werden, damit der User kein Audio verliert.
    @Published var isPaused: Bool = UserDefaults.standard.bool(forKey: "alva.isPaused") {
        didSet { UserDefaults.standard.set(isPaused, forKey: "alva.isPaused") }
    }

    // MARK: - Hotkey configuration

    @Published var standardHotkey: HotkeyConfig = AppCoordinator.loadHotkey(key: "standardHotkey", fallback: .defaultStandard) {
        didSet { AppCoordinator.saveHotkey(standardHotkey, key: "standardHotkey") }
    }
    @Published var politeHotkey: HotkeyConfig = AppCoordinator.loadHotkey(key: "politeHotkey", fallback: .defaultPolite) {
        didSet { AppCoordinator.saveHotkey(politeHotkey, key: "politeHotkey") }
    }
    @Published var messageHotkey: HotkeyConfig = AppCoordinator.loadHotkey(key: "messageHotkey", fallback: .defaultMessage) {
        didSet { AppCoordinator.saveHotkey(messageHotkey, key: "messageHotkey") }
    }

    /// Window in seconds for double-press toggle detection. 0.35 s is the
    /// original hardcoded value; user-adjustable via Settings → Hotkeys.
    @Published var doublePressWindow: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "doublePressWindow")
        return stored > 0 ? stored : 0.35
    }() {
        didSet { UserDefaults.standard.set(doublePressWindow, forKey: "doublePressWindow") }
    }

    /// Minimum recording length in seconds. User-adjustable in Settings.
    @Published var minimumRecordingDuration: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "minimumRecordingDuration")
        return stored > 0 ? stored : 0.4
    }() {
        didSet { UserDefaults.standard.set(minimumRecordingDuration, forKey: "minimumRecordingDuration") }
    }

    // MARK: - Language bindings (F-key → target language)

    @Published var languageBindings: [LanguageBinding] = AppCoordinator.loadLanguageBindings() {
        didSet { AppCoordinator.saveLanguageBindings(languageBindings) }
    }

    private static func defaultLanguageBindings() -> [LanguageBinding] {
        [
            LanguageBinding(isoCode: "en", fKey: 1),
            LanguageBinding(isoCode: "fr", fKey: 2),
            LanguageBinding(isoCode: "it", fKey: 3)
        ]
    }

    private static func loadLanguageBindings() -> [LanguageBinding] {
        guard let data = UserDefaults.standard.data(forKey: "languageBindings"),
              let decoded = try? JSONDecoder().decode([LanguageBinding].self, from: data) else {
            return defaultLanguageBindings()
        }
        return decoded
    }

    private static func saveLanguageBindings(_ list: [LanguageBinding]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "languageBindings")
        }
    }

    func resetLanguageBindings() {
        languageBindings = AppCoordinator.defaultLanguageBindings()
    }

    // MARK: - Reverse-Translate hotkey config
    //
    // The shortcut is HARDCODED to ⌃⌥⌘L ("L" for Language). Triple-modifier
    // combos are the only ones guaranteed to pass through every macOS app
    // including Word, Excel, Keynote, Mail, Safari, Finder — two-modifier
    // combos (⌃⌥Return, ⌥⇧Return, …) get swallowed by app-level bindings
    // (Word's context menu, browser line-breaks, etc.). There is no UI to
    // reconfigure this; the only user-facing control is the on/off switch.

    @Published var reverseTranslateEnabled: Bool = UserDefaults.standard.object(forKey: "reverseTranslateEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reverseTranslateEnabled, forKey: "reverseTranslateEnabled") }
    }

    /// Fixed modifier set: ⌃⌥⌘.
    let reverseTranslateModifiers = HotkeyConfig(
        command: true, option: true, control: true, shift: false
    )

    /// Fixed trigger key: kVK_ANSI_L (37). Same physical position on US
    /// (QWERTY) and German (QWERTZ) keyboards — the "L" key.
    let reverseTranslateKeyCode: UInt16 = 37

    /// One-time cleanup: earlier builds persisted `reverseTranslateModifiers`
    /// and `reverseTranslateKeyCode` in UserDefaults so users could remap
    /// the hotkey. That config is now stale; we remove the keys so nothing
    /// weird happens if we ever re-introduce them.
    static func migrateReverseTranslateDefaults() {
        UserDefaults.standard.removeObject(forKey: "reverseTranslateModifiers")
        UserDefaults.standard.removeObject(forKey: "reverseTranslateKeyCode")
    }

    // MARK: - Launch at login (macOS 13+ SMAppService)

    /// Whether ALVA-TEXT is registered to launch at login.
    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enable or disable launch-at-login. Silently logs on failure.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            objectWillChange.send()
        } catch {
            print("ALVA launch-at-login toggle failed:", error.localizedDescription)
        }
    }

    // MARK: - Transcript history

    @Published var history: [TranscriptEntry] = AppCoordinator.loadHistory() {
        didSet { AppCoordinator.saveHistory(history) }
    }

    @Published var historyEnabled: Bool = UserDefaults.standard.object(forKey: "historyEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(historyEnabled, forKey: "historyEnabled") }
    }

    /// Max entries kept locally. Older items fall off when adding new ones.
    static let maxHistoryEntries = 50

    private static func loadHistory() -> [TranscriptEntry] {
        guard let data = UserDefaults.standard.data(forKey: "history"),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveHistory(_ entries: [TranscriptEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "history")
        }
    }

    func appendHistory(_ entry: TranscriptEntry) {
        guard historyEnabled else { return }
        var updated = history
        updated.insert(entry, at: 0)
        if updated.count > AppCoordinator.maxHistoryEntries {
            updated = Array(updated.prefix(AppCoordinator.maxHistoryEntries))
        }
        history = updated
    }

    func clearHistory() {
        history = []
    }

    func deleteHistoryEntry(_ entry: TranscriptEntry) {
        history.removeAll { $0.id == entry.id }
    }

    /// Puts `entry.final` back into the clipboard. Optionally auto-pastes
    /// into whatever was frontmost before the history window opened.
    func replayHistoryEntry(_ entry: TranscriptEntry, autoPaste: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.final, forType: .string)
        if autoPaste, let app = targetApp {
            Task { await pasteService.paste(into: app) }
        }
    }

    // MARK: - Error display

    /// Last user-facing error message (e.g. network down, rate limit, invalid key).
    /// Cleared when a new successful operation completes.
    @Published var lastErrorMessage: String?
    @Published var lastErrorDate: Date?

    func recordError(_ message: String) {
        lastErrorMessage = message
        lastErrorDate = Date()
    }

    func clearError() {
        lastErrorMessage = nil
        lastErrorDate = nil
    }

    // MARK: - Cost tracking (OpenAI API spend)

    @Published var costEntries: [CostEntry] = AppCoordinator.loadCostEntries() {
        didSet { AppCoordinator.saveCostEntries(costEntries) }
    }

    static let maxCostEntries = 500

    private static func loadCostEntries() -> [CostEntry] {
        guard let data = UserDefaults.standard.data(forKey: "costEntries"),
              let decoded = try? JSONDecoder().decode([CostEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveCostEntries(_ entries: [CostEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "costEntries")
        }
    }

    func appendCostEntry(_ entry: CostEntry) {
        var updated = costEntries
        updated.insert(entry, at: 0)
        if updated.count > AppCoordinator.maxCostEntries {
            updated = Array(updated.prefix(AppCoordinator.maxCostEntries))
        }
        costEntries = updated
    }

    func clearCostEntries() {
        costEntries = []
    }

    /// Sum of all costs recorded today (midnight to midnight, local time).
    var costToday: Double {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        return costEntries
            .filter { $0.date >= startOfDay }
            .reduce(0) { $0 + $1.costUSD }
    }

    /// Sum of all costs from the first day of the current month.
    var costThisMonth: Double {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: Date())
        guard let startOfMonth = cal.date(from: components) else { return 0 }
        return costEntries
            .filter { $0.date >= startOfMonth }
            .reduce(0) { $0 + $1.costUSD }
    }

    /// Sum of all costs ever recorded (up to `maxCostEntries` retention).
    var costAllTime: Double {
        costEntries.reduce(0) { $0 + $1.costUSD }
    }

    private static func loadHotkey(key: String, fallback: HotkeyConfig) -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return fallback
        }
        return decoded
    }

    private static func saveHotkey(_ config: HotkeyConfig, key: String) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Reset all hotkey configs to their original built-in defaults
    /// (single-modifier layout: ⌃ / ⌥ / ⌘).
    func resetHotkeyDefaults() {
        standardHotkey = .defaultStandard
        politeHotkey = .defaultPolite
        messageHotkey = .defaultMessage
        doublePressWindow = 0.35
    }

    private let recorder = AudioRecorder()
    private lazy var hotkeys = HotkeyManager(delegate: self, configProvider: self)
    private let openAI = OpenAIService()
    let localWhisper = LocalWhisperTranscriber()
    private let pasteService = PasteService()

    /// User's chosen transcription backend. Default is local so the app
    /// works out of the box without an API key.
    @Published var transcriptionBackend: TranscriptionBackend = {
        if let raw = UserDefaults.standard.string(forKey: "transcriptionBackend"),
           let parsed = TranscriptionBackend(rawValue: raw) {
            return parsed
        }
        return .local
    }() {
        didSet {
            UserDefaults.standard.set(transcriptionBackend.rawValue, forKey: "transcriptionBackend")
            // v2.1.6.1: Erzwinge sofortiges Persistieren, damit die User-Wahl
            // einen Mac-Sleep / App-Nap überlebt, auch wenn macOS den
            // Prozess unmittelbar danach terminiert (#B-Wake).
            UserDefaults.standard.synchronize()
        }
    }

    /// v2.1.6.1: Re-Hydration nach Mac-Wake.
    ///
    /// macOS kann den App-Prozess während Sleep beenden (App Nap / Memory
    /// Pressure). Beim Wake wird die App neu gestartet, der Init-Closure
    /// liest UserDefaults frisch — was funktionieren SOLLTE, aber wir
    /// erzwingen es zusätzlich für den Fall, dass der App-Prozess durch-
    /// gehend läuft und nur Property-Reset-Effekte gab. Wird vom AppDelegate
    /// auf `NSWorkspace.didWakeNotification` getriggert.
    @MainActor
    func rehydrateUserPreferences() {
        if let raw = UserDefaults.standard.string(forKey: "transcriptionBackend"),
           let parsed = TranscriptionBackend(rawValue: raw),
           parsed != transcriptionBackend {
            transcriptionBackend = parsed
            print("ALVA wake: transcriptionBackend re-hydrated → \(parsed.rawValue)")
        }
    }

    private var recordingMode: HotkeyMode?
    private var recordingStartedAt: Date?
    /// If set, the current recording's output is additionally translated into
    /// this ISO code. Populated by `hotkeySelectLanguage(isoCode:)` when the
    /// user taps a configured F-key during the recording.
    private var recordingTargetLanguage: String?
    /// The app that was frontmost when the hotkey fired. We re-activate this
    /// one right before pasting so ⌘V lands where the user expects.
    private var targetApp: NSRunningApplication?
    private var isProcessing = false
    private var isReverseTranslating = false
    private var settingsWindowController: NSWindowController?

    /// Wenn gesetzt, springt die Settings-Ansicht beim naechsten Oeffnen
    /// in diesen Tab und setzt sich danach selbst zurueck. Wird z.B. beim
    /// ersten App-Start verwendet, um direkt den Account-Tab zu zeigen,
    /// falls die App noch nicht aktiviert ist.
    @Published var settingsRequestedTab: String?
    private var reverseTranslateWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    /// Polls the TCC permission state so the UI can update without user
    /// interaction. 2-second interval is a good balance between snappiness
    /// (user sees green right after granting) and CPU/I-O load.
    private var permissionPollTimer: Timer?

    func start() {
        hotkeys.start()
        refreshPermissionStates()
        startPermissionPolling()
        // v2.1.6: API-Key-Validation beim App-Start (#B14)
        validateStoredAPIKeyOnLaunch()
    }

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStates()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func refreshPermissionStates() {
        let ax = AXIsProcessTrusted()
        var permissionJustGranted = false

        if ax != accessibilityTrusted {
            let justGrantedAX = !accessibilityTrusted && ax
            accessibilityTrusted = ax
            if justGrantedAX {
                hotkeys.reinstallEventTapIfNeeded()
                print("ALVA: Accessibility granted at runtime")
                permissionJustGranted = true
            }
        }
        let im = pasteService.hasInputMonitoringPermission
        if im != inputMonitoringTrusted {
            let justGrantedIM = !inputMonitoringTrusted && im
            inputMonitoringTrusted = im
            if justGrantedIM {
                hotkeys.reinstallEventTapIfNeeded()
                print("ALVA: Input-Monitoring granted at runtime")
                permissionJustGranted = true
            }
        }

        // Auto-Restart nur dann triggern, wenn der User EXPLIZIT eine
        // Permission angefordert hat (über „Jetzt freigeben"-Button).
        // Reine Polling-Wechsel ohne User-Aktion (z.B. beim Erststart,
        // wenn AXIsProcessTrusted() seinen Cache erst synchronisiert)
        // dürfen NICHT zu Auto-Restart führen — das wäre eine Endlos-
        // schleife: Restart → frischer Prozess → Cache-Sync → Wechsel
        // detektiert → Restart → ...
        if permissionJustGranted && awaitingPermissionGrant && !isInRestartCooldown() {
            awaitingPermissionGrant = false
            scheduleAutoRestart()
        }
    }

    /// True während ein Auto-Restart bereits geplant ist — verhindert
    /// doppelten Auto-Restart, wenn beide Permissions kurz hintereinander
    /// erteilt werden.
    private var pendingAutoRestart: Bool = false

    /// Wird auf true gesetzt, wenn der User explizit eine Permission
    /// angefordert hat (Klick auf „Jetzt freigeben" / „Erlaubnis erteilen").
    /// Nach erfolgreicher Erteilung wieder auf false zurückgesetzt.
    /// Schützt vor Auto-Restart-Schleifen bei reinen Cache-Synchronisations-
    /// Wechseln im Polling.
    var awaitingPermissionGrant: Bool = false

    /// UserDefaults-Key für den Zeitpunkt des letzten Auto-Restarts.
    /// Dient als 30-Sekunden-Cooldown, damit selbst bei Race-Conditions
    /// keine Restart-Schleife entstehen kann.
    private static let lastAutoRestartKey = "ALVA.lastAutoRestart"

    /// True, wenn weniger als 30 s seit dem letzten Auto-Restart vergangen
    /// sind. In dieser Zeit blockt `refreshPermissionStates()` jeden
    /// weiteren Auto-Restart-Versuch.
    private func isInRestartCooldown() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastAutoRestartKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(last) < 30
    }

    /// Plant einen automatischen App-Restart, sobald eine Permission
    /// frisch erteilt wurde. Behebt das macOS-TCC-Cache-Problem
    /// (`AXIsProcessTrusted()` liefert für die laufende Prozess-Instanz
    /// oft den alten Wert) und stellt sicher, dass alle Subsysteme
    /// (CGEventTap, PasteService) mit dem aktualisierten Trust-Status
    /// frisch initialisiert werden.
    private func scheduleAutoRestart() {
        // v2.1.4: Auto-Restart deaktiviert.
        //
        // Hintergrund: Der frühere Auto-Restart sollte den macOS-TCC-Cache-
        // Bug umgehen, bei dem `AXIsProcessTrusted()` für den laufenden
        // Prozess auch nach erteilter Permission noch `false` liefert. In
        // der Praxis hat der Auto-Restart aber eine Endlosschleife erzeugt:
        // jeder neue Prozess sah AX wieder false, requestPermissions()
        // triggerte den TCC-Dialog, User klickte, Polling sah Wechsel,
        // Auto-Restart, Loop.
        //
        // Sauberere Variante: User wird per Banner gebeten, ALVA-TEXT
        // einmal manuell zu beenden und neu zu öffnen, falls der Toggle
        // bereits gesetzt ist aber die App es nicht erkennt.
        guard !pendingAutoRestart else { return }
        pendingAutoRestart = true
        print("ALVA: auto-restart suppressed (v2.1.4) — user must restart manually if permission state is stale")
        recordError("Erlaubnis registriert. Bitte ALVA-TEXT einmal manuell beenden und neu öffnen, damit macOS den Status synchronisiert.")
    }

    func requestPermissions() {
        // v2.1.4: TCC-Permissions (Bedienungshilfen, Eingabeüberwachung)
        // werden NICHT mehr automatisch beim App-Start angefragt.
        //
        // Vorher löste das einen System-Dialog aus, der mitten ins Onboarding
        // platzte und neben dem ALVA-Onboarding-Fenster + Settings-Fenster
        // ein drittes parallel laufendes UI-Element erzeugte. Ergebnis: Chaos.
        //
        // Neu: Die Onboarding-Pages „Bedienungshilfen" und „Eingabeüberwachung"
        // fragen die Permissions explizit an — durch User-Klick auf den Button
        // „Erlaubnis erteilen". Dadurch ein klarer, linearer Flow:
        // Schritt 1 Welcome → Schritt 2 Aktivierung → Schritt 3 OpenAI-Key →
        // Schritt 4 Bedienungshilfen → Schritt 5 Eingabeüberwachung.
        //
        // Mikrofon-Permission bleibt hier — der Aufruf ist non-blocking und
        // löst keinen System-Dialog aus, solange er nicht im Aufnahme-Pfad
        // genutzt wird.
        recorder.requestPermission()
    }

    func openSettings(initialTab: String? = nil) {
        // v2.1.4: Während Onboarding aktiv ist, KEIN zweites Settings-Window
        // öffnen — sonst läuft der User zwischen zwei Fenstern hin und her.
        // Stattdessen das Onboarding-Window in den Vordergrund holen.
        if let onb = onboardingWindowController?.window, onb.isVisible {
            print("ALVA: openSettings suppressed — onboarding active")
            NSApp.activate(ignoringOtherApps: true)
            onb.makeKeyAndOrderFront(nil)
            onb.orderFrontRegardless()
            return
        }

        // Wenn ein Wunsch-Tab mitkommt (z.B. "account" beim Erstlauf),
        // jetzt vormerken — SettingsView liest das im onAppear/onChange.
        if let initialTab {
            settingsRequestedTab = initialTab
        }

        // Remember which app was frontmost BEFORE we activate ourselves, so
        // "Test Paste" from the Settings window can paste back into it.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        }

        if settingsWindowController == nil {
            let contentView = SettingsView().environmentObject(self)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "ALVA-TEXT Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 560))
            window.isReleasedWhenClosed = false
            // Stay on top like the Onboarding window so it doesn't get
            // lost among the user's many other windows.
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace]
            window.hidesOnDeactivate = false
            // Auto-reset activation policy when the user closes Settings.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAuxWindowClosed()
                }
            }
            settingsWindowController = NSWindowController(window: window)
        }

        // Temporarily switch to .regular so the window can reliably become
        // key in an accessory app. finishOnboarding / handleAuxWindowClosed
        // flip it back to .accessory.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.center()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        settingsWindowController?.window?.orderFrontRegardless()
    }

    /// Called when Settings (or any aux window) closes. Drops Dock icon
    /// again unless another aux window is still open.
    private func handleAuxWindowClosed() {
        let anyOpen = [
            settingsWindowController?.window?.isVisible,
            onboardingWindowController?.window?.isVisible,
            historyWindowController?.window?.isVisible,
            reverseTranslateWindowController?.window?.isVisible
        ].contains(where: { $0 == true })
        if !anyOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func beginRecording(mode: HotkeyMode) {
        guard !isProcessing else { return }

        // v2.1.4: License-Gate. Ohne aktive Lizenz darf der Aufnahme-Pfad
        // gar nicht starten — sonst läuft die volle Funktionalität ohne
        // Aktivierung. Im Fehlerfall öffnet sich automatisch der Account-Tab,
        // damit der User den Onboarding-Schritt findet.
        guard LicenseState.shared.phase.isUsable else {
            print("ALVA: recording blocked — license not usable (phase=\(LicenseState.shared.phase))")
            recordError("ALVA-TEXT ist noch nicht aktiviert. Bitte im Account-Tab den 6-stelligen Code eintragen.")
            openSettings(initialTab: "account")
            return
        }

        // Snapshot the frontmost app BEFORE we start recording, so we know
        // where to paste once the transcript comes back. Skip our own app
        // (would happen if the Settings window was focused).
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        } else {
            targetApp = nil
        }

        recordingTargetLanguage = nil

        do {
            try recorder.startRecording()
            recordingMode = mode
            recordingStartedAt = Date()
            status = .recording
        } catch {
            print("ALVA recording start failed:", error.localizedDescription)
            status = .error
        }
    }

    /// Marks the currently running recording for translation into `isoCode`.
    /// Called from the hotkey manager when the user hits an F-key during
    /// recording. Last tap wins if the user taps multiple F-keys.
    func markCurrentRecordingLanguage(isoCode: String) {
        print("ALVA markCurrentRecordingLanguage(\(isoCode)) status=\(status.rawValue)")
        guard status == .recording else { return }
        recordingTargetLanguage = isoCode
    }

    func endRecordingAndProcess() {
        guard status == .recording, !isProcessing else { return }

        // Reject accidental taps shorter than the minimum duration.
        if let start = recordingStartedAt,
           Date().timeIntervalSince(start) < minimumRecordingDuration {
            if let url = try? recorder.stopRecording() {
                try? FileManager.default.removeItem(at: url)
            }
            recordingMode = nil
            recordingStartedAt = nil
            status = .idle
            return
        }

        isProcessing = true
        let mode = recordingMode
        let targetLanguage = recordingTargetLanguage

        Task {
            defer {
                isProcessing = false
                recordingMode = nil
                recordingStartedAt = nil
                recordingTargetLanguage = nil
                targetApp = nil
            }

            do {
                status = .transcribing
                let audioURL = try recorder.stopRecording()
                defer { try? FileManager.default.removeItem(at: audioURL) }

                // Shortcut: if the user wants English AND we'd be running
                // locally anyway, Whisper can translate directly inside the
                // transcription pass — no cloud call, no API key needed.
                let canUseLocalEnglishTranslate =
                    targetLanguage == "en"
                    && (transcriptionBackend == .local
                        || (transcriptionBackend == .auto && apiKey.isEmpty))
                    && localWhisper.isAvailable

                let transcript: String
                var localTranslateApplied = false
                if canUseLocalEnglishTranslate {
                    status = .translating
                    transcript = try await localWhisper.transcribe(
                        audioURL: audioURL,
                        language: "de",
                        translateToEnglish: true
                    )
                    localTranslateApplied = true
                } else {
                    transcript = try await runTranscription(audioURL: audioURL)
                }
                lastTranscript = transcript
                UserDefaults.standard.set(transcript, forKey: "lastTranscript")

                // Guard: if the user accidentally triggered recording or said
                // nothing, Whisper returns an empty or very short string. In
                // that case we must NOT forward it to the rewrite step —
                // GPT would respond with "Bitte teile mir den Text mit …"
                // and that junk would end up in the clipboard.
                let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTranscript.count < 2 {
                    status = .idle
                    return
                }

                var finalText = transcript

                // If Whisper already translated to English, we skip the
                // cloud-based translate step. Rewrite (polite/message) on
                // an English string wouldn't give sensible German output,
                // so we also skip those.
                if localTranslateApplied {
                    lastRewrittenText = finalText
                    UserDefaults.standard.set(finalText, forKey: "lastRewritten")
                } else {
                    // Rewrite / translate need a cloud call. Without an API
                    // key we quietly fall back to the plain transcript and
                    // flag the shortcoming so the user knows why Höflich /
                    // Nachricht didn't transform this round.
                    let needsCloud = (mode?.requiresCloud ?? false) || targetLanguage != nil
                    if needsCloud && apiKey.isEmpty {
                        recordError("Für Höflich, Nachricht und Sprach-Übersetzung (außer Englisch im Lokalbetrieb) wird ein OpenAI-Schlüssel benötigt. Ergebnis bleibt das reine Transkript.")
                    } else {
                        switch mode {
                        case .polite where rewriteEnabled:
                            status = .rewriting
                            let result = try await openAI.rewriteToPoliteGerman(text: transcript, apiKey: apiKey)
                            finalText = result.text
                            lastRewrittenText = finalText
                            UserDefaults.standard.set(finalText, forKey: "lastRewritten")
                            trackChatUsage(result.usage, kind: .rewrite)
                        case .message:
                            status = .rewriting
                            let result = try await openAI.rewriteAsAdaptiveMessage(text: transcript, apiKey: apiKey)
                            finalText = result.text
                            lastRewrittenText = finalText
                            UserDefaults.standard.set(finalText, forKey: "lastRewritten")
                            trackChatUsage(result.usage, kind: .rewrite)
                        default:
                            break
                        }

                        // Sprach-Override via F-Taste während Aufnahme.
                        if let iso = targetLanguage {
                            status = .translating
                            let result = try await openAI.translateText(to: iso, text: finalText, apiKey: apiKey)
                            finalText = result.text
                            lastRewrittenText = finalText
                            UserDefaults.standard.set(finalText, forKey: "lastRewritten")
                            trackChatUsage(result.usage, kind: .translate)
                        }
                    }
                }

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)

                if autoPaste {
                    let didPaste = await pasteService.paste(into: targetApp)
                    if didPaste {
                        status = .pasted
                    } else {
                        // No Accessibility permission — text is still in the
                        // clipboard, user needs to paste manually. Trigger
                        // the macOS system dialog so the user can grant it
                        // in one click instead of digging through Settings.
                        _ = pasteService.promptForAccessibility()
                        status = .needsAccessibility
                        recordError("Automatisches Einfügen fehlgeschlagen — Bedienungshilfen-Erlaubnis fehlt. Text liegt in der Zwischenablage.")
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        status = .idle
                        return
                    }
                } else {
                    status = .copied
                }

                // Append to history on success
                appendHistory(TranscriptEntry(
                    date: Date(),
                    modeRawValue: mode?.rawValue ?? "standard",
                    targetLanguageISO: targetLanguage,
                    original: transcript,
                    final: finalText
                ))
                clearError()

                try await Task.sleep(nanoseconds: 900_000_000)
                status = .idle
            } catch {
                print("ALVA error:", error.localizedDescription)
                recordError(friendlyErrorMessage(for: error))
                status = .error
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                status = .idle
            }
        }
    }

    /// Picks the right transcription backend for this recording and runs it.
    ///  * `.cloud` → OpenAI-Whisper (needs API key + internet)
    ///  * `.local` → WhisperKit on-device (no API key needed)
    ///  * `.auto`  → cloud if possible, else local fallback
    private func runTranscription(audioURL: URL) async throws -> String {
        switch transcriptionBackend {
        case .cloud:
            return try await runCloudTranscription(audioURL: audioURL)
        case .local:
            return try await runLocalTranscription(audioURL: audioURL)
        case .auto:
            if !apiKey.isEmpty {
                do {
                    return try await runCloudTranscription(audioURL: audioURL)
                } catch {
                    // Network / API down → fall back to local
                    print("ALVA auto-mode: cloud failed, falling back to local:", error.localizedDescription)
                    return try await runLocalTranscription(audioURL: audioURL)
                }
            } else {
                return try await runLocalTranscription(audioURL: audioURL)
            }
        }
    }

    private func runCloudTranscription(audioURL: URL) async throws -> String {
        let model = "gpt-4o-mini-transcribe"
        let result = try await openAI.transcribe(
            audioURL: audioURL,
            apiKey: apiKey,
            model: model,
            language: "de"
        )
        // Track transcription cost based on audio duration
        let seconds = recorder.lastDuration
        if seconds > 0 {
            let cost = OpenAIPricing.transcriptionCost(audioSeconds: seconds, model: model)
            appendCostEntry(CostEntry(
                date: Date(),
                kind: .transcribe,
                model: model,
                audioSeconds: seconds,
                promptTokens: nil,
                completionTokens: nil,
                costUSD: cost
            ))
        }
        return result
    }

    /// Logs a cost entry for a chat-completion call. Does nothing if usage
    /// is missing (shouldn't happen on successful OpenAI responses).
    private func trackChatUsage(_ usage: OpenAIUsage?, kind: CostEntry.Kind) {
        guard let usage else { return }
        let model = "gpt-4o-mini"
        let cost = OpenAIPricing.chatCost(
            model: model,
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens
        )
        appendCostEntry(CostEntry(
            date: Date(),
            kind: kind,
            model: model,
            audioSeconds: nil,
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            costUSD: cost
        ))
    }

    private func runLocalTranscription(audioURL: URL) async throws -> String {
        guard localWhisper.isAvailable else {
            throw LocalWhisperTranscriber.unavailableError
        }
        return try await localWhisper.transcribe(audioURL: audioURL, language: "de")
    }

    /// Translates raw NSError/URLError into a readable German sentence.
    private func friendlyErrorMessage(for error: Error) -> String {
        let ns = error as NSError
        // URLError (network)
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "Keine Internetverbindung."
            case NSURLErrorTimedOut:               return "OpenAI hat nicht innerhalb des Zeitlimits geantwortet."
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost:         return "OpenAI ist aktuell nicht erreichbar."
            default:                               return "Netzwerkfehler: \(ns.localizedDescription)"
            }
        }
        // Our own errors (ALVA_TEXT domain)
        if ns.domain == "ALVA_TEXT" {
            switch ns.code {
            case 401:  return "OpenAI-Schlüssel fehlt oder ist ungültig. Bitte in den Einstellungen prüfen."
            case 429:  return "OpenAI-Rate-Limit erreicht. Kurz warten und erneut versuchen."
            default:
                let body = ns.userInfo[NSLocalizedDescriptionKey] as? String ?? ns.localizedDescription
                // OpenAI error payloads often contain JSON — trim for readability.
                return "API-Fehler: \(body.prefix(200))"
            }
        }
        return "Fehler: \(ns.localizedDescription)"
    }

    // MARK: - Settings helpers

    func isAccessibilityTrusted() -> Bool {
        pasteService.hasAccessibilityPermission
    }

    func openAccessibilitySettings() {
        // User hat explizit eine Permission-Action ausgelöst — Flag setzen,
        // damit refreshPermissionStates() Auto-Restart triggern darf.
        awaitingPermissionGrant = true
        pasteService.openAccessibilitySettings()
    }

    /// v2.1.4: Cooldown für den TCC-Permission-Prompt.
    /// macOS' AXIsProcessTrustedWithOptions(prompt:true) zeigt den
    /// System-Dialog jedes Mal frisch an, wenn der Prozess sich noch als
    /// untrusted sieht — auch wenn der User in den Systemeinstellungen
    /// längst grünen Toggle gesetzt hat (TCC-Cache-Bug pro Prozess).
    /// Ohne Cooldown bombt sich der User mit Klicks auf den Button selbst
    /// mit Dialogen voll. 5 s Cooldown bricht die Schleife.
    private var lastAccessibilityPromptAt: Date?
    private static let accessibilityPromptCooldown: TimeInterval = 5.0

    /// Triggers the macOS system dialog that asks the user to enable
    /// Accessibility for ALVA-TEXT. Sets `awaitingPermissionGrant=true` —
    /// dadurch darf `refreshPermissionStates()` einen Auto-Restart triggern,
    /// sobald die Permission tatsächlich erteilt wird.
    /// Use this right after a rebuild or when
    /// the user clicks the "Erlaubnis anfordern" button.
    @discardableResult
    func requestAccessibilityPrompt() -> Bool {
        // Cooldown-Check: Wenn der Prompt erst kürzlich angezeigt wurde,
        // nicht erneut triggern — egal wie oft der User klickt.
        if let last = lastAccessibilityPromptAt,
           Date().timeIntervalSince(last) < AppCoordinator.accessibilityPromptCooldown {
            print("ALVA: requestAccessibilityPrompt suppressed (cooldown)")
            return AXIsProcessTrusted()
        }
        lastAccessibilityPromptAt = Date()
        awaitingPermissionGrant = true
        return pasteService.promptForAccessibility()
    }

    // MARK: - Input Monitoring (for F-key detection)

    func isInputMonitoringTrusted() -> Bool {
        pasteService.hasInputMonitoringPermission
    }

    @discardableResult
    func requestInputMonitoringPrompt() -> Bool {
        awaitingPermissionGrant = true
        return pasteService.requestInputMonitoringPermission()
    }

    func openInputMonitoringSettings() {
        awaitingPermissionGrant = true
        pasteService.openInputMonitoringSettings()
    }

    /// Beendet ALVA-TEXT und startet eine neue Instanz. Notwendiger
    /// Workaround für ein bekanntes macOS-Problem: `AXIsProcessTrusted()`
    /// cached den Trust-Status pro Prozess — wenn der User die
    /// Bedienungshilfen-Permission in den Systemeinstellungen erteilt,
    /// erkennt der laufende Prozess das oft nicht zuverlässig. Erst nach
    /// einem Neustart liest macOS den frischen TCC-Status.
    ///
    /// Mechanik: `open -n <bundlePath>` startet eine zweite Instanz; die
    /// `terminateOlderInstances()`-Logik im AppDelegate killt dann automatisch
    /// die alte. Als Sicherheits-Fallback terminieren wir uns selbst nach
    /// einer Sekunde, falls die neue Instanz zu langsam aufwacht.
    func restartApp() {
        // Systemeinstellungen-Fenster auch zumachen, falls es noch offen
        // ist — sonst bleibt es nach dem Auto-Restart als „loses Ende" auf
        // dem Bildschirm stehen. Wir killen System Settings nur dann, wenn
        // wir gerade einen Permission-bedingten Auto-Restart machen.
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == "com.apple.systempreferences" {
            app.terminate()
        }

        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        do {
            try task.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApp.terminate(nil)
            }
        } catch {
            print("ALVA: restartApp failed: \(error)")
        }
    }

    // MARK: - History window

    func openHistoryWindow() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        }

        if historyWindowController == nil {
            let view = HistoryView().environmentObject(self)
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "ALVA-TEXT — Verlauf"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 640, height: 520))
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace]
            window.hidesOnDeactivate = false
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAuxWindowClosed()
                }
            }
            historyWindowController = NSWindowController(window: window)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        historyWindowController?.showWindow(nil)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
        historyWindowController?.window?.orderFrontRegardless()
    }

    // MARK: - Onboarding

    var shouldShowOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    }

    /// True, wenn dem User noch Setup-Schritte fehlen (Bedienungshilfen
    /// oder Eingabeüberwachung nicht freigegeben). Wird im AccountTab
    /// nach erfolgreicher Aktivierung geprüft, um das Onboarding-Window
    /// erneut zu zeigen und den User aktiv zu den Systemfreigaben zu
    /// führen — verhindert die Falle „Aktivierung erfolgreich, alles
    /// grün, aber Hotkeys funktionieren nicht, weil Permissions fehlen".
    var hasIncompletePermissions: Bool {
        !accessibilityTrusted || !inputMonitoringTrusted
    }

    func showOnboardingIfNeeded() {
        guard shouldShowOnboarding else { return }
        showOnboardingWindow()
    }

    func showOnboardingWindow() {
        print("ALVA: showOnboardingWindow called")
        if onboardingWindowController == nil {
            let view = OnboardingView(onFinish: { [weak self] in
                self?.finishOnboarding()
            }).environmentObject(self)
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "ALVA-TEXT — Einrichtung"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 620, height: 500))
            window.isReleasedWhenClosed = false
            // Staying on top for accessory apps: use floating level so the
            // window can't get hidden by whichever app was frontmost.
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace]
            window.hidesOnDeactivate = false
            onboardingWindowController = NSWindowController(window: window)
        }
        // Accessory apps need explicit activation-policy bump for a real
        // window to become key. We flip to .regular for the duration of
        // onboarding, then back to .accessory in finishOnboarding().
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.center()
        onboardingWindowController?.showWindow(nil)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
        print("ALVA: onboarding window ordered front, visible=\(onboardingWindowController?.window?.isVisible ?? false)")
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        onboardingWindowController?.close()
        onboardingWindowController = nil
        // Back to menu-bar-only mode.
        NSApp.setActivationPolicy(.accessory)
    }

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
    }

    /// Puts a known string into the clipboard and attempts a paste into the
    /// app that was frontmost before the Settings window opened. Used by the
    /// "Test Paste" button in Settings.
    func runPasteSelfTest() {
        let testString = "✅ ALVA-TEXT test paste \(Date().formatted(date: .omitted, time: .standard))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testString, forType: .string)

        // We'll paste into whatever app was frontmost BEFORE Settings opened.
        let app = targetApp
        Task {
            let ok = await pasteService.paste(into: app)
            status = ok ? .pasted : .needsAccessibility
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            status = .idle
        }
    }
}

extension AppCoordinator: HotkeyManagerDelegate {
    func hotkeyStart(mode: HotkeyMode) {
        guard !isPaused else { return }
        beginRecording(mode: mode)
    }

    func hotkeyStop() {
        // Stop is always allowed — if a recording is in progress, we must
        // not leave the recorder running just because the user paused between
        // key-down and key-up.
        endRecordingAndProcess()
    }

    func hotkeySelectLanguage(isoCode: String) {
        guard !isPaused else { return }
        markCurrentRecordingLanguage(isoCode: isoCode)
    }

    func reverseTranslateRequested() {
        guard !isPaused else { return }
        startReverseTranslate()
    }
}

// MARK: - Reverse translate flow

extension AppCoordinator {
    /// Entry point called by the hotkey ⌃⌥D. Grabs the current selection,
    /// translates to German, shows the popup. Blocks re-entry while running
    /// and respects active recordings.
    func startReverseTranslate() {
        print("ALVA reverseTranslate: triggered (isProcessing=\(isProcessing) isReverse=\(isReverseTranslating) status=\(status.rawValue))")

        // v2.1.4: License-Gate. Reverse-Translate ist Cloud-only und braucht
        // eine aktive Lizenz, damit kein gratis-Konsum von Cloud-Funktionen
        // möglich ist.
        guard LicenseState.shared.phase.isUsable else {
            print("ALVA reverseTranslate: blocked — license not usable")
            recordError("ALVA-TEXT ist noch nicht aktiviert. Bitte im Account-Tab den 6-stelligen Code eintragen.")
            openSettings(initialTab: "account")
            return
        }

        // Ignore during any other activity. We intentionally do NOT gate
        // on `status` here — the user might press the hotkey right after
        // a recording finished, when status is briefly .pasted / .copied /
        // .needsAccessibility, and we don't want to swallow that.
        guard !isReverseTranslating, !isProcessing else {
            print("ALVA reverseTranslate: busy, ignoring")
            return
        }
        guard !apiKey.isEmpty else {
            print("ALVA reverseTranslate: no API key set")
            recordError("Rückwärtsübersetzung benötigt einen OpenAI-Schlüssel. Im Einstellungen-Tab „Allgemein\" hinterlegen.")
            status = .needsAccessibility  // reuse as "cannot" marker
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                status = .idle
            }
            return
        }

        isReverseTranslating = true
        status = .translating

        Task {
            defer {
                isReverseTranslating = false
                status = .idle
            }

            // 1. Snapshot the current clipboard so we can restore it afterwards.
            let previousClipboard = NSPasteboard.general.string(forType: .string)
            let previousChangeCount = NSPasteboard.general.changeCount

            // 2. Simulate ⌘C on the frontmost app.
            let ok = pasteService.simulateCommandC()
            print("ALVA reverseTranslate: simulateCommandC returned \(ok)")
            guard ok else {
                print("ALVA reverseTranslate: no Accessibility permission")
                recordError("⌘C konnte nicht simuliert werden — Bedienungshilfen-Freigabe fehlt.")
                status = .needsAccessibility
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return
            }

            // 3. Wait briefly for the copy to take effect, then read clipboard.
            try? await Task.sleep(nanoseconds: 250_000_000)
            let newChangeCount = NSPasteboard.general.changeCount
            let selectionRaw = NSPasteboard.general.string(forType: .string)
            print("ALVA reverseTranslate: clipboard changed=\(newChangeCount != previousChangeCount) content=\(selectionRaw?.prefix(40) ?? "nil")")
            guard newChangeCount != previousChangeCount,
                  let selection = selectionRaw,
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("ALVA reverseTranslate: nothing selected or clipboard unchanged")
                recordError("Keine Textauswahl erkannt. Markiere Text in der App, bevor du das Tastenkürzel drückst.")
                // Restore previous clipboard content.
                if let prev = previousClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
                status = .needsAccessibility
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                status = .idle
                return
            }

            // 4. Translate into German.
            let germanText: String
            do {
                let result = try await openAI.translateText(to: "de", text: selection, apiKey: apiKey)
                germanText = result.text
                // Track cost
                if let usage = result.usage {
                    let cost = OpenAIPricing.chatCost(
                        model: "gpt-4o-mini",
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens
                    )
                    appendCostEntry(CostEntry(
                        date: Date(),
                        kind: .translate,
                        model: "gpt-4o-mini",
                        audioSeconds: nil,
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        costUSD: cost
                    ))
                }
            } catch {
                print("ALVA reverseTranslate: translation failed:", error.localizedDescription)
                if let prev = previousClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
                status = .error
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return
            }

            // 5. Restore original clipboard (never overwrite it silently).
            NSPasteboard.general.clearContents()
            if let prev = previousClipboard {
                NSPasteboard.general.setString(prev, forType: .string)
            }

            // 6. Detect languages in the selection and open the popup.
            let originalChunks = LanguageCatalog.detectChunks(in: selection)
            showReverseTranslatePopup(originalChunks: originalChunks, translated: germanText)
        }
    }

    private func showReverseTranslatePopup(originalChunks: [LanguageChunk], translated: String) {
        print("ALVA reverseTranslate: showing popup with \(originalChunks.count) chunks, \(translated.count) chars translated")

        // STEP 1 — Flip to regular activation BEFORE creating the window.
        // Accessory apps (LSUIElement=true) can't reliably make a window key
        // if it was created while the app was still .accessory. The
        // onboarding/settings flows do this first-thing too.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // STEP 2 — Build the SwiftUI view + hosting controller.
        let view = ReverseTranslatePopup(
            originalChunks: originalChunks,
            translated: translated,
            onClose: { [weak self] in
                self?.reverseTranslateWindowController?.close()
                self?.reverseTranslateWindowController = nil
            }
        )
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]

        // STEP 3 — Build the window in "lightbox" style: no visible title
        // bar, no traffic lights, slim padding. Escape closes (handled in
        // SwiftUI via `.onExitCommand`). `.titled` stays in the style mask
        // so the window can become key — without `.titled`, SwiftUI's
        // exit-command handler never receives the event. We just hide all
        // title-bar affordances visually.
        let contentSize = NSSize(width: 520, height: 360)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = host
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.hidesOnDeactivate = false

        // Center on whichever screen is currently active (main screen's
        // visibleFrame, not frame — excludes menu bar and Dock).
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - contentSize.width / 2,
                y: visible.midY - contentSize.height / 2
            )
            window.setFrame(
                NSRect(origin: origin, size: contentSize),
                display: true
            )
        }

        // Auto-reset activation policy to .accessory when popup closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAuxWindowClosed()
            }
        }

        // Click-outside-to-close: if the user clicks anywhere else (other
        // app, desktop, our own menu-bar icon), the popup loses key status
        // → we close it. This is the expected UX for a lightbox.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reverseTranslateWindowController?.close()
                self?.reverseTranslateWindowController = nil
            }
        }

        // STEP 4 — Show & surface.
        reverseTranslateWindowController = NSWindowController(window: window)
        reverseTranslateWindowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        let screenFrame = NSScreen.main?.frame ?? .zero
        print("ALVA reverseTranslate: popup visible=\(window.isVisible) frame=\(window.frame) screen=\(screenFrame)")
    }
}

extension AppCoordinator: HotkeyConfigProvider {}
