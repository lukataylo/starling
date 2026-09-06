import UIKit
import Observation
import CryptoKit

/// Generates illustrations and diagrams for image cards with the OpenAI image API, cached on disk.
@Observable @MainActor
final class ImageGenerator {
    private(set) var images: [String: UIImage] = [:]
    private(set) var failed: Set<String> = []
    private var inflight: Set<String> = []
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("genimg", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func key(_ prompt: String, mood: String) -> String {
        let h = SHA256.hash(data: Data((mood + "|" + prompt).utf8))
        return h.prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    func image(prompt: String, mood: String) -> UIImage? {
        let k = Self.key(prompt, mood: mood)
        if let i = images[k] { return i }
        let file = dir.appendingPathComponent(k + ".jpg")
        if let data = try? Data(contentsOf: file), let i = UIImage(data: data) { images[k] = i; return i }
        return nil
    }

    func isFailed(prompt: String, mood: String) -> Bool { failed.contains(Self.key(prompt, mood: mood)) }

    static func style(for mood: String) -> String {
        mood == "calm"
        ? "Soft, calm editorial illustration. Muted sage, sand and warm cream tones, gentle rounded shapes, generous negative space, matte texture."
        : "Crisp, high-contrast editorial illustration. Ink on off-white with a single bold accent colour, sharp geometric shapes, clear focal point."
    }

    func request(prompt: String, mood: String) {
        let k = Self.key(prompt, mood: mood)
        guard images[k] == nil, !inflight.contains(k), !failed.contains(k), let key = LLMClient.apiKey else { return }
        inflight.insert(k)
        let full = "\(Self.style(for: mood)) \(prompt). If this is a diagram, keep it simple and legible with at most a few labelled elements. No paragraphs of text, no logos, no watermarks."
        Task {
            defer { inflight.remove(k) }
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 90
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = ["model": "gpt-image-2", "prompt": full, "size": "1024x1024", "quality": "low", "output_format": "jpeg", "n": 1]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let b64 = ((json["data"] as? [[String: Any]])?.first?["b64_json"] as? String),
                  let imgData = Data(base64Encoded: b64), let img = UIImage(data: imgData) else {
                failed.insert(k); return
            }
            try? imgData.write(to: dir.appendingPathComponent(k + ".jpg"))
            images[k] = img
        }
    }
}
