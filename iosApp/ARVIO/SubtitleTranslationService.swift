import Foundation

struct SubtitleTranslationResult {
    let lines: [String]
    let success: Bool
    let errorMessage: String?
}

enum SubtitleTranslationService {
    private static let groqURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private static let openAIURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let geminiModel = "gemini-2.5-flash"
    private static let groqModel = "llama-3.3-70b-versatile"
    private static let rtlLanguages = Set(["hebrew", "arabic", "urdu", "persian", "farsi", "yiddish"])

    static func translateBatch(lines: [String], targetLanguage: String, apiKey: String, model: String) async -> SubtitleTranslationResult {
        guard !lines.isEmpty else { return SubtitleTranslationResult(lines: lines, success: true, errorMessage: nil) }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SubtitleTranslationResult(lines: lines, success: false, errorMessage: "API key missing")
        }
        if model.localizedCaseInsensitiveContains("GEMINI") {
            return await translateGemini(lines: lines, targetLanguage: targetLanguage, apiKey: apiKey)
        }
        if model.localizedCaseInsensitiveContains("OPENAI") {
            return await translateOpenAI(lines: lines, targetLanguage: targetLanguage, apiKey: apiKey, model: model)
        }
        return await translateGroq(lines: lines, targetLanguage: targetLanguage, apiKey: apiKey)
    }

    private static func translateGroq(lines: [String], targetLanguage: String, apiKey: String) async -> SubtitleTranslationResult {
        let separator = "<NL>"
        let encoded = lines.map { $0.replacingOccurrences(of: "\n", with: separator) }
        let body: [String: Any] = [
            "model": groqModel,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": prompt(targetLanguage: targetLanguage, separator: separator)],
                ["role": "user", "content": "Translate to \(targetLanguage):\n\(jsonArrayString(encoded))"]
            ]
        ]
        var request = URLRequest(url: groqURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return SubtitleTranslationResult(lines: lines, success: false, errorMessage: "AI subtitle request failed")
            }
            let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let raw = message?["content"] as? String ?? ""
            return parse(raw: raw, fallback: lines, targetLanguage: targetLanguage, separator: separator)
        } catch {
            return SubtitleTranslationResult(lines: lines, success: false, errorMessage: error.localizedDescription)
        }
    }

    private static func translateGemini(lines: [String], targetLanguage: String, apiKey: String) async -> SubtitleTranslationResult {
        let separator = "<NL>"
        let encoded = lines.map { $0.replacingOccurrences(of: "\n", with: separator) }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent?key=\(apiKey)") else {
            return SubtitleTranslationResult(lines: lines, success: false, errorMessage: "Invalid Gemini URL")
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": prompt(targetLanguage: targetLanguage, separator: separator)]]],
            "contents": [["parts": [["text": "Translate to \(targetLanguage):\n\(jsonArrayString(encoded))"]]]],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json",
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return SubtitleTranslationResult(lines: lines, success: false, errorMessage: "AI subtitle request failed")
            }
            let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            let raw = parts?.first?["text"] as? String ?? ""
            return parse(raw: raw, fallback: lines, targetLanguage: targetLanguage, separator: separator)
        } catch {
            return SubtitleTranslationResult(lines: lines, success: false, errorMessage: error.localizedDescription)
        }
    }

    private static func translateOpenAI(lines: [String], targetLanguage: String, apiKey: String, model: String) async -> SubtitleTranslationResult {
        let separator = "<NL>"
        let encoded = lines.map { $0.replacingOccurrences(of: "\n", with: separator) }
        let resolvedModel = model == "OPENAI_GPT_4O" ? "gpt-4o" : "gpt-4o-mini"
        let body: [String: Any] = [
            "model": resolvedModel,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": prompt(targetLanguage: targetLanguage, separator: separator)],
                ["role": "user", "content": "Translate to \(targetLanguage):\n\(jsonArrayString(encoded))"]
            ]
        ]
        var request = URLRequest(url: openAIURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return SubtitleTranslationResult(lines: lines, success: false, errorMessage: "AI subtitle request failed")
            }
            let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let raw = message?["content"] as? String ?? ""
            return parse(raw: raw, fallback: lines, targetLanguage: targetLanguage, separator: separator)
        } catch {
            return SubtitleTranslationResult(lines: lines, success: false, errorMessage: error.localizedDescription)
        }
    }

    private static func prompt(targetLanguage: String, separator: String) -> String {
        """
        You are a professional subtitle translator. Translate the JSON array into natural \(targetLanguage).
        Return only a valid JSON array. Keep the same order and count. Preserve the \(separator) symbol exactly where it appears as a line break. Use informal spoken \(targetLanguage) suitable for cinema.
        """
    }

    private static func parse(raw: String, fallback: [String], targetLanguage: String, separator: String) -> SubtitleTranslationResult {
        guard let data = extractJSONArray(raw).data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data),
              decoded.count == fallback.count else {
            return SubtitleTranslationResult(lines: fallback, success: false, errorMessage: "No valid JSON array in AI response")
        }
        let isRTL = rtlLanguages.contains(targetLanguage.lowercased())
        let translated = decoded.map { line in
            let value = line.replacingOccurrences(of: separator, with: "\n")
            return isRTL ? "\u{200F}\(value)\u{200F}" : value
        }
        return SubtitleTranslationResult(lines: translated, success: true, errorMessage: nil)
    }

    private static func extractJSONArray(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = stripped.firstIndex(of: "["),
              let end = stripped.lastIndex(of: "]"),
              start <= end else { return stripped }
        return String(stripped[start...end])
    }

    private static func jsonArrayString(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
