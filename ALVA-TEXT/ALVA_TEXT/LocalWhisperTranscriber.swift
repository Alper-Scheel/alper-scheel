import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

/// On-device transcription via WhisperKit. The `WhisperKit` Swift Package
/// must be added to the project (File → Add Package Dependencies →
/// `https://github.com/argmaxinc/WhisperKit`). Until that's done the code
/// compiles but `isAvailable` returns false and calls throw a readable
/// error telling the user what to do.
///
/// Default model: `openai_whisper-small` (~466 MB). Downloaded lazily to
/// Application Support on first transcription. Solid German quality, runs
/// faster than real-time on any Apple Silicon.
@MainActor
final class LocalWhisperTranscriber {

    static let defaultModelName = "openai_whisper-small"

    #if canImport(WhisperKit)
    private var pipe: WhisperKit?
    private var loadingTask: Task<WhisperKit, Error>?
    #endif

    /// True if WhisperKit is linked into the binary.
    var isAvailable: Bool {
        #if canImport(WhisperKit)
        return true
        #else
        return false
        #endif
    }

    /// True if the default model is already loaded in memory.
    var isReady: Bool {
        #if canImport(WhisperKit)
        return pipe != nil
        #else
        return false
        #endif
    }

    /// Triggers the first-time model download and load. Safe to call
    /// multiple times — subsequent calls return immediately.
    func prepare() async throws {
        #if canImport(WhisperKit)
        if pipe != nil { return }
        if let existing = loadingTask {
            pipe = try await existing.value
            return
        }
        let task = Task { () throws -> WhisperKit in
            return try await WhisperKit(model: Self.defaultModelName)
        }
        loadingTask = task
        defer { loadingTask = nil }
        pipe = try await task.value
        #else
        throw Self.unavailableError
        #endif
    }

    /// Transcribes the audio file into text. `language` is an ISO-639-1 code
    /// ("de", "en", …) or nil for auto-detection.
    ///
    /// If `translateToEnglish` is true, Whisper uses its built-in
    /// translate task instead of plain transcription — the audio is
    /// translated directly into English, no second LLM call needed.
    /// This only works for English as the target; other target languages
    /// need a separate translation step.
    func transcribe(
        audioURL: URL,
        language: String?,
        translateToEnglish: Bool = false
    ) async throws -> String {
        #if canImport(WhisperKit)
        try await prepare()
        guard let pipe else {
            throw Self.loadFailedError
        }
        let options = DecodingOptions(
            task: translateToEnglish ? .translate : .transcribe,
            language: language
        )
        let results = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        let joined = results.map { $0.text }.joined(separator: " ")
        let charSet: CharacterSet = .whitespacesAndNewlines
        let trimmed = joined.trimmingCharacters(in: charSet)
        return Self.stripCommonHallucinations(in: trimmed)
        #else
        throw Self.unavailableError
        #endif
    }

    /// Removes trailing (and repeated) phrases that Whisper is known to
    /// hallucinate when the audio contains silence or unclear segments.
    /// These come from video subtitle training data ("Danke fürs Zuschauen",
    /// "Untertitelung des ZDF", "Thanks for watching") and creep into
    /// dictation output where they have no business.
    static func stripCommonHallucinations(in text: String) -> String {
        // Regex-friendly list of end-of-text noise patterns. Matched
        // case-insensitively at the very END of the string, with optional
        // trailing punctuation / whitespace, and folded into a single
        // trimming pass so stacked hallucinations ("Danke. Danke. Vielen
        // Dank.") all disappear together.
        let noisePhrases: [String] = [
            // German
            "vielen dank fürs zuschauen",
            "vielen dank fürs zusehen",
            "danke fürs zuschauen",
            "danke fürs zusehen",
            "vielen dank für ihre aufmerksamkeit",
            "vielen dank",
            "danke schön",
            "danke",
            "untertitelung des zdf für funk",
            "untertitel im auftrag des zdf",
            "untertitel der arbeitsgemeinschaft",
            "untertitelung",
            // English
            "thanks for watching",
            "thank you for watching",
            "thank you",
            "thanks",
            // French
            "merci",
            // Italian
            "grazie",
            // Misc noise
            "www.mooji.org",
            "www.beadaki.de"
        ]

        // Regex patterns for trailing audio annotations that Whisper
        // produces when it hears silence or non-speech:
        //   [Musik], [Applause], [Laughter], [any-bracket]
        //   *lacht*, *Sie seufzt.*, *any-asterisk*
        let trailingAnnotationPatterns = [
            #"\s*\[[^\]]+\]\s*$"#,     // [brackets]
            #"\s*\*[^*]+\*\s*$"#,      // *asterisks*
            #"\s*\([^)]+\)\s*$"#       // (parens) — some models use these too
        ]

        var working = text
        var changed = true
        while changed {
            changed = false

            // 1. Regex patterns (audio annotations in brackets/asterisks)
            for pattern in trailingAnnotationPatterns {
                if let range = working.range(of: pattern, options: .regularExpression) {
                    working.removeSubrange(range)
                    working = working.trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }

            // 2. Known noise phrases at the end
            let stripped = working.trimmingCharacters(in: .whitespacesAndNewlines)
            let stripPunct = stripped.trimmingCharacters(in: CharacterSet(charactersIn: ".!?…,"))
            let lower = stripPunct.lowercased()
            for phrase in noisePhrases {
                if lower.hasSuffix(phrase) {
                    let cutoff = stripPunct.index(stripPunct.endIndex, offsetBy: -phrase.count)
                    working = String(stripPunct[..<cutoff])
                    changed = true
                    break
                }
            }
        }
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops the currently loaded model from memory. Next `prepare()` call
    /// will reload it. Useful if the user switches to cloud and wants to
    /// free RAM.
    func unload() {
        #if canImport(WhisperKit)
        pipe = nil
        loadingTask = nil
        #endif
    }

    // MARK: - Errors

    static let unavailableError = NSError(
        domain: "ALVA_TEXT",
        code: -200,
        userInfo: [NSLocalizedDescriptionKey: "Lokales Whisper-Modul nicht verfügbar. Öffne in Xcode File → Add Package Dependencies und füge https://github.com/argmaxinc/WhisperKit hinzu."]
    )

    static let loadFailedError = NSError(
        domain: "ALVA_TEXT",
        code: -201,
        userInfo: [NSLocalizedDescriptionKey: "WhisperKit konnte das Modell nicht laden."]
    )
}
