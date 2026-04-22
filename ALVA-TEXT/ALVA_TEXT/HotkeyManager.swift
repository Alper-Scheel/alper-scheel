import AppKit
import CoreGraphics
import Foundation
import NaturalLanguage

/// Top-level C-convention callback for the CGEventTap.
/// Swift @convention(c) closures can't capture context, so we round-trip
/// the `HotkeyManager` via the userInfo pointer.
private func alvaEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        manager.handleTapEvent(type: type, event: event)
    }
}

/// A single user-configured binding between a function key (F1-F12) and a
/// target language. While a recording is running, tapping the F-key flips
/// the current recording into that language — the final output gets
/// translated accordingly.
struct LanguageBinding: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var isoCode: String   // e.g. "en", "fr", "it"
    var fKey: Int         // 1-12

    var displayName: String {
        LanguageCatalog.germanName(for: isoCode)
    }
}

/// Curated list of languages and two name variants (German for UI, English
/// for translator prompts).
enum LanguageCatalog {
    /// Pairs of (isoCode, German UI label).
    static let supported: [(iso: String, name: String)] = [
        ("en", "Englisch"),
        ("en-GB", "Englisch (UK)"),
        ("fr", "Französisch"),
        ("it", "Italienisch"),
        ("es", "Spanisch"),
        ("pt", "Portugiesisch"),
        ("nl", "Niederländisch"),
        ("pl", "Polnisch"),
        ("ru", "Russisch"),
        ("tr", "Türkisch"),
        ("sv", "Schwedisch"),
        ("da", "Dänisch"),
        ("no", "Norwegisch"),
        ("fi", "Finnisch"),
        ("el", "Griechisch"),
        ("cs", "Tschechisch"),
        ("hu", "Ungarisch"),
        ("ro", "Rumänisch"),
        ("ja", "Japanisch"),
        ("zh", "Chinesisch (Mandarin, vereinfacht)"),
        ("yue", "Kantonesisch"),
        ("ko", "Koreanisch"),
        ("ar", "Arabisch"),
        ("he", "Hebräisch"),
        ("th", "Thailändisch"),
        ("uk", "Ukrainisch")
    ]

    static func germanName(for iso: String) -> String {
        supported.first { $0.iso == iso }?.name ?? iso
    }

    /// English language name for translator prompts. Falls back to the ISO
    /// code if unknown.
    static func englishName(for iso: String) -> String {
        switch iso {
        case "en":    return "English"
        case "en-GB": return "British English"
        case "fr":    return "French"
        case "it":    return "Italian"
        case "es":    return "Spanish"
        case "pt":    return "Portuguese"
        case "nl":    return "Dutch"
        case "pl":    return "Polish"
        case "ru":    return "Russian"
        case "tr":    return "Turkish"
        case "sv":    return "Swedish"
        case "da":    return "Danish"
        case "no":    return "Norwegian"
        case "fi":    return "Finnish"
        case "el":    return "Greek"
        case "cs":    return "Czech"
        case "hu":    return "Hungarian"
        case "ro":    return "Romanian"
        case "ja":    return "Japanese"
        case "zh":    return "Simplified Chinese (Mandarin)"
        case "yue":   return "Cantonese (traditional Chinese characters)"
        case "ko":    return "Korean"
        case "ar":    return "Arabic"
        case "he":    return "Hebrew"
        case "th":    return "Thai"
        case "uk":    return "Ukrainian"
        default:      return iso
        }
    }
}

/// A slice of text that is (per automatic detection) in one language.
/// Shown as a separate labelled box in the reverse-translate popup.
struct LanguageChunk: Identifiable, Equatable {
    let id = UUID()
    let isoCode: String
    let text: String

    /// Localised display name, e.g. "Französisch". Falls back to the ISO
    /// code if the language isn't in our curated catalog.
    var displayName: String {
        switch isoCode {
        case "und":     return "Unbekannt"
        default:        return LanguageCatalog.germanName(for: isoCode)
        }
    }
}

extension LanguageCatalog {
    /// Splits `text` into language-homogeneous chunks. Consecutive
    /// paragraphs of the same dominant language are merged back together.
    static func detectChunks(in text: String) -> [LanguageChunk] {
        let paragraphs = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return [] }

        var chunks: [LanguageChunk] = []
        for paragraph in paragraphs {
            let iso = dominantLanguageISO(of: paragraph)
            if let last = chunks.last, last.isoCode == iso {
                chunks[chunks.count - 1] = LanguageChunk(
                    isoCode: iso,
                    text: last.text + "\n" + paragraph
                )
            } else {
                chunks.append(LanguageChunk(isoCode: iso, text: paragraph))
            }
        }
        return chunks
    }

    /// Returns an ISO 639-1 code for the dominant language of `text`, or
    /// "und" if detection is inconclusive. Regional suffixes like
    /// "zh-Hans" are stripped down to "zh".
    private static func dominantLanguageISO(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return "und" }
        let raw = dominant.rawValue
        return raw.components(separatedBy: "-").first ?? raw
    }
}

/// Curated catalog of "trigger keys" the user can pick for the
/// reverse-translate hotkey. Labels are the PHYSICAL key position that
/// works on both US and German keyboards. Letters are last resort.
enum TriggerKeyCatalog {
    /// Pairs of (virtual keycode, user-facing label).
    static let options: [(code: UInt16, label: String)] = [
        (36, "Return / Enter"),        // kVK_Return
        (49, "Leertaste"),             // kVK_Space (konfliktet mit macOS ⌃⌥Space)
        (47, ". (Punkt)"),             // kVK_ANSI_Period — identische Position DE/US
        (43, ", (Komma)"),             // kVK_ANSI_Comma — identische Position DE/US
        (51, "Löschen (Backspace)"),   // kVK_Delete
        (48, "Tabulator"),             // kVK_Tab
        // Letters – meist ergonomisch, aber achte auf App-Shortcuts
        (2,  "D"),   // kVK_ANSI_D
        (17, "T"),   // kVK_ANSI_T
        (16, "Y"),   // kVK_ANSI_Y — auf DE = Z
        (32, "U"),   // kVK_ANSI_U
        (4,  "H"),   // kVK_ANSI_H
        (38, "J"),   // kVK_ANSI_J
        (40, "K"),   // kVK_ANSI_K
    ]

    static func label(for code: UInt16) -> String {
        options.first(where: { $0.code == code })?.label ?? "?"
    }
}

/// Translates a macOS virtual keycode to its F-key number (1…12) or `nil`.
func fKeyNumber(forKeyCode keyCode: UInt16) -> Int? {
    switch keyCode {
    case 0x7A: return 1   // kVK_F1
    case 0x78: return 2   // kVK_F2
    case 0x63: return 3   // kVK_F3
    case 0x76: return 4   // kVK_F4
    case 0x60: return 5   // kVK_F5
    case 0x61: return 6   // kVK_F6
    case 0x62: return 7   // kVK_F7
    case 0x64: return 8   // kVK_F8
    case 0x65: return 9   // kVK_F9
    case 0x6D: return 10  // kVK_F10
    case 0x67: return 11  // kVK_F11
    case 0x6F: return 12  // kVK_F12
    default:   return nil
    }
}

/// User-configurable modifier combination for a single hotkey mode.
/// Encoded as simple booleans so it can be bound directly to SwiftUI
/// toggles and round-tripped through UserDefaults.
struct HotkeyConfig: Codable, Equatable {
    var command: Bool = false
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false

    /// `NSEvent.ModifierFlags` representation for matching against events.
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        if shift { flags.insert(.shift) }
        return flags
    }

    /// Human-readable symbol string (e.g. `⌃⌥`). Used in the menu bar and
    /// settings summary.
    var displaySymbols: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift  { s += "⇧" }
        if command { s += "⌘" }
        return s.isEmpty ? "—" : s
    }

    /// At least one modifier must be set or the hotkey can never fire.
    var isValid: Bool {
        command || option || control || shift
    }

    // Alper's preferred single-modifier defaults (2026-04-21):
    //  ⌃ Control → Standard (direct transcript)
    //  ⌥ Option  → Polite (rewrite)
    //  ⌘ Command → Message (adaptive chat/social-media style)
    static let defaultStandard = HotkeyConfig(command: false, option: false, control: true,  shift: false)
    static let defaultPolite   = HotkeyConfig(command: false, option: true,  control: false, shift: false)
    static let defaultMessage  = HotkeyConfig(command: true,  option: false, control: false, shift: false)
}

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyStart(mode: HotkeyMode)
    func hotkeyStop()
    /// The user tapped a configured language F-key while a recording is in
    /// progress. The coordinator should remember the ISO code and translate
    /// the final output at the end of the recording.
    func hotkeySelectLanguage(isoCode: String)
    /// The user pressed the reverse-translate hotkey (⌃⌥D). The coordinator
    /// should grab the current selection and show a German translation in
    /// a floating popup. Fires only OUTSIDE an active recording.
    func reverseTranslateRequested()
}

@MainActor
protocol HotkeyConfigProvider: AnyObject {
    var standardHotkey: HotkeyConfig { get }
    var politeHotkey: HotkeyConfig { get }
    var messageHotkey: HotkeyConfig { get }
    var doublePressWindow: TimeInterval { get }
    var languageBindings: [LanguageBinding] { get }
    /// Modifier set for the reverse-translate hotkey (e.g. `[⌃, ⌥]`).
    var reverseTranslateModifiers: HotkeyConfig { get }
    /// Virtual keycode of the reverse-translate trigger key (e.g. 49 = Space).
    var reverseTranslateKeyCode: UInt16 { get }
    /// Global on/off switch for the reverse-translate hotkey.
    var reverseTranslateEnabled: Bool { get }
}

@MainActor
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    weak var configProvider: HotkeyConfigProvider?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Low-level keyboard tap. Installed in addition to the NSEvent
    /// flagsChanged monitors because:
    ///  * NSEvent's global `.keyDown` monitor is passive — it can observe
    ///    events but not consume them, and it often misses F-keys that the
    ///    HID layer has rerouted to media actions.
    ///  * A session-level CGEventTap sits one layer deeper, sees F-keys
    ///    whenever they come through as regular key events (Fn held or
    ///    "standard function keys" preference), and — crucially — can
    ///    consume them so they don't trigger brightness/volume/etc. while
    ///    we're recording.
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    private var isHoldRecording = false
    private var holdMode: HotkeyMode?

    private var toggleRecording = false
    private var toggleMode: HotkeyMode?

    private var standardTapTimes: [Date] = []
    private var politeTapTimes: [Date] = []
    private var messageTapTimes: [Date] = []

    private var wasStandardComboDown = false
    private var wasPoliteComboDown = false
    private var wasMessageComboDown = false

    init(delegate: HotkeyManagerDelegate?, configProvider: HotkeyConfigProvider?) {
        self.delegate = delegate
        self.configProvider = configProvider
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event: event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event: event)
            }
            return event
        }

        installEventTap()
    }

    func stop() {
        for monitor in [globalMonitor, localMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalMonitor = nil
        localMonitor = nil
        removeEventTap()
    }

    // MARK: - CGEventTap

    private func installEventTap() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Constraints:
        //  - `.cghidEventTap` would need root privileges → unavailable to
        //    a user-space app. We use `.cgSessionEventTap`.
        //  - `.listenOnly` is passive observation — we can't swallow
        //    events, but we don't need to. The user always presses Fn +
        //    F-Key which keeps the default media behaviour intact and
        //    additionally delivers the F-key as keyCode 122/120/… to us.
        //  - Any-key-stop's key may type a single character into the
        //    target app; the subsequent paste overwrites/extends it.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: alvaEventTapCallback,
            userInfo: refcon
        ) else {
            print("ALVA: CGEvent.tapCreate failed — Accessibility permission is missing or the system denied the tap. Grant Accessibility in Settings → Bedienungshilfen.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapSource = source
        print("ALVA: CGEventTap installed for .keyDown")
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
    }

    /// Called from the C-level tap callback on the main run loop.
    /// Return value: pass-through event, or `nil` to consume.
    fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS may disable our tap if a callback takes too long. Re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("ALVA: event tap re-enabled after \(type)")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Reverse-translate hotkey: configurable modifier combo + key.
        // Fires only when we're NOT recording and the config is enabled.
        if !isHoldRecording && !toggleRecording,
           let provider = configProvider,
           provider.reverseTranslateEnabled,
           keyCode == provider.reverseTranslateKeyCode,
           provider.reverseTranslateModifiers.isValid {
            let wanted = provider.reverseTranslateModifiers
            let f = event.flags
            let hasCtrl  = f.contains(.maskControl)
            let hasOpt   = f.contains(.maskAlternate)
            let hasCmd   = f.contains(.maskCommand)
            let hasShift = f.contains(.maskShift)
            if hasCtrl == wanted.control,
               hasOpt  == wanted.option,
               hasCmd  == wanted.command,
               hasShift == wanted.shift {
                print("ALVA tap → reverse translate triggered (\(wanted.displaySymbols)+\(TriggerKeyCatalog.label(for: keyCode)))")
                delegate?.reverseTranslateRequested()
                return Unmanaged.passUnretained(event)
            }
        }

        // Ignore remaining keystrokes when there's no active recording.
        guard isHoldRecording || toggleRecording else {
            return Unmanaged.passUnretained(event)
        }

        print("ALVA tap keyDown keyCode=\(keyCode) hold=\(isHoldRecording) toggle=\(toggleRecording)")

        // 1. F-key → language binding
        //    (In listenOnly mode we can't consume; the F-key continues its
        //    normal path. That's fine because when the user pressed Fn+F1
        //    or enabled standard-F-keys, F-keys don't trigger brightness.)
        if let fKey = fKeyNumber(forKeyCode: keyCode) {
            if let provider = configProvider,
               let binding = provider.languageBindings.first(where: { $0.fKey == fKey }) {
                print("ALVA tap → language binding \(binding.isoCode)")
                delegate?.hotkeySelectLanguage(isoCode: binding.isoCode)
            } else {
                print("ALVA tap → F\(fKey) has no binding")
            }
            return Unmanaged.passUnretained(event)
        }

        // 2. Toggle recording: any non-F key stops it. We do NOT consume so
        // the key still reaches the target app (where the user was typing).
        if toggleRecording {
            print("ALVA tap → stopping toggle")
            toggleRecording = false
            toggleMode = nil
            clearAllTapHistories()
            delegate?.hotkeyStop()
        }

        // 3. Hold recording: ignore other keys.
        return Unmanaged.passUnretained(event)
    }


    /// Mask of modifier flags we actually care about for hotkey matching.
    /// `.function` (Fn) is intentionally EXCLUDED so users can tap Fn+F1
    /// while holding their recording hotkey without the Fn press breaking
    /// the hold. `.capsLock`, `.numericPad` and `.help` are also excluded.
    private static let relevantModifierMask: NSEvent.ModifierFlags =
        [.shift, .control, .option, .command]

    private func handle(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevantModifierMask)

        guard let provider = configProvider else { return }
        let standardMask = provider.standardHotkey.modifierFlags
        let politeMask   = provider.politeHotkey.modifierFlags
        let messageMask  = provider.messageHotkey.modifierFlags

        // Exact-match comparisons. Non-overlapping combos auto-discriminate.
        let rawStandard = !standardMask.isEmpty && flags == standardMask
        let rawPolite   = !politeMask.isEmpty   && flags == politeMask
        let rawMessage  = !messageMask.isEmpty  && flags == messageMask

        // Priority when two modes share the same mask: message > polite > standard.
        let messagePressed  = rawMessage
        let politePressed   = rawPolite   && !(rawMessage && politeMask == messageMask)
        let standardPressed = rawStandard && !(rawMessage && standardMask == messageMask)
                                          && !(rawPolite  && standardMask == politeMask)

        // Snapshot previous combo state, then update immediately so later
        // branches see a consistent view.
        let prevStandardDown = wasStandardComboDown
        let prevPoliteDown   = wasPoliteComboDown
        let prevMessageDown  = wasMessageComboDown
        wasStandardComboDown = standardPressed
        wasPoliteComboDown   = politePressed
        wasMessageComboDown  = messagePressed

        let standardRising = !prevStandardDown && standardPressed
        let politeRising   = !prevPoliteDown   && politePressed
        let messageRising  = !prevMessageDown  && messagePressed

        // Priority 1 — Toggle-Mode STOP.
        // If we're already recording in toggle mode, ONLY the same combo's
        // rising edge counts, and it stops the toggle. This MUST run before
        // tap registration, otherwise the stop-press would start a new toggle.
        if toggleRecording, let mode = toggleMode {
            let stopRising: Bool
            switch mode {
            case .standard: stopRising = standardRising
            case .polite:   stopRising = politeRising
            case .message:  stopRising = messageRising
            }
            if stopRising {
                toggleRecording = false
                toggleMode = nil
                clearAllTapHistories()
                delegate?.hotkeyStop()
            }
            return
        }

        // Priority 2 — Tap registration. May start a new toggle via `toggle(for:)`.
        if standardRising { registerTap(group: .standard, provider: provider) }
        if politeRising   { registerTap(group: .polite,   provider: provider) }
        if messageRising  { registerTap(group: .message,  provider: provider) }

        // If a toggle was just started by the tap-count reaching 2, skip the
        // hold pipeline so the press isn't interpreted as a hold-start too.
        if toggleRecording { return }

        // Priority 3 — Hold handling (press-to-record / release-to-stop).
        handleHoldModes(standard: standardPressed, polite: politePressed, message: messagePressed)
    }

    private func clearAllTapHistories() {
        standardTapTimes.removeAll()
        politeTapTimes.removeAll()
        messageTapTimes.removeAll()
    }

    private enum TapGroup {
        case standard
        case polite
        case message
    }

    private func registerTap(group: TapGroup, provider: HotkeyConfigProvider) {
        let now = Date()
        let window = provider.doublePressWindow
        switch group {
        case .standard:
            standardTapTimes.append(now)
            standardTapTimes = standardTapTimes.filter { now.timeIntervalSince($0) <= window }
            if standardTapTimes.count >= 2 {
                standardTapTimes.removeAll()
                toggle(for: .standard)
            }
        case .polite:
            politeTapTimes.append(now)
            politeTapTimes = politeTapTimes.filter { now.timeIntervalSince($0) <= window }
            if politeTapTimes.count >= 2 {
                politeTapTimes.removeAll()
                toggle(for: .polite)
            }
        case .message:
            messageTapTimes.append(now)
            messageTapTimes = messageTapTimes.filter { now.timeIntervalSince($0) <= window }
            if messageTapTimes.count >= 2 {
                messageTapTimes.removeAll()
                toggle(for: .message)
            }
        }
    }


    private func handleHoldModes(standard: Bool, polite: Bool, message: Bool) {
        if toggleRecording { return }

        if !isHoldRecording {
            if standard {
                isHoldRecording = true
                holdMode = .standard
                delegate?.hotkeyStart(mode: .standard)
            } else if polite {
                isHoldRecording = true
                holdMode = .polite
                delegate?.hotkeyStart(mode: .polite)
            } else if message {
                isHoldRecording = true
                holdMode = .message
                delegate?.hotkeyStart(mode: .message)
            }
            return
        }

        guard let holdMode else { return }
        let stillPressed: Bool
        switch holdMode {
        case .standard:  stillPressed = standard
        case .polite:    stillPressed = polite
        case .message: stillPressed = message
        }
        if !stillPressed {
            isHoldRecording = false
            self.holdMode = nil
            delegate?.hotkeyStop()
        }
    }

    private func toggle(for mode: HotkeyMode) {
        if toggleRecording {
            guard toggleMode == mode else { return }
            toggleRecording = false
            toggleMode = nil
            delegate?.hotkeyStop()
        } else {
            toggleRecording = true
            toggleMode = mode
            isHoldRecording = false
            holdMode = nil
            delegate?.hotkeyStart(mode: mode)
        }
    }
}
