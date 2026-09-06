import SwiftUI

struct ReaderView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @Environment(HeroImageStore.self) private var heroes
    @State var article: Article
    @State private var bodyLoaded = false
    @State private var mode: Mode = .adapted
    @State private var showWhy = false
    @State private var showCompare = false
    @State private var showStatePicker = false
    /// The state the page on screen was generated for. The page never swaps on its own.
    @State private var shownState: UserState?
    @State private var pendingState: UserState?
    @State private var pendingSince: Date?
    @State private var formatOverride: EditionFormat?
    @State private var showProposal = false
    private let stableAfter: TimeInterval = 5

    enum Mode: Hashable { case adapted, preset(GenerationIntent.Preset), longform, original }

    private var liveState: UserState { hub.state }
    private var pageState: UserState { shownState ?? liveState }
    private var adapted: Edition? { generator.edition(for: article, intent: .adapt, state: pageState) }
    private var longform: Edition? { generator.edition(for: article, intent: .longform, state: pageState) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                content
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { tray }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StateChip(compact: true) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCompare = true } label: { Label("Compare generations", systemImage: "rectangle.split.2x1") }
                    Button { mode = .original } label: { Label("Original article", systemImage: "doc.plaintext") }
                    Button { Task { await regenerate() } } label: { Label("Regenerate for now", systemImage: "arrow.clockwise") }
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
            heroes.load(article.imageURL)
            article = await feeds.loadBody(for: article)
            bodyLoaded = true
            shownState = liveState
            await generator.generate(article: article, intent: .adapt, state: liveState, sources: feeds.enabledSources)
        }
        .onChange(of: liveState.bucket) { _, _ in
            // Live state moved. Don't swap the page: wait until it is stable, prefetch, then propose.
            guard bodyLoaded, mode == .adapted, let shown = shownState else { return }
            if liveState.bucket == shown.bucket { pendingState = nil; pendingSince = nil; return }
            pendingState = liveState
            pendingSince = .now
            let candidate = liveState
            Task {
                try? await Task.sleep(for: .seconds(stableAfter))
                guard pendingState?.bucket == candidate.bucket else { return }
                await generator.generate(article: article, intent: .adapt, state: candidate, sources: feeds.enabledSources)
            }
        }
    }

    private var currentEdition: Edition? {
        switch mode {
        case .adapted: return adapted
        case .preset(let p): return generator.edition(for: article, intent: .preset(p), state: pageState)
        case .longform: return longform
        case .original: return nil
        }
    }

    private var heroImage: UIImage? {
        if let name = generator.heroImageName(for: article, edition: currentEdition), let img = UIImage(named: name) { return img }
        return heroes.image(for: article.imageURL)
    }

    private var pageBackground: Color {
        if let e = currentEdition { return DesignGenome.palette(e.palette).background }
        return Color(.systemBackground)
    }

    private var effectiveFormat: EditionFormat { formatOverride ?? currentEdition?.format ?? .text }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                modeChip("Now", .adapted, symbol: "sparkles")
                modeChip("Calm", .preset(.calm), symbol: "leaf")
                modeChip("Focused", .preset(.focused), symbol: "scope")
                modeChip("Full", .longform, symbol: "text.book.closed")
                modeChip("Original", .original, symbol: "doc.plaintext")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
        .onChange(of: mode) { _, m in
            switch m {
            case .longform: if longform == nil { Task { await readFull() } }
            case .preset(let p):
                if generator.edition(for: article, intent: .preset(p), state: pageState) == nil {
                    Task { await generator.generate(article: article, intent: .preset(p), state: pageState, sources: feeds.enabledSources) }
                }
            default: break
            }
        }
    }

    private func modeChip(_ title: String, _ m: Mode, symbol: String) -> some View {
        let selected = mode == m
        return Button {
            withAnimation(.snappy(duration: 0.25)) { mode = m }
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var pendingChange: UserState? {
        guard mode == .adapted, let p = pendingState, p.bucket != pageState.bucket else { return nil }
        return p
    }

    @ViewBuilder private var tray: some View {
        if mode == .adapted, let e = adapted {
            HStack {
                Spacer()
                ProposalButton(edition: e,
                               updateReady: pendingChange.map { generator.edition(for: article, intent: .adapt, state: $0) != nil } ?? false,
                               action: { showProposal = true })
                Spacer()
            }
            .padding(.bottom, 4)
            .sheet(isPresented: $showProposal) {
                ProposalSheet(edition: e,
                              format: Binding(get: { effectiveFormat }, set: { formatOverride = $0 }),
                              pending: pendingChange,
                              pendingReady: pendingChange.map { generator.edition(for: article, intent: .adapt, state: $0) != nil } ?? false,
                              onSwitch: { if let p = pendingChange { switchTo(p) } },
                              onDismissPending: { pendingState = nil; pendingSince = nil },
                              onReadFull: { Task { await readFull() } },
                              onKeep: {
                                  pendingState = nil
                                  generator.addFeedback("At \(pageState.timeOfDay.label) while \(pageState.motion.rawValue) I kept: \(e.density.rawValue), \(e.palette.rawValue), \(e.typeface.rawValue), \(effectiveFormat.rawValue)")
                              },
                              onNotMe: { showStatePicker = true },
                              onWhy: { showWhy = true })
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .adapted:
            if let e = adapted {
                if effectiveFormat == .cards {
                    CardsRenderer(edition: e, hero: heroImage, onReadFull: { Task { await readFull() } }).id(e.id)
                } else {
                    EditionRenderer(edition: e, hero: heroImage, onReadFull: { Task { await readFull() } }).id(e.id)
                }
            } else {
                generatingOrError(intent: .adapt)
            }
        case .preset(let p):
            if let e = generator.edition(for: article, intent: .preset(p), state: pageState) {
                if e.format == .cards {
                    CardsRenderer(edition: e, hero: heroImage, onReadFull: { Task { await readFull() } }).id(e.id)
                } else {
                    EditionRenderer(edition: e, hero: heroImage, onReadFull: { Task { await readFull() } }).id(e.id)
                }
            } else {
                generatingOrError(intent: .preset(p))
            }
        case .longform:
            if let e = longform {
                EditionRenderer(edition: e, hero: heroImage)
            } else {
                generatingOrError(intent: .longform)
            }
        case .original:
            originalView
        }
    }

    @ViewBuilder private func generatingOrError(intent: GenerationIntent) -> some View {
        let status = generator.status(for: article, intent: intent, state: pageState)
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
                    Text(bodyLoaded ? "Writing this for \(pageState.timeOfDay.label), \(pageState.label.rawValue)…" : "Fetching the story…")
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

    private func switchTo(_ s: UserState) {
        withAnimation(.easeInOut(duration: 0.35)) {
            shownState = s
            pendingState = nil
            pendingSince = nil
            formatOverride = nil
        }
        Task { await generator.generate(article: article, intent: .adapt, state: s, sources: feeds.enabledSources) }
    }

    private func readFull() async {
        mode = .longform
        await generator.generate(article: article, intent: .longform, state: pageState, sources: feeds.enabledSources)
    }

    private func regenerate() async {
        var intent: GenerationIntent = .adapt
        if case .preset(let p) = mode { intent = .preset(p) } else if mode == .longform { intent = .longform }
        if mode == .original { mode = .adapted }
        shownState = liveState
        pendingState = nil
        await generator.generate(article: article, intent: intent, state: liveState, sources: feeds.enabledSources, force: true)
    }

    private func correctState(to label: ReaderLabel) {
        hub.labelOverride = label
        generator.addFeedback("When the app guessed '\(pageState.label.rawValue)' at \(pageState.timeOfDay.label) I actually felt '\(label.rawValue)'.")
        Task {
            let s = hub.state
            shownState = s
            pendingState = nil
            await generator.generate(article: article, intent: .adapt, state: s, sources: feeds.enabledSources, force: true)
        }
    }
}

/// "Your state changed" — a proposal, never an automatic swap.
struct StateChangeProposal: View {
    let from: UserState
    let to: UserState
    let ready: Bool
    let onSwitch: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: to.label.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text("Now \(describe(to))").font(.caption.weight(.semibold))
                Text(ready ? "A version for this moment is ready." : "Preparing a version for this moment…").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Switch", action: onSwitch).disabled(!ready)
            Button { onDismiss() } label: { Image(systemName: "xmark") }
        }
        .font(.caption)
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.mini)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func describe(_ s: UserState) -> String {
        var parts: [String] = []
        if s.motion != from.motion { parts.append(s.motion == .stationary ? "still" : s.motion.rawValue) }
        if s.posture != from.posture && s.motion == .stationary { parts.append(s.posture.rawValue) }
        if s.label != from.label { parts.append(s.label.rawValue) }
        if s.timeOfDay != from.timeOfDay { parts.append(s.timeOfDay.label) }
        return parts.isEmpty ? "a different moment" : parts.joined(separator: ", ")
    }
}
