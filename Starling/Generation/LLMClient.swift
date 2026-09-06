import Foundation

enum LLMError: LocalizedError {
    case noKey, http(Int, String), refusal(String), truncated, badJSON(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "No OpenAI API key. Add one in Settings."
        case .http(let code, let body): return "API error \(code): \(body.prefix(200))"
        case .refusal(let why): return "The model declined to adapt this story. \(why)"
        case .truncated: return "The generation was cut short."
        case .badJSON(let why): return "Could not read the generated edition. \(why)"
        }
    }
}

/// OpenAI Chat Completions with strict JSON-schema structured output.
struct LLMClient {
    static let defaultModel = "gpt-5.6-luna"
    static var model: String { UserDefaults.standard.string(forKey: "modelOverride").flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel }

    static var apiKey: String? {
        let override = UserDefaults.standard.string(forKey: "apiKeyOverride")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty { return override }
        let bundled = (Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bundled.isEmpty ? nil : bundled
    }

    static func generate(userMessage: String) async throws -> (Edition, usage: [String: Any]) {
        guard let key = apiKey else { throw LLMError.noKey }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": DesignGenome.rules],
                ["role": "user", "content": userMessage],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "edition", "strict": true, "schema": EditionSchema.json],
            ],
        ]
        // Reasoning models: keep effort minimal, this is a rewrite not a proof. gpt-6 family rejects "none".
        if model.hasPrefix("gpt-6") { body["reasoning_effort"] = "low" }
        else if model.hasPrefix("gpt-5") { body["reasoning_effort"] = "none" }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw LLMError.http(code, String(data: data, encoding: .utf8) ?? "") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw LLMError.badJSON("no choices") }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw LLMError.refusal(refusal) }
        if choice["finish_reason"] as? String == "length" { throw LLMError.truncated }
        guard let text = message["content"] as? String, let textData = text.data(using: .utf8) else { throw LLMError.badJSON("no content") }
        do {
            return (try JSONDecoder().decode(Edition.self, from: textData), json["usage"] as? [String: Any] ?? [:])
        } catch {
            throw LLMError.badJSON(error.localizedDescription)
        }
    }
}
