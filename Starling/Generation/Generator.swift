import Foundation
import Observation

/// Owns generated editions, caching by (article, intent, state bucket), plus reader feedback that evolves later generations.
@Observable @MainActor
final class Generator {
    struct Key: Hashable { let articleID: String; let intent: String; let bucket: String }
    enum Status: Equatable { case idle, generating, failed(String) }

    private(set) var editions: [Key: Edition] = [:]
    private(set) var status: [Key: Status] = [:]
    private var inflight: [Key: Task<Edition?, Never>] = [:]
    private(set) var lastLatency: TimeInterval?
    private(set) var lastUsage: String = ""

    /// Stored feedback strings, sent in every prompt. Persisted.
    var feedback: [String] {
        didSet { UserDefaults.standard.set(feedback, forKey: "readerFeedback") }
    }

    /// Pre-generated editions and hero images for the bundled example articles.
    private let bundledEditions: [String: [String: Edition]]
    private let bundledMedia: [String: [String: String]]

    init() {
        feedback = UserDefaults.standard.stringArray(forKey: "readerFeedback") ?? []
        if let url = Bundle.main.url(forResource: "editions", withExtension: "json"), let data = try? Data(contentsOf: url) {
            bundledEditions = (try? JSONDecoder().decode([String: [String: Edition]].self, from: data)) ?? [:]
        } else { bundledEditions = [:] }
        if let url = Bundle.main.url(forResource: "media", withExtension: "json"), let data = try? Data(contentsOf: url) {
            bundledMedia = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
        } else { bundledMedia = [:] }
    }

    func bundled(_ article: Article, _ intent: GenerationIntent) -> Edition? {
        bundledEditions[article.id]?[intent.cacheKey]
    }

    /// Featured stories: the live "adapt" resolves to the pre-generated edition that matches the mood, instantly and offline.
    func bundledAdapt(_ article: Article, state: UserState) -> Edition? {
        guard let set = bundledEditions[article.id] else { return nil }
        let calmish = state.label == .calm || state.label == .tired || state.timeOfDay == .evening || state.timeOfDay == .night
        return set[calmish ? "preset:calm" : "preset:focused"] ?? set.values.first
    }

    /// Bundled hero image name for an article, matched to the edition's mood.
    func heroImageName(for article: Article, edition: Edition?) -> String? {
        guard let m = bundledMedia[article.id] else { return nil }
        let calmPalettes: Set<PaletteName> = [.calm, .dusk, .night, .dawn]
        let mood = (edition.map { calmPalettes.contains($0.palette) } ?? false) ? "calm" : "focused"
        return m[mood] ?? m.values.first
    }

    /// Enabled sources shape the voice, so they are part of the cache key.
    var sourceSignature: String = ""

    func key(_ article: Article, _ intent: GenerationIntent, _ state: UserState) -> Key {
        var bucket: String
        switch intent {
        case .adapt: bucket = state.bucket
        case .longform: bucket = state.timeOfDay.rawValue + "|" + (state.stress > 0.6 ? "hi" : "lo")
        case .preset: bucket = state.timeOfDay.rawValue
        }
        bucket += "|" + sourceSignature + "|fb\(feedback.count)"
        return Key(articleID: article.id, intent: intent.cacheKey, bucket: bucket)
    }

    /// Warm the cache for the first few visible stories so tapping one is instant.
    /// Pre-render the top five stories for the live state and the key moods, then draw their images, so opening one is instant.
    func prefetch(_ articles: [Article], state: UserState, sources: [FeedSource], feeds: FeedStore, images: ImageGenerator? = nil, mood: String = "focused") {
        guard LLMClient.apiKey != nil else { return }
        let intents: [GenerationIntent] = [.adapt, .preset(.calm), .preset(.focused), .preset(.commute)]
        let live = articles.filter { self.bundledEditions[$0.id] == nil }
        for a in live.prefix(5) {
            Task {
                let full = await feeds.loadBody(for: a)
                for intent in intents {
                    let k = self.key(full, intent, state)
                    if self.editions[k] == nil && self.inflight[k] == nil {
                        _ = await self.generate(article: full, intent: intent, state: state, sources: sources)
                    }
                    if let images, let e = self.edition(for: full, intent: intent, state: state) {
                        let m: String = [.calm, .dusk, .night, .dawn].contains(e.palette) ? "calm" : mood
                        let idx = articles.firstIndex(where: { $0.id == a.id }) ?? 99
                        if intent == .adapt || idx < 2 {
                            for p in CardsRenderer.posterPrompts(edition: e, article: full, mood: m) { if let p { images.request(prompt: p, mood: m) } }
                        }
                        for b in e.blocks where b.type == .imageCard {
                            if let p = b.imagePrompt, !p.isEmpty { images.request(prompt: p, mood: m) }
                        }
                    }
                }
            }
        }
    }

    func edition(for article: Article, intent: GenerationIntent, state: UserState) -> Edition? {
        if let e = editions[key(article, intent, state)] { return e }
        if intent == .adapt, let e = bundledAdapt(article, state: state) { return e }
        return bundled(article, intent)
    }

    func status(for article: Article, intent: GenerationIntent, state: UserState) -> Status {
        status[key(article, intent, state)] ?? .idle
    }

    @discardableResult
    func generate(article: Article, intent: GenerationIntent, state: UserState, sources: [FeedSource], force: Bool = false) async -> Edition? {
        let k = key(article, intent, state)
        if !force, let e = editions[k] { return e }
        if !force, intent == .adapt, let e = bundledAdapt(article, state: state) { return e }
        if !force, let e = bundled(article, intent) { return e }
        if let t = inflight[k] { return await t.value }
        let prompt = PromptBuilder.userMessage(article: article, sources: sources, state: state, intent: intent, feedback: feedback)
        status[k] = .generating
        let task = Task<Edition?, Never> {
            let start = Date()
            do {
                let (edition, usage) = try await LLMClient.generate(userMessage: prompt)
                self.lastLatency = Date().timeIntervalSince(start)
                self.lastUsage = usage.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
                self.editions[k] = edition
                self.status[k] = .idle
                return edition
            } catch {
                self.status[k] = .failed(error.localizedDescription)
                return nil
            }
        }
        inflight[k] = task
        let result = await task.value
        inflight[k] = nil
        return result
    }

    func addFeedback(_ line: String) {
        feedback.append(line)
        if feedback.count > 12 { feedback.removeFirst(feedback.count - 12) }
    }

    func clearCache() { editions.removeAll(); status.removeAll() }
}
