import Foundation
import Observation

@Observable @MainActor
final class FeedStore {
    var enabledIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledIDs), forKey: "enabledFeeds.v2") }
    }
    private(set) var articles: [Article] = []
    /// All parsed items, beyond the visible window; `loadMore()` reveals more as the reader scrolls.
    private var reserve: [Article] = []
    var hasMore: Bool { !reserve.isEmpty }
    func loadMore(_ n: Int = 8) {
        guard !reserve.isEmpty else { return }
        let chunk = Array(reserve.prefix(n)); reserve.removeFirst(chunk.count)
        articles += chunk
    }
    private(set) var isLoading = false
    private(set) var failedSourceIDs: Set<String> = []
    private(set) var usedSnapshot = false
    private(set) var lastRefresh: Date?
    /// Bundled example stories with pre-generated editions and posters, pinned to the top for an instant, offline-safe demo.
    let featured: [Article] = {
        let all = Snapshot.load()
        guard let url = Bundle.main.url(forResource: "featured", withExtension: "json"), let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String]], let ids = obj["featured"] else { return Array(all.prefix(5)) }
        return ids.compactMap { id in all.first { $0.id == id } }
    }()
    var featuredIDs: Set<String> { Set(featured.map(\.id)) }

    init() {
        if let saved = UserDefaults.standard.array(forKey: "enabledFeeds.v2") as? [String], !saved.isEmpty {
            enabledIDs = Set(saved)
        } else {
            enabledIDs = FeedCatalog.defaultEnabled
        }
        articles = featured
    }

    var enabledSources: [FeedSource] { FeedCatalog.all.filter { enabledIDs.contains($0.id) } }

    func toggle(_ source: FeedSource) {
        if enabledIDs.contains(source.id) { enabledIDs.remove(source.id) } else { enabledIDs.insert(source.id) }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let sources = enabledSources
        var collected: [Article] = []
        var failed: Set<String> = []
        await withTaskGroup(of: (String, [Article]?).self) { group in
            for s in sources {
                group.addTask {
                    var req = URLRequest(url: s.url)
                    req.timeoutInterval = 10
                    req.setValue("Starling/1.0", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: req) else { return (s.id, nil) }
                    let items = RSSParser.parse(data: data, sourceID: s.id)
                    return (s.id, items.isEmpty ? nil : Array(items.prefix(60)))
                }
            }
            for await (id, items) in group {
                if let items { collected += items } else { failed.insert(id) }
            }
        }
        // Snapshot fallback for anything that failed.
        let snapshot = Snapshot.load()
        usedSnapshot = false
        for id in failed {
            let fallback = snapshot.filter { $0.sourceID == id }
            if !fallback.isEmpty { collected += fallback; usedSnapshot = true }
        }
        failedSourceIDs = failed
        // Interleave by source so one feed doesn't dominate.
        var bySource: [String: [Article]] = Dictionary(grouping: collected, by: \.sourceID)
        var merged: [Article] = []
        var seen: Set<String> = []
        while !bySource.isEmpty {
            for s in sources {
                guard var list = bySource[s.id], !list.isEmpty else { bySource[s.id] = nil; continue }
                let a = list.removeFirst()
                bySource[s.id] = list
                if seen.insert(a.id).inserted { merged.append(a) }
            }
        }
        let featuredSet = featuredIDs
        // Live items that exist in the bundled snapshot are swapped for the snapshot copy, so their
        // pre-generated editions and posters (keyed on the exact summary text) always resolve.
        let snapshotByID = Dictionary(uniqueKeysWithValues: Snapshot.load().map { ($0.id, $0) })
        let all = featured + merged.filter { !featuredSet.contains($0.id) }.map { snapshotByID[$0.id] ?? $0 }
        articles = Array(all.prefix(16))
        reserve = Array(all.dropFirst(16))
        lastRefresh = .now
    }

    /// Ensure the body is loaded. Returns the article with body populated when possible.
    func loadBody(for article: Article) async -> Article {
        if let body = article.body, body.count >= 2 { return article }
        var copy = article
        let (paras, og) = await ArticleExtractor.fetch(for: article)
        copy.body = paras.isEmpty ? [article.summary] : paras
        if copy.imageURL == nil, let og { copy.imageURL = og }
        if let idx = articles.firstIndex(where: { $0.id == article.id }) { articles[idx] = copy }
        return copy
    }
}

enum Snapshot {
    static func load() -> [Article] {
        guard let url = Bundle.main.url(forResource: "articles", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Article].self, from: data)) ?? []
    }
}
