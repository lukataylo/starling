import SwiftUI

struct ReaderView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @State var article: Article
    @State private var bodyLoaded = false
    @State private var mode: Mode = .adapted
    @State private var showWhy = false
    @State private var showCompare = false
    @State private var showStatePicker = false
    @State private var pinnedBucket: String?   // "Keep this" freezes the edition while reading

    enum Mode { case adapted, longform, original }

    private var state: UserState { hub.state }
    private var adapted: Edition? { generator.edition(for: article, intent: .adapt, state: state) }
    private var longform: Edition? { generator.edition(for: article, intent: .longform, state: state) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                content
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StateChip(compact: true) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCompare = true } label: { Label("Compare generations", systemImage: "rectangle.split.2x1") }
                    Button { mode = .original } label: { Label("Original article", systemImage: "doc.plaintext") }
                    Button { Task { await regenerate() } } label: { Label("Regenerate now", systemImage: "arrow.clockwise") }
                    Link(destination: article.link) { Label("Open in Safari", systemImage: "safari") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showWhy) { WhyThisSheet(article: article, edition: currentEdition) }
        .sheet(isPresented: $showCompare) { CompareView(article: article) }
        .confirmationDialog("How do you feel right now?", isPresented: $showStatePicker, titleVisibility: .visible) {
            ForEach(ReaderLabel.allCases, id: \.self) { l in
                Button(l.rawValue.capitalized) { correctState(to: l) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            article = await feeds.loadBody(for: article)
            bodyLoaded = true
            await generator.generate(article: article, intent: .adapt, state: state, sources: feeds.enabledSources)
        }
        .onChange(of: state.bucket) { _, _ in
            // Live state changed: propose a new generation unless the reader pinned this one.
            guard bodyLoaded, mode == .adapted, pinnedBucket == nil else { return }
            Task { await generator.generate(article: article, intent: .adapt, state: state, sources: feeds.enabledSources) }
        }
    }

    private var currentEdition: Edition? {
        switch mode {
        case .adapted: return adapted
        case .longform: return longform
        case .original: return nil
        }
    }

    private var pageBackground: Color {
        if let e = currentEdition { return DesignGenome.palette(e.palette).background }
        return Color(.systemBackground)
    }

    @ViewBuilder private var header: some View {
        if mode == .adapted, let e = adapted {
            ProposalBanner(edition: e,
                           onReadFull: { Task { await readFull() } },
                           onKeep: { pinnedBucket = state.bucket; generator.addFeedback("At \(state.timeOfDay.label) while \(state.motion.rawValue) I liked: \(e.density.rawValue), \(e.palette.rawValue), \(e.typeface.rawValue)") },
                           onNotMe: { showStatePicker = true },
                           onWhy: { showWhy = true })
            .padding(.horizontal, 12).padding(.top, 8)
        } else if mode != .adapted {
            HStack {
                Label(mode == .longform ? "Full story, designed for now" : "Original article", systemImage: mode == .longform ? "text.book.closed" : "doc.plaintext")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Back to adapted") { mode = .adapted }.font(.caption)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .adapted:
            if let e = adapted {
                EditionRenderer(edition: e, onReadFull: { Task { await readFull() } })
                    .transition(.opacity)
            } else {
                generatingOrError(intent: .adapt)
            }
        case .longform:
            if let e = longform {
                EditionRenderer(edition: e)
            } else {
                generatingOrError(intent: .longform)
            }
        case .original:
            originalView
        }
    }

    @ViewBuilder private func generatingOrError(intent: GenerationIntent) -> some View {
        let status = generator.status(for: article, intent: intent, state: state)
        VStack(alignment: .leading, spacing: 12) {
            if case .failed(let why) = status {
                Label("Couldn't adapt this story", systemImage: "exclamationmark.triangle").font(.headline)
                Text(why).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Try again") { Task { await regenerate() } }
                    Button("Show original") { mode = .original }
                }.buttonStyle(.bordered)
                Divider()
                originalView
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(bodyLoaded ? "Writing this for \(state.timeOfDay.label), \(state.label.rawValue)…" : "Fetching the story…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                Text(article.title).font(.title2.bold())
                Text(article.summary).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var originalView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = FeedCatalog.source(article.sourceID) {
                Label(s.name, systemImage: s.symbol).font(.caption).foregroundStyle(.secondary)
            }
            Text(article.title).font(.title.bold())
            ForEach(Array((article.body ?? [article.summary]).enumerated()), id: \.offset) { _, p in
                Text(p)
            }
        }
        .padding()
    }

    private func readFull() async {
        mode = .longform
        await generator.generate(article: article, intent: .longform, state: state, sources: feeds.enabledSources)
    }

    private func regenerate() async {
        pinnedBucket = nil
        let intent: GenerationIntent = mode == .longform ? .longform : .adapt
        if mode == .original { mode = .adapted }
        await generator.generate(article: article, intent: intent, state: state, sources: feeds.enabledSources, force: true)
    }

    private func correctState(to label: ReaderLabel) {
        hub.labelOverride = label
        generator.addFeedback("When the app guessed '\(state.label.rawValue)' at \(state.timeOfDay.label) I actually felt '\(label.rawValue)'.")
        pinnedBucket = nil
        Task { await generator.generate(article: article, intent: .adapt, state: hub.state, sources: feeds.enabledSources, force: true) }
    }
}
