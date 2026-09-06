import Foundation
import Observation

/// Per-state layout rules the reader can edit. They are injected into the system prompt, so the interface is
/// promptable: change the text for "tense" and the next generation for a tense reader follows it.
@Observable @MainActor
final class StateRules {
    enum HomeLayout: String, Codable, CaseIterable { case auto, tiles, stack }

    struct Rule: Codable, Equatable {
        var instruction: String
        var home: HomeLayout
    }

    private(set) var rules: [ReaderLabel: Rule]
    var walkingRule: Rule { didSet { save() } }
    /// Free-form instruction that applies to every state, e.g. "I like cards in the morning".
    var customInstruction: String { didSet { save() } }

    static let defaults: [ReaderLabel: Rule] = [
        .calm: Rule(instruction: "Layout article: spacious, serif, generous leading, a pull quote, longer paragraphs allowed. Text format. Warm and reflective.", home: .tiles),
        .focused: Rule(instruction: "Layout article when standard or longform, quick when brief. Plain tone, clear section headings, key facts as a ruled grid. Text format.", home: .tiles),
        .tense: Rule(instruction: "Layout quick: compressed and poster-like. Glance or brief density, cards format, a stat first, key facts as short two-column blocks, no pull quote, reassuring tone, nothing alarming in the framing.", home: .stack),
        .tired: Rule(instruction: "Layout quick but gentle: large type, brief density, reassuring tone, one takeaway, no timeline. Cards format if it is late.", home: .stack),
        .distracted: Rule(instruction: "Layout quick: shorter blocks, a pull-quote hook, a stat, takeaway at the end. Cards format. Large type.", home: .stack),
    ]
    static let walkingDefault = Rule(instruction: "In motion: layout quick, cards format, glance or brief, large or xl type, key facts first, single pace. Format and legibility only — do not change tone for exertion.", home: .stack)

    init() {
        if let data = UserDefaults.standard.data(forKey: "stateRules.v1"), let saved = try? JSONDecoder().decode([String: Rule].self, from: data) {
            var r = Self.defaults
            for (k, v) in saved { if let l = ReaderLabel(rawValue: k) { r[l] = v } }
            rules = r
        } else { rules = Self.defaults }
        if let data = UserDefaults.standard.data(forKey: "stateRules.walking"), let w = try? JSONDecoder().decode(Rule.self, from: data) { walkingRule = w } else { walkingRule = Self.walkingDefault }
        customInstruction = UserDefaults.standard.string(forKey: "stateRules.custom") ?? ""
    }

    func rule(for label: ReaderLabel) -> Rule { rules[label] ?? Self.defaults[label]! }
    func set(_ r: Rule, for label: ReaderLabel) { rules[label] = r; save() }
    func reset() { rules = Self.defaults; walkingRule = Self.walkingDefault; customInstruction = ""; save() }

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: rules.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(try? JSONEncoder().encode(dict), forKey: "stateRules.v1")
        UserDefaults.standard.set(try? JSONEncoder().encode(walkingRule), forKey: "stateRules.walking")
        UserDefaults.standard.set(customInstruction, forKey: "stateRules.custom")
    }

    /// Home layout for the current state.
    func homeLayout(for s: UserState) -> HomeLayout {
        let moving = [.walking, .running, .automotive].contains(s.motion)
        let r = moving ? walkingRule : rule(for: s.label)
        if r.home != .auto { return r.home }
        return moving || s.label == .tense || s.label == .distracted ? .stack : .tiles
    }

    /// Text injected into the prompt for this state.
    func promptText(for s: UserState) -> String {
        let moving = [.walking, .running, .automotive].contains(s.motion)
        var lines = ["READER'S LAYOUT RULES (editable by the reader, they outrank the defaults):"]
        lines.append("- Current state '\(s.label.rawValue)': \(rule(for: s.label).instruction)")
        if moving { lines.append("- In motion: \(walkingRule.instruction)") }
        if !customInstruction.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("- Reader's own instruction: \(customInstruction)") }
        return lines.joined(separator: "\n")
    }

    /// Changes to rules must invalidate cached generations.
    var signature: String {
        let all = rules.values.map(\.instruction).joined() + walkingRule.instruction + customInstruction
        return String(all.hashValue)
    }
}
