import SwiftUI

/// Two distinct generations of the same story, side by side.
struct CompareView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    let article: Article
    @State private var right: GenerationIntent = .preset(.couch)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Compare with", selection: $right) {
                    Text("Full story").tag(GenerationIntent.longform)
                    ForEach(GenerationIntent.Preset.allCases, id: \.self) { p in Text(p.title).tag(GenerationIntent.preset(p)) }
                }
                .pickerStyle(.segmented)
                .padding()
                HStack(spacing: 1) {
                    pane(title: "Now: \(hub.state.label.rawValue)", intent: .adapt)
                    pane(title: paneTitle(right), intent: right)
                }
            }
            .navigationTitle("Two generations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: right) {
                await generator.generate(article: article, intent: right, state: hub.state, sources: feeds.enabledSources)
            }
        }
    }

    private func paneTitle(_ i: GenerationIntent) -> String {
        switch i {
        case .longform: return "Full story"
        case .preset(let p): return p.title
        case .adapt: return "Now"
        }
    }

    @ViewBuilder private func pane(title: String, intent: GenerationIntent) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).padding(6).frame(maxWidth: .infinity).background(.thinMaterial)
            if let e = generator.edition(for: article, intent: intent, state: hub.state) {
                ScrollView {
                    EditionRenderer(edition: e)
                        .scaleEffect(0.62, anchor: .topLeading)
                        .frame(width: UIScreen.main.bounds.width / 2 / 0.62, alignment: .topLeading)
                        .frame(width: UIScreen.main.bounds.width / 2, alignment: .topLeading)
                    Spacer(minLength: 0)
                }
                .clipped()
                .background(DesignGenome.palette(e.palette).background)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.density.rawValue) · \(e.tone.rawValue) · \(e.typeface.rawValue) · \(e.palette.rawValue)")
                    Text(e.rationale).foregroundStyle(.secondary)
                }
                .font(.caption2)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
            } else {
                Spacer()
                if case .failed(let why) = generator.status(for: article, intent: intent, state: hub.state) {
                    Text(why).font(.caption2).foregroundStyle(.secondary).padding()
                } else {
                    ProgressView()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }
}
