import SwiftUI

/// Two distinct generations of the same story, side by side, in the identity.
struct CompareView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    let article: Article
    @State private var right: GenerationIntent = .preset(.calm)

    private var options: [(String, GenerationIntent)] { [("Calm", .preset(.calm)), ("Focused", .preset(.focused)), ("Commute", .preset(.commute)), ("Adapted", .longform)] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TWO GENERATIONS").font(Identity.grotesk(12, .bold)).tracking(1.5)
                Spacer()
                Button("Done") { dismiss() }.font(Identity.grotesk(13, .semibold)).foregroundStyle(Identity.ink)
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)
            HStack(spacing: 4) {
                ForEach(options, id: \.0) { (title, intent) in
                    Button { right = intent } label: {
                        Text(title).font(Identity.grotesk(12, .semibold)).frame(maxWidth: .infinity).frame(height: 32)
                            .background(right == intent ? Identity.ink : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(right == intent ? Identity.warmWhite : Identity.ink)
                    }.buttonStyle(.plain)
                }
            }
            .padding(4).background(Color.white, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 16)
            Rectangle().fill(Identity.rule).frame(height: 1).padding(.top, 12)
            HStack(spacing: 0) {
                pane(title: "NOW · \(hub.state.label.rawValue.uppercased())", intent: .adapt)
                Rectangle().fill(Identity.rule).frame(width: 1)
                pane(title: options.first { $0.1 == right }?.0.uppercased() ?? "", intent: right)
            }
        }
        .background(Identity.warmWhite.ignoresSafeArea())
        .foregroundStyle(Identity.ink)
        .environment(\.colorScheme, .light)
        .task(id: right) {
            await generator.generate(article: article, intent: .adapt, state: hub.state, sources: feeds.enabledSources)
            await generator.generate(article: article, intent: right, state: hub.state, sources: feeds.enabledSources)
        }
    }

    @ViewBuilder private func pane(title: String, intent: GenerationIntent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Identity.grotesk(10, .bold)).tracking(1.4).padding(12)
            Rectangle().fill(Identity.rule).frame(height: 1)
            if let e = generator.edition(for: article, intent: intent, state: hub.state) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(e.resolvedLayout.rawValue) · \(e.density.rawValue) · \(e.tone.rawValue) · \(e.format.rawValue)".uppercased())
                            .font(Identity.grotesk(9, .bold)).tracking(1).foregroundStyle(Identity.grey)
                        Text(e.headline)
                            .font(e.resolvedLayout == .quick ? Identity.grotesk(22, .heavy) : Identity.serif(24))
                            .tracking(e.resolvedLayout == .quick ? -0.8 : -0.3).lineSpacing(-1).fixedSize(horizontal: false, vertical: true)
                        if let stat = e.blocks.first(where: { $0.type == .stat }) {
                            Text(stat.text ?? "").font(Identity.grotesk(34, .black)).tracking(-1.5)
                            Text(stat.caption ?? "").font(Identity.grotesk(12)).foregroundStyle(Identity.grey)
                        }
                        ForEach(Array(e.blocks.filter { $0.type == .keyFacts || $0.type == .paragraph || $0.type == .takeaway || $0.type == .dek }.prefix(3).enumerated()), id: \.offset) { _, b in
                            if let items = b.items {
                                ForEach(items, id: \.self) { it in
                                    HStack(alignment: .top, spacing: 6) { Rectangle().fill(Identity.acid).frame(width: 3, height: 14).padding(.top, 2); Text(it).font(Identity.grotesk(12)).lineSpacing(1) }
                                }
                            } else if let t = b.text {
                                Text(t).font(e.resolvedLayout == .quick ? Identity.grotesk(13) : Identity.serif(14)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Rectangle().fill(Identity.rule).frame(height: 1).padding(.top, 6)
                        Text(e.rationale).font(Identity.grotesk(11)).foregroundStyle(Identity.grey)
                    }
                    .padding(12)
                }
            } else {
                Spacer()
                if case .failed(let why) = generator.status(for: article, intent: intent, state: hub.state) {
                    Text(why).font(Identity.grotesk(11)).foregroundStyle(Identity.grey).padding()
                } else {
                    VStack(spacing: 8) { ProgressView().tint(Identity.ink); Text("GENERATING").font(Identity.grotesk(10, .bold)).tracking(1.2).foregroundStyle(Identity.grey) }
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
