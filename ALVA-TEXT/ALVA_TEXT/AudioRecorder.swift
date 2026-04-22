import AVFoundation
import Foundation

final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?

    /// Last recording's duration in seconds. Set when `stopRecording()`
    /// returns, used for API-cost tracking and ignored elsewhere.
    private(set) var lastDuration: TimeInterval = 0

    func requestPermission() {
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func startRecording() throws {
        let url = Self.tempFileURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record()
    }

    func stopRecording() throws -> URL {
        guard let recorder else {
            throw NSError(domain: "ALVA_TEXT", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recorder was not running"])
        }
        lastDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return recorder.url
    }

    private static func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("alva-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
}
