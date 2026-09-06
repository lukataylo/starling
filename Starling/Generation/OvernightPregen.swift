import Foundation
import Observation
import BackgroundTasks

/// Overnight pre-generation: while charging on wifi, pre-render the top stories from every enabled source
/// for the states this reader is most often in, so the morning feed is instant.
@Observable @MainActor
final class OvernightPregen {
    static let taskID = "com.lukadadiani.starling.overnight"
    var isEnabled: Bool { didSet { UserDefaults.standard.set(isEnabled, forKey: "overnight.enabled"); if isEnabled { schedule() } } }
    private(set) var isRunning = false
    private(set) var progress = ""
    private(set) var lastRun: Date? { didSet { UserDefaults.standard.set(lastRun, forKey: "overnight.lastRun") } }
    private(set) var lastSummary: String { didSet { UserDefaults.standard.set(lastSummary, forKey: "overnight.summary") } }

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "overnight.enabled") as? Bool ?? true
        lastRun = UserDefaults.standard.object(forKey: "overnight.lastRun") as? Date
        lastSummary = UserDefaults.standard.string(forKey: "overnight.summary") ?? ""
    }

    /// Register once at launch. The system calls the handler overnight when conditions are met.
    func register(feeds: FeedStore, generator: Generator, images: ImageGenerator, hub: SignalHub) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { [weak self] task in
            guard let self, let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            let work = Task { @MainActor in
                await self.run(feeds: feeds, generator: generator, images: images, hub: hub, postersFor: 3)
                task.setTaskCompleted(success: true)
                self.schedule()
            }
            task.expirationHandler = { work.cancel() }
        }
        if isEnabled { schedule() }
    }

    func schedule() {
        let req = BGProcessingTaskRequest(identifier: Self.taskID)
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = true
        // Next 2:00 am local time.
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = 2; comps.minute = 0
        var when = Calendar.current.date(from: comps) ?? .now
        if when < .now { when = Calendar.current.date(byAdding: .day, value: 1, to: when) ?? when }
        req.earliestBeginDate = when
        try? BGTaskScheduler.shared.submit(req)
    }

    /// The reader's common states: the two buckets seen most often, plus commute and calm as standing categories.
    func commonStates(hub: SignalHub) -> [(name: String, state: UserState)] {
        var out: [(String, UserState)] = []
        for (name, s) in hub.frequentStates().prefix(2) { out.append((name, s)) }
        var commute = UserState(); commute.motion = .walking; commute.posture = .upright; commute.label = .tense; commute.stress = 0.65; commute.attention = 0.45
        commute.clock = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: .now) ?? .now; commute.timeOfDay = .from(commute.clock)
        var calm = UserState(); calm.motion = .stationary; calm.posture = .reclined; calm.label = .calm; calm.stress = 0.1; calm.attention = 0.85
        calm.clock = Calendar.current.date(bySettingHour: 20, minute: 30, second: 0, of: .now) ?? .now; calm.timeOfDay = .from(calm.clock)
        if !out.contains(where: { $0.1.bucket == commute.bucket }) { out.append(("morning commute", commute)) }
        if !out.contains(where: { $0.1.bucket == calm.bucket }) { out.append(("calm evening", calm)) }
        return out
    }

    /// Pre-render: for every enabled source, the top `perSource` stories, for every common state. Posters for the first few.
    func run(feeds: FeedStore, generator: Generator, images: ImageGenerator, hub: SignalHub, perSource: Int = 3, postersFor: Int = 2) async {
        guard !isRunning, LLMClient.apiKey != nil else { return }
        isRunning = true
        defer { isRunning = false }
        if feeds.articles.isEmpty || (feeds.lastRefresh.map { Date().timeIntervalSince($0) > 1800 } ?? true) { await feeds.refresh() }
        let states = commonStates(hub: hub)
        var editionsMade = 0, postersQueued = 0
        var picked: [Article] = []
        for src in feeds.enabledSources {
            picked += feeds.articles.filter { $0.sourceID == src.id }.prefix(perSource)
        }
        for (ai, a) in picked.enumerated() {
            if Task.isCancelled { break }
            let full = await feeds.loadBody(for: a)
            for (name, s) in states {
                progress = "\(name): \(full.title.prefix(40))…"
                if generator.edition(for: full, intent: .adapt, state: s) == nil {
                    if await generator.generate(article: full, intent: .adapt, state: s, sources: feeds.enabledSources) != nil { editionsMade += 1 }
                }
                if ai < postersFor, let e = generator.edition(for: full, intent: .adapt, state: s) {
                    let mood = PosterPrompts.mood(for: e.palette)
                    for p in PosterPrompts.prompts(edition: e, title: full.title, summary: full.summary, sourceName: FeedCatalog.source(full.sourceID)?.name ?? "Starling", mood: mood) {
                        if let p, images.image(prompt: p, mood: mood) == nil { images.request(prompt: p, mood: mood); postersQueued += 1 }
                    }
                }
            }
        }
        generator.persist()
        lastRun = .now
        lastSummary = "\(picked.count) stories × \(states.count) states (\(states.map(\.name).joined(separator: ", "))): \(editionsMade) new editions, \(postersQueued) posters queued."
        progress = ""
    }
}
