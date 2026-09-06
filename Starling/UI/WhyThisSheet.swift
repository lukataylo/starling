import SwiftUI

struct WhyThisSheet: View {
    @Environment(SignalHub.self) private var hub
    @Environment(Generator.self) private var generator
    @Environment(\.dismiss) private var dismiss
    let article: Article
    let edition: Edition?

    var body: some View {
        NavigationStack {
            List {
                if let e = edition {
                    Section("Why this version") {
                        Text(e.rationale)
                        LabeledContent("Noticed", value: e.stateSummary)
                        LabeledContent("Text", value: "\(e.density.rawValue), \(e.tone.rawValue) tone, \(e.pace.rawValue)")
                        LabeledContent("Design", value: "\(e.typeface.rawValue) \(e.typeScale.rawValue), \(e.palette.rawValue) + \(e.accent.rawValue), \(e.margins.rawValue) margins")
                    }
                }
                Section("What the phone sensed") {
                    let s = hub.state
                    LabeledContent("Predicted state", value: "\(s.label.rawValue) (\(Int(s.labelConfidence * 100))%)")
                    LabeledContent("Time", value: s.clock.formatted(date: .omitted, time: .shortened) + " · " + s.timeOfDay.label)
                    LabeledContent("Motion", value: "\(s.motion.rawValue), \(s.posture.rawValue)")
                    if s.sensingEnabled {
                        LabeledContent("Attention", value: s.faceDetected ? "\(Int(s.attention * 100))% on screen" : "no face detected")
                        LabeledContent("Blink rate", value: "\(Int(s.blinkRate)) / min")
                        if let bpm = s.bpm, s.bpmConfidence >= 0.4 {
                            LabeledContent("Heart rate", value: "\(Int(bpm)) bpm via \(s.pulseSource.rawValue) (\(Int(s.bpmConfidence * 100))%)")
                        } else {
                            LabeledContent("Heart rate", value: "calibrating — not used")
                        }
                        LabeledContent("Stress estimate", value: String(format: "%.2f", s.stress))
                        LabeledContent("Baseline", value: hub.baselineIsDefault ? "default 70 bpm" : "\(Int(hub.baselineBPM)) bpm")
                    } else {
                        Text("Sensing is off. Only time, motion and posture are used.").foregroundStyle(.secondary)
                    }
                }
                Section("Correct me") {
                    Picker("I actually feel", selection: Binding(get: { hub.labelOverride ?? hub.state.label }, set: { hub.labelOverride = $0 })) {
                        ForEach(ReaderLabel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    if hub.labelOverride != nil {
                        Button("Let the sensors decide again") { hub.labelOverride = nil }
                    }
                    HStack {
                        Button { generator.addFeedback("Liked the \(edition?.density.rawValue ?? "") \(edition?.palette.rawValue ?? "") version at \(hub.state.timeOfDay.label).") } label: { Label("Good call", systemImage: "hand.thumbsup") }
                        Spacer()
                        Button { generator.addFeedback("Disliked the \(edition?.density.rawValue ?? "") \(edition?.palette.rawValue ?? "") version at \(hub.state.timeOfDay.label); prefer something different next time.") } label: { Label("Not for me", systemImage: "hand.thumbsdown") }
                    }
                    .buttonStyle(.bordered)
                }
                if !generator.feedback.isEmpty {
                    Section("What it has learned from you") {
                        ForEach(generator.feedback, id: \.self) { Text($0).font(.caption) }
                        Button("Forget all", role: .destructive) { generator.feedback = [] }
                    }
                }
                if let l = generator.lastLatency {
                    Section("Generation") {
                        LabeledContent("Model", value: LLMClient.model)
                        LabeledContent("Last latency", value: String(format: "%.1fs", l))
                        Text(generator.lastUsage).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Why this version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
