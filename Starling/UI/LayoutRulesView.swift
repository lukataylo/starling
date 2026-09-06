import SwiftUI

/// Edit the per-state rules the model follows. This is the "interface is never finished" control panel.
struct LayoutRulesView: View {
    @Environment(StateRules.self) private var rules
    @Environment(Generator.self) private var generator

    var body: some View {
        @Bindable var rules = rules
        Form {
            Section {
                TextField("e.g. When I'm tense, only cards, never more than four.", text: $rules.customInstruction, axis: .vertical).lineLimit(2...5)
            } header: { Text("Your own instruction") } footer: { Text("Applies to every state. Plain language; the model reads it verbatim.") }
            ForEach(ReaderLabel.allCases, id: \.self) { label in
                let r = rules.rule(for: label)
                Section(label.rawValue.capitalized) {
                    TextField("Layout instruction", text: Binding(get: { r.instruction }, set: { rules.set(.init(instruction: $0, home: r.home), for: label) }), axis: .vertical).lineLimit(3...8)
                    Picker("Home layout", selection: Binding(get: { r.home }, set: { rules.set(.init(instruction: r.instruction, home: $0), for: label) })) {
                        ForEach(StateRules.HomeLayout.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
            }
            Section("Walking / in transit") {
                TextField("Layout instruction", text: $rules.walkingRule.instruction, axis: .vertical).lineLimit(3...8)
                Picker("Home layout", selection: $rules.walkingRule.home) {
                    ForEach(StateRules.HomeLayout.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            Section {
                Button("Reset to defaults", role: .destructive) { rules.reset() }
            } footer: { Text("Edits regenerate stories the next time you open them. The genome vocabulary (palettes, typefaces, blocks, layouts) stays fixed; these rules decide how it is used.") }
        }
        .navigationTitle("Layout rules")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: rules.signature) { _, s in generator.rulesSignature = s }
    }
}
