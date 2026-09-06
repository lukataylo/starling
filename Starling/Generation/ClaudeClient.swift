import Foundation

enum ClaudeError: LocalizedError {
    case noKey, http(Int, String), refusal(String), truncated, badJSON(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "No Anthropic API key. Add one in Settings."
        case .http(let code, let body): return "API error \(code): \(body.prefix(200))"
        case .refusal(let why): return "The model declined to adapt this story. \(why)"
        case .truncated: return "The generation was cut short."
        case .badJSON(let why): return "Could not read the generated edition. \(why)"
        }
    }
}

struct ClaudeClient {
    static var model: String { UserDefaults.standard.string(forKey: "modelOverride").flatMap { $0.isEmpty ? nil : $0 } ?? "claude-opus-5" }

    static var apiKey: String? {
        let override = UserDefaults.standard.string(forKey: "anthropicKeyOverride")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty { return override }
        let bundled = (Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bundled.isEmpty ? nil : bundled
    }

    /// One structured-output call: system = genome rules (cached), user = article + state.
    static func generate(userMessage: String) async throws -> (Edition, usage: [String: Any]) {
        guard let key = apiKey else { throw ClaudeError.noKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 6000,
            "fallbacks": "default",
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": EditionSchema.json],
            ],
            "system": [[
                "type": "text",
                "text": DesignGenome.rules,
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [["role": "user", "content": userMessage]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClaudeError.http(code, String(data: data, encoding: .utf8) ?? "") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.badJSON("not an object") }
        let stop = json["stop_reason"] as? String ?? ""
        if stop == "refusal" {
            let why = ((json["stop_details"] as? [String: Any])?["explanation"] as? String) ?? ""
            throw ClaudeError.refusal(why)
        }
        if stop == "max_tokens" { throw ClaudeError.truncated }
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let textData = text.data(using: .utf8) else { throw ClaudeError.badJSON("no text block") }
        do {
            let edition = try JSONDecoder().decode(Edition.self, from: textData)
            return (edition, json["usage"] as? [String: Any] ?? [:])
        } catch {
            throw ClaudeError.badJSON(error.localizedDescription)
        }
    }
}
