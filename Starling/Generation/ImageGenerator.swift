import UIKit
import Observation
import CryptoKit

/// Generates story images (covers, illustrations, diagrams) with the OpenAI image API, high quality, cached on disk.
@Observable @MainActor
final class ImageGenerator {
    private(set) var images: [String: UIImage] = [:]
    private(set) var failed: Set<String> = []
    private var inflight: Set<String> = []
    private var queue: [(String, String, String)] = []   // (key, prompt, mood)
    private let maxConcurrent = 3
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("genimg2", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static let styleBase = "Editorial news-story illustration with a bold, contemporary mobile-first composition: one clear human, object, or symbolic action as the dominant subject, positioned low-right or right-of-frame; reserve generous clean negative space across the upper-left for an app to overlay a large statistic and one short line. Build the image from flat saturated colour fields and tinted duotone photographic imagery, using warm or vivid monochrome washes, simplified silhouettes, subtle soft grain, gentle atmospheric haze, and cinematic directional light. Minimal, graphic, emotionally immediate, premium editorial feeling. No lettering, numbers, logos, interface elements, watermarks, or embedded text."
    static let styleCalm = "Editorial news-story illustration in a calm, reflective adaptation of the same mobile-first visual language: a single clear subject or quiet action sits low-right or along the right edge, with expansive uncluttered negative space in the upper-left for later statistic and caption overlay. Use muted sage, sand, warm stone, pale clay, and softened cream colour fields with restrained duotone photography. Add delicate film grain, diffuse daylight, low-contrast shadows, gentle haze, and simple graphic shapes. The mood is measured, humane, reassuring, and contemplative. No lettering, numbers, logos, interface elements, watermarks, or embedded text."
    static let styleFocused = "Editorial news-story illustration in a focused, tense adaptation of the same mobile-first visual language: one decisive subject, gesture, or object dominates the lower-right, leaving broad dark negative space in the upper-left for later statistic and caption overlay. Use high-contrast ink black, charcoal, deep slate, and off-white, punctuated by one vivid accent colour such as signal orange, red, or electric lime. Combine stark duotone photography, crisp silhouettes, directional cinematic light, hard-edged shadow, restrained grain, and subtle haze. The mood is urgent, precise, and investigative. No lettering, numbers, logos, interface elements, watermarks, or embedded text."

    static func key(_ prompt: String, mood: String) -> String { PosterPrompts.key(prompt, mood: mood) }

    func image(prompt: String, mood: String) -> UIImage? {
        let k = Self.key(prompt, mood: mood)
        if let i = images[k] { return i }
        if let i = UIImage(named: "poster_" + k) { images[k] = i; return i }   // bundled, pre-generated
        let file = dir.appendingPathComponent(k + ".jpg")
        if let data = try? Data(contentsOf: file), let i = UIImage(data: data) { images[k] = i; return i }
        return nil
    }

    func isFailed(prompt: String, mood: String) -> Bool { failed.contains(Self.key(prompt, mood: mood)) }

    /// Look up under the given mood, then the other one — pre-generated posters may be keyed by the preset's mood.
    func imageAnyMood(prompt: String, mood: String) -> UIImage? {
        image(prompt: prompt, mood: mood) ?? image(prompt: prompt, mood: mood == "calm" ? "focused" : "calm")
    }

    static func coverPrompt(headline: String, summary: String) -> String { PosterPrompts.coverPrompt(headline: headline, summary: summary) }
    static func style(for mood: String) -> String { mood == "calm" ? styleCalm : styleFocused }

    func request(prompt: String, mood: String) {
        let k = Self.key(prompt, mood: mood)
        guard images[k] == nil, !inflight.contains(k), !failed.contains(k), !queue.contains(where: { $0.0 == k }), LLMClient.apiKey != nil else { return }
        if UIImage(named: "poster_" + k) != nil { _ = image(prompt: prompt, mood: mood); return }
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(k + ".jpg").path) { _ = image(prompt: prompt, mood: mood); return }
        queue.append((k, prompt, mood))
        pump()
    }

    private func pump() {
        while inflight.count < maxConcurrent, !queue.isEmpty {
            let (k, prompt, mood) = queue.removeFirst()
            inflight.insert(k)
            Task { await self.run(k, prompt: prompt, mood: mood); self.inflight.remove(k); self.pump() }
        }
    }

    private func run(_ k: String, prompt: String, mood: String) async {
        guard let key = LLMClient.apiKey else { return }
        let isPoster = prompt.hasPrefix("Vertical 9:16 story card")
        let full = isPoster ? prompt : "\(Self.style(for: mood)) Subject: \(prompt). If a diagram is described, keep it to at most three simple elements with no labels."
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": "gpt-image-2", "prompt": full, "size": "1024x1536", "quality": "high", "output_format": "jpeg", "output_compression": 80, "n": 1]
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
