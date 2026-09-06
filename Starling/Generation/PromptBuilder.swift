import Foundation

enum GenerationIntent: Hashable {
    case adapt                 // from live state
    case longform              // the full story, designed for the current moment
    case preset(Preset)        // "show me the couch version"

    enum Preset: String, CaseIterable, Hashable {
        case commute, couch, focus
        var title: String {
            switch self {
            case .commute: return "Commute"
            case .couch: return "Couch"
            case .focus: return "Focus"
            }
        }
        var stateText: String {
            switch self {
            case .commute: return "motion: walking, posture: upright, attention: 0.45, stress_estimate: 0.65, predicted_state: tense (reader asked for the commute version)"
            case .couch: return "motion: stationary, posture: reclined, attention: 0.9, stress_estimate: 0.1, predicted_state: calm (reader asked for the couch version)"
            case .focus: return "motion: stationary, posture: upright, attention: 0.95, stress_estimate: 0.25, predicted_state: focused (reader asked for the focus version)"
            }
        }
    }

    var cacheKey: String {
        switch self {
        case .adapt: return "adapt"
        case .longform: return "longform"
        case .preset(let p): return "preset:" + p.rawValue
        }
    }
}

enum PromptBuilder {
    static func userMessage(article: Article, sources: [FeedSource], state: UserState, intent: GenerationIntent, feedback: [String]) -> String {
        let own = FeedCatalog.source(article.sourceID)
        var s = ""
        s += "READER STATE:\n"
        switch intent {
        case .adapt:
            s += state.promptSummary() + "\n"
        case .longform:
            s += state.promptSummary() + "\n"
            s += "REQUEST: the reader tapped 'Read full'. density MUST be longform, pace scroll. Keep the design suited to the time of day and state above, but do not shorten.\n"
        case .preset(let p):
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            s += "local_time: \(f.string(from: state.clock)) (\(state.timeOfDay.label))\n" + p.stateText + "\n"
        }
        s += "\nENABLED SOURCES (their house styles shape the voice):\n"
        for src in sources { s += "- \(src.name): \(src.style)\n" }
        if let own { s += "\nTHIS ARTICLE'S SOURCE: \(own.name) — \(own.style)\n" }
        if !feedback.isEmpty {
            s += "\nREADER FEEDBACK (highest priority):\n" + feedback.map { "- " + $0 }.joined(separator: "\n") + "\n"
        }
        s += "\nARTICLE TITLE: \(article.title)\n"
        if let d = article.published { s += "PUBLISHED: \(d.formatted(date: .abbreviated, time: .shortened))\n" }
        s += "ARTICLE TEXT:\n"
        s += (article.body ?? [article.summary]).joined(separator: "\n\n")
        return s
    }
}
