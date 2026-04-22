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

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var lastTranscript: String = UserDefaults.standard.string(forKey: "lastTranscript") ?? ""
    @Published var lastRewrittenText: String = UserDefaults.standard.string(forKey: "lastRewritten") ?? ""
    @Published var apiKey: String = AppCoordinator.loadInitialAPIKey() {
        didSet { KeychainStore.set(apiKey, for: "openaiApiKey") }
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

    @Published var reverseTranslateEnabled: Bool = UserDefaults.standard.object(forKey: "reverseTranslateEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reverseTranslateEnabled, forKey: "reverseTranslateEnabled") }
    }

    @Published var reverseTranslateModifiers: HotkeyConfig = AppCoordinator.loadHotkey(
        key: "reverseTranslateModifiers",
        fallback: HotkeyConfig(command: false, option: true, control: true, shift: false)  // default ⌃⌥
    ) {
        didSet { AppCoordinator.saveHotkey(reverseTranslateModifiers, key: "reverseTranslateModifiers") }
    }

    /// Default trigger is Return (kVK_Return = 36). Works identically on
    /// every keyboard layout (US, DE, FR, …) and doesn't collide with
    /// common macOS shortcuts. Users with other preferences can pick from
    /// the `TriggerKeyCatalog` in Settings.
    @Published var reverseTranslateKeyCode: UInt16 = {
        if let raw = UserDefaults.standard.object(forKey: "reverseTranslateKeyCode") as? Int {
            return UInt16(raw)
        }
        return 36 // kVK_Return
    }() {
        didSet { UserDefaults.standard.set(Int(reverseTranslateKeyCode), forKey: "reverseTranslateKeyCode") }
    }

    func resetReverseTranslateDefaults() {
        reverseTranslateEnabled = true
        reverseTranslateModifiers = HotkeyConfig(command: false, option: true, control: true, shift: false)
        reverseTranslateKeyCode = 36 // Return
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
    private let pasteService = PasteService()

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
    private var reverseTranslateWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?

    func start() {
        hotkeys.start()
    }

    func requestPermissions() {
        recorder.requestPermission()

        if !AXIsProcessTrusted() {
            let didPrompt = UserDefaults.standard.bool(forKey: "didPromptAccessibility")
            if !didPrompt {
                let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                UserDefaults.standard.set(true, forKey: "didPromptAccessibility")
            }
        }

        // Input-Monitoring is needed for CGEventTap to receive key-down
        // events in macOS 10.15+. Prompt the first time; afterwards the
        // user has to enable it manually in System Settings.
        if !pasteService.hasInputMonitoringPermission {
            _ = pasteService.requestInputMonitoringPermission()
        }
    }

    func openSettings() {
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
            window.center()

            settingsWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func beginRecording(mode: HotkeyMode) {
        guard !isProcessing else { return }

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

                let transcript = try await openAI.transcribe(
                    audioURL: audioURL,
                    apiKey: apiKey,
                    model: "gpt-4o-mini-transcribe",
                    language: "de"
                )
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
                switch mode {
                case .polite where rewriteEnabled:
                    status = .rewriting
                    finalText = try await openAI.rewriteToPoliteGerman(text: transcript, apiKey: apiKey)
                    lastRewrittenText = finalText
                    UserDefaults.standard.set(finalText, forKey: "lastRewritten")
                case .message:
                    status = .rewriting
                    finalText = try await openAI.rewriteAsAdaptiveMessage(text: transcript, apiKey: apiKey)
                    lastRewrittenText = finalText
                    UserDefaults.standard.set(finalText, forKey: "lastRewritten")
                default:
                    break
                }

                // If the user tapped an F-key for a language binding during
                // recording, translate the final output into that language.
                // The German version is DISCARDED (per Alper's preference).
                if let iso = targetLanguage {
                    status = .translating
                    finalText = try await openAI.translateText(to: iso, text: finalText, apiKey: apiKey)
                    lastRewrittenText = finalText
                    UserDefaults.standard.set(finalText, forKey: "lastRewritten")
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
        pasteService.openAccessibilitySettings()
    }

    /// Triggers the macOS system dialog that asks the user to enable
    /// Accessibility for ALVA-TEXT. Use this right after a rebuild or when
    /// the user clicks the "Erlaubnis anfordern" button.
    @discardableResult
    func requestAccessibilityPrompt() -> Bool {
        pasteService.promptForAccessibility()
    }

    // MARK: - Input Monitoring (for F-key detection)

    func isInputMonitoringTrusted() -> Bool {
        pasteService.hasInputMonitoringPermission
    }

    @discardableResult
    func requestInputMonitoringPrompt() -> Bool {
        pasteService.requestInputMonitoringPermission()
    }

    func openInputMonitoringSettings() {
        pasteService.openInputMonitoringSettings()
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
            historyWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindowController?.showWindow(nil)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Onboarding

    var shouldShowOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    }

    func showOnboardingIfNeeded() {
        guard shouldShowOnboarding else { return }
        showOnboardingWindow()
    }

    func showOnboardingWindow() {
        if onboardingWindowController == nil {
            let view = OnboardingView(onFinish: { [weak self] in
                self?.finishOnboarding()
            }).environmentObject(self)
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "ALVA-TEXT — Einrichtung"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 620, height: 500))
            window.center()
            window.isReleasedWhenClosed = false
            onboardingWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.showWindow(nil)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        onboardingWindowController?.close()
        onboardingWindowController = nil
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
        beginRecording(mode: mode)
    }

    func hotkeyStop() {
        endRecordingAndProcess()
    }

    func hotkeySelectLanguage(isoCode: String) {
        markCurrentRecordingLanguage(isoCode: isoCode)
    }

    func reverseTranslateRequested() {
        startReverseTranslate()
    }
}

// MARK: - Reverse translate flow

extension AppCoordinator {
    /// Entry point called by the hotkey ⌃⌥D. Grabs the current selection,
    /// translates to German, shows the popup. Blocks re-entry while running
    /// and respects active recordings.
    func startReverseTranslate() {
        // Ignore during any other activity.
        guard !isReverseTranslating, !isProcessing else { return }
        guard status == .idle || status == .pasted || status == .copied else { return }
        guard !apiKey.isEmpty else {
            print("ALVA reverseTranslate: no API key set")
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
            guard ok else {
                print("ALVA reverseTranslate: no Accessibility permission")
                status = .needsAccessibility
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return
            }

            // 3. Wait briefly for the copy to take effect, then read clipboard.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard NSPasteboard.general.changeCount != previousChangeCount,
                  let selection = NSPasteboard.general.string(forType: .string),
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("ALVA reverseTranslate: nothing selected or clipboard unchanged")
                // Restore previous clipboard content.
                if let prev = previousClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
                return
            }

            // 4. Translate into German.
            let germanText: String
            do {
                germanText = try await openAI.translateText(to: "de", text: selection, apiKey: apiKey)
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

        let window = NSWindow(contentViewController: host)
        // Title bar is suppressed: transparent + title hidden + traffic
        // lights hidden. Still a .titled window so it can become key and
        // accept keyboard shortcuts like Escape.
        window.styleMask = [.titled, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(NSSize(width: 560, height: 440))
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false

        reverseTranslateWindowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        reverseTranslateWindowController?.showWindow(nil)
        reverseTranslateWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

extension AppCoordinator: HotkeyConfigProvider {}
