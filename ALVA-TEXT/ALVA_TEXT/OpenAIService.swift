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
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ALVA_TEXT", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = "Schreibe den folgenden Text als höfliche, knappe, nachrichtentaugliche deutsche Nachricht um. Nur den finalen Text ausgeben.\n\n\(text)"
        let payload = ChatCompletionsRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(role: "system", content: "Du bist ein deutscher Schreibassistent."),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: responseData)
        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: responseData)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
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
