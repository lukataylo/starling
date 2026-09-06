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
    func prefetch(_ articles: [Article], state: UserState, sources: [FeedSource], feeds: FeedStore) {
        guard LLMClient.apiKey != nil else { return }
        for a in articles.prefix(3) {
            let k = key(a, .adapt, state)
            if editions[k] != nil || inflight[k] != nil { continue }
            Task {
                let full = await feeds.loadBody(for: a)
                await self.generate(article: full, intent: .adapt, state: state, sources: sources)
            }
        }
    }

    func edition(for article: Article, intent: GenerationIntent, state: UserState) -> Edition? {
        editions[key(article, intent, state)] ?? bundled(article, intent)
    }

    func status(for article: Article, intent: GenerationIntent, state: UserState) -> Status {
        status[key(article, intent, state)] ?? .idle
    }

    @discardableResult
    func generate(article: Article, intent: GenerationIntent, state: UserState, sources: [FeedSource], force: Bool = false) async -> Edition? {
        let k = key(article, intent, state)
        if !force, let e = editions[k] { return e }
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
