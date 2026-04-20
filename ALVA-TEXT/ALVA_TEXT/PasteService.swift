import AppKit

final class PasteService {
    func simulateCommandV() {
        guard AXIsProcessTrusted() else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyV: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
