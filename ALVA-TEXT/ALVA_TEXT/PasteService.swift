import AppKit
import ApplicationServices
import IOKit.hid

/// Simulates a ⌘V keystroke so the transcribed text lands in the app the
/// user was typing into when they triggered the hotkey. Handles three issues
/// we hit in practice:
///   1. Accessibility permission may be missing or stale after a rebuild.
///   2. Our own app may be frontmost when we try to paste — so we explicitly
///      re-activate the target app first.
///   3. The target app may still be mid-activation when the keystroke fires,
///      so we wait briefly before posting.
@MainActor
final class PasteService {

    /// Fresh, uncached check of whether the app currently has Accessibility
    /// permission. Call every time right before pasting, because the user can
    /// grant/revoke it at any moment via System Settings.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Activates `targetApp` (if provided and not ALVA-TEXT itself), waits
    /// briefly for focus to land, then posts ⌘V.
    /// Returns `false` iff Accessibility permission is missing; in that case
    /// the caller should surface a visible error so the user can grant it.
    @discardableResult
    func paste(into targetApp: NSRunningApplication?) async -> Bool {
        guard hasAccessibilityPermission else { return false }

        if let app = targetApp,
           app.bundleIdentifier != Bundle.main.bundleIdentifier,
           !app.isTerminated {
            app.activate(options: [])
            // Let the window server route focus before we post the keystroke.
            try? await Task.sleep(nanoseconds: 120_000_000) // 120 ms
        }

        postCommandV()
        return true
    }

    /// Opens System Settings directly on the Accessibility privacy pane so
    /// the user can grant permission without hunting for it.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Whether the app currently has Input-Monitoring permission. Needed for
    /// global non-modifier key-down detection (F-keys, regular letters).
    var hasInputMonitoringPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Asks macOS to prompt the user for Input-Monitoring permission. Only
    /// shows the dialog the first time; afterwards the user has to enable it
    /// manually in System Settings.
    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Opens System Settings directly on the Input-Monitoring privacy pane.
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Prompts macOS to show the "grant Accessibility permission" dialog the
    /// first time we need it. Safe to call repeatedly — the OS only shows the
    /// system dialog when it makes sense.
    @discardableResult
    func promptForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyV: CGKeyCode = 9 // kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Simulates ⌘C, used by the reverse-translate flow to grab the current
    /// selection in the frontmost app. Returns false if Accessibility is
    /// missing (keystrokes can't be posted in that case).
    @discardableResult
    func simulateCommandC() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        let keyC: CGKeyCode = 8 // kVK_ANSI_C
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return true
    }
}
