import AppKit
import Foundation

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyStart(mode: HotkeyMode)
    func hotkeyStop()
}

final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var isControlDown = false
    private var isOptionDown = false
    private var isCommandDown = false

    private var isHoldRecording = false
    private var holdMode: HotkeyMode?

    private var toggleRecording = false
    private var toggleMode: HotkeyMode?

    private var standardTapTimes: [Date] = []
    private var politeTapTimes: [Date] = []

    private var wasStandardComboDown = false
    private var wasPoliteComboDown = false

    private let doublePressWindow: TimeInterval = 0.35

    init(delegate: HotkeyManagerDelegate?) {
        self.delegate = delegate
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    private func handle(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let oldControl = isControlDown
        let oldOption = isOptionDown
        let oldCommand = isCommandDown

        isControlDown = flags.contains(.control)
        isOptionDown = flags.contains(.option)
        isCommandDown = flags.contains(.command)

        if !oldControl && isControlDown { registerTap(group: .standard) }
        if !oldOption && isOptionDown && isControlDown { registerTap(group: .standard) }
        if !oldOption && isOptionDown && isCommandDown { registerTap(group: .polite) }
        if !oldCommand && isCommandDown { registerTap(group: .polite) }

        handleToggleStopEdges()
        handleHoldModes()
    }

    private enum TapGroup {
        case standard
        case polite
    }

    private func registerTap(group: TapGroup) {
        let now = Date()
        switch group {
        case .standard:
            guard isControlDown && isOptionDown && !isCommandDown else { return }
            standardTapTimes.append(now)
            standardTapTimes = standardTapTimes.filter { now.timeIntervalSince($0) <= doublePressWindow }
            if standardTapTimes.count >= 2 {
                standardTapTimes.removeAll()
                toggle(for: .standard)
            }
        case .polite:
            guard isOptionDown && isCommandDown && !isControlDown else { return }
            politeTapTimes.append(now)
            politeTapTimes = politeTapTimes.filter { now.timeIntervalSince($0) <= doublePressWindow }
            if politeTapTimes.count >= 2 {
                politeTapTimes.removeAll()
                toggle(for: .polite)
            }
        }
    }


    private func handleToggleStopEdges() {
        let standardPressed = isControlDown && isOptionDown && !isCommandDown
        let politePressed = isOptionDown && isCommandDown && !isControlDown

        defer {
            wasStandardComboDown = standardPressed
            wasPoliteComboDown = politePressed
        }

        guard toggleRecording, let toggleMode else { return }

        switch toggleMode {
        case .standard:
            if standardPressed && !wasStandardComboDown {
                toggleRecording = false
                self.toggleMode = nil
                delegate?.hotkeyStop()
            }
        case .polite:
            if politePressed && !wasPoliteComboDown {
                toggleRecording = false
                self.toggleMode = nil
                delegate?.hotkeyStop()
            }
        }
    }

    private func handleHoldModes() {
        if toggleRecording { return }

        let standardPressed = isControlDown && isOptionDown && !isCommandDown
        let politePressed = isOptionDown && isCommandDown && !isControlDown

        if !isHoldRecording {
            if standardPressed {
                isHoldRecording = true
                holdMode = .standard
                delegate?.hotkeyStart(mode: .standard)
            } else if politePressed {
                isHoldRecording = true
                holdMode = .polite
                delegate?.hotkeyStart(mode: .polite)
            }
            return
        }

        guard let holdMode else { return }
        let stillPressed = (holdMode == .standard) ? standardPressed : politePressed
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
