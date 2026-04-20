import AppKit
import Combine
import Foundation

enum AppStatus: String {
    case idle
    case recording
    case transcribing
    case rewriting
    case pasted
    case error
}

enum HotkeyMode {
    case standard
    case polite
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var lastTranscript: String = UserDefaults.standard.string(forKey: "lastTranscript") ?? ""
    @Published var lastRewrittenText: String = UserDefaults.standard.string(forKey: "lastRewritten") ?? ""
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "openaiApiKey") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "openaiApiKey") }
    }
    @Published var autoPaste: Bool = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var rewriteEnabled: Bool = UserDefaults.standard.object(forKey: "rewriteEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rewriteEnabled, forKey: "rewriteEnabled") }
    }

    private let recorder = AudioRecorder()
    private lazy var hotkeys = HotkeyManager(delegate: self)
    private let openAI = OpenAIService()
    private let pasteService = PasteService()

    private var recordingMode: HotkeyMode?
    private var isProcessing = false

    func start() {
        hotkeys.start()
    }

    func requestPermissions() {
        recorder.requestPermission()
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func beginRecording(mode: HotkeyMode) {
        guard !isProcessing else { return }
        do {
            try recorder.startRecording()
            recordingMode = mode
            status = .recording
        } catch {
            status = .error
        }
    }

    func endRecordingAndProcess() {
        guard status == .recording, !isProcessing else { return }
        isProcessing = true

        Task {
            defer {
                isProcessing = false
                recordingMode = nil
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

                var finalText = transcript
                if recordingMode == .polite && rewriteEnabled {
                    status = .rewriting
                    finalText = try await openAI.rewriteToPoliteGerman(text: transcript, apiKey: apiKey)
                    lastRewrittenText = finalText
                    UserDefaults.standard.set(finalText, forKey: "lastRewritten")
                }

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)

                if autoPaste {
                    pasteService.simulateCommandV()
                }

                status = .pasted
                try await Task.sleep(nanoseconds: 900_000_000)
                status = .idle
            } catch {
                status = .error
            }
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
}
