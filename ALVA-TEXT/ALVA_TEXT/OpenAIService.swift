import Foundation

struct TranscriptionResponse: Decodable {
    let text: String
}

private struct ChatCompletionsRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

final class OpenAIService {
    func transcribe(audioURL: URL, apiKey: String, model: String, language: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ALVA_TEXT", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data = try Data(contentsOf: audioURL)
        let body = createMultipartBody(
            boundary: boundary,
            fileData: data,
            fileName: audioURL.lastPathComponent,
            model: model,
            language: language
        )
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: responseData)
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func rewriteToPoliteGerman(text: String, apiKey: String) async throws -> String {
        try await chatCompletion(
            apiKey: apiKey,
            systemPrompt: "Du bist ein deutscher Schreibassistent.",
            userPrompt: "Schreibe den folgenden Text als höfliche, knappe, nachrichtentaugliche deutsche Nachricht um. Nur den finalen Text ausgeben.\n\n\(text)",
            fallback: text
        )
    }

    /// Message-Modus: adaptive rewrite for chats, social-media posts, short
    /// e-mails. Mirrors the tone of the dictation (Du/Sie, formell/locker),
    /// trims filler, never sounds AI-generated. Output language is ALWAYS
    /// the same as the input language — never translate.
    func rewriteAsAdaptiveMessage(text: String, apiKey: String) async throws -> String {
        let systemPrompt = """
        Du bist Alpers persönlicher deutscher Schreibassistent für Chats, WhatsApp, \
        Signal, kurze E-Mails und Social-Media-Posts.

        HARTE REGELN (absolut verbindlich):
        - Die Eingabe ist IMMER ein deutscher Diktat-Text. Gib IMMER deutschen Text zurück. \
          Niemals übersetzen. Niemals eine englische Fassung anhängen. Niemals einen \
          Trennstrich („---", „— — —") oder sonstige Separatoren einfügen.
        - Niemals Rückfragen stellen. Niemals antworten mit „Please provide the text" \
          oder Ähnlichem. Wenn die Eingabe sehr kurz ist, gib sie unverändert oder minimal \
          geglättet zurück.
        - Gib NUR den fertigen Nachrichtentext aus, ohne Anführungszeichen, ohne Kommentare, \
          ohne Zwischenüberschriften.

        TON ERKENNEN (zuerst):
        Ermittle aus der Eingabe, ob der Ton LOCKER (Chat/WhatsApp/Signal) oder FORMELL \
        (E-Mail an jemanden im Sie) ist.
        - LOCKER: „Hi", „Hey", „Moin", Duzen, kurze Sätze, Umgangssprache, Ausrufe.
        - FORMELL: „Sehr geehrter", „Guten Tag", Siezen, vollständige Höflichkeitsformeln.

        STILREGELN:
        1. Anrede/Ansprache 1:1 vom Ton übernehmen (Du wenn geduzt, Sie wenn gesiezt).
        2. KEINE erfundenen Höflichkeitsfloskeln. „Ich hoffe, dir/Ihnen geht es gut", \
           „Viele Grüße vorab", „Zusammenfassend lässt sich sagen" sind verboten, wenn \
           Alper sie nicht selbst diktiert hat.
        3. Abkürzungen am Ende:
           - LOCKERER Ton → Abkürzung BEIBEHALTEN: „lg Alper" bleibt „LG Alper". \
             „vg" bleibt „VG". „hdl" bleibt „HDL". Nur groß/klein sanft normalisieren.
           - FORMELLER Ton → Abkürzung ausschreiben: „mfg" → „Mit freundlichen Grüßen". \
             „vg" → „Viele Grüße". „bg" → „Beste Grüße".
        4. Emojis:
           - LOCKERER Ton → GENAU EIN passendes Emoji einbauen (max. zwei bei längeren \
             Nachrichten, niemals drei). Stelle: meist am Satzende oder vor der Grußformel. \
             Passend zum Inhalt (nicht generisch 😊). Niemals ein Emoji erzwingen, wenn es \
             unpassend wirkt.
           - FORMELLER Ton → NIEMALS Emojis einfügen.
        5. Rechtschreibung/Grammatik korrigieren, holprige Diktat-Stellen glätten.
        6. Keine Semikolons. Stattdessen Punkt oder Gedankenstrich.
        7. Kurze Eingaben bleiben kurz.
        8. Keine Formulierungen, die nach KI klingen („Zusammenfassend", „Es ist wichtig zu \
           beachten", „In diesem Zusammenhang möchte ich betonen" usw.).
        """
        return try await chatCompletion(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: text,
            fallback: text
        )
    }

    /// Translates German (or any) input into natural, neutral English.
    /// Kept for backward compatibility; prefer `translateText(to:text:apiKey:)`.
    func translateToEnglish(text: String, apiKey: String) async throws -> String {
        try await translateText(to: "en", text: text, apiKey: apiKey)
    }

    /// Translates `text` into the language identified by `isoCode` (e.g.
    /// `"en"`, `"fr"`, `"it"`). Preserves meaning, tone and paragraph breaks,
    /// outputs only the translation.
    func translateText(to isoCode: String, text: String, apiKey: String) async throws -> String {
        let languageName = LanguageCatalog.englishName(for: isoCode)
        let systemPrompt = """
        You are a precise translator. Output ONLY the translation — no \
        commentary, no quotation marks, no headers, no alternative versions.
        """
        let userPrompt = """
        Translate the following text into \(languageName). Preserve meaning, \
        tone, register (formal/informal) and paragraph breaks. If the input \
        contains a greeting or sign-off (e.g. "LG", "VG", "Mit freundlichen \
        Grüßen"), translate it idiomatically. Output only the translation.

        \(text)
        """
        return try await chatCompletion(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            fallback: text
        )
    }

    private func chatCompletion(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        fallback: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ALVA_TEXT", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ChatCompletionsRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: responseData)
        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: responseData)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback
    }

    private func createMultipartBody(boundary: String, fileData: Data, fileName: String, model: String, language: String) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append("\(language)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        body.append(fileData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(
                domain: "ALVA_TEXT",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: serverMessage]
            )
        }
    }
}
