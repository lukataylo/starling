import SwiftUI

enum ReaderMode: Hashable { case adapted, preset(GenerationIntent.Preset), longform, original }

struct ReaderView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @Environment(HeroImageStore.self) private var heroes
    @Environment(\.dismiss) private var dismiss
    @State var article: Article
    @State private var bodyLoaded = false
    @State private var mode: ReaderMode = .adapted
    @State private var showWhy = false
    @State private var showCompare = false
    @State private var showSignals = false
    @State private var showProposal = false
    @State private var shownState: UserState?
    @State private var pendingState: UserState?
    @State private var pendingSince: Date?
    @State private var formatOverride: EditionFormat?
    @State private var cardPage = 0
    private let stableAfter: TimeInterval = 5

    private var liveState: UserState { hub.state }
    private var pageState: UserState { shownState ?? liveState }
    private var adapted: Edition? { generator.edition(for: article, intent: .adapt, state: pageState) }
    private var longform: Edition? { generator.edition(for: article, intent: .longform, state: pageState) }

    private var currentEdition: Edition? {
        switch mode {
        case .adapted: return adapted
        case .preset(let p): return generator.edition(for: article, intent: .preset(p), state: pageState)
        case .longform: return longform
        case .original: return nil
        }
    }
    private var theme: Theme { currentEdition.map(Theme.forEdition) ?? hub.theme }
    private var effectiveFormat: EditionFormat {
        if mode == .longform || mode == .original { return .text }
        return formatOverride ?? currentEdition?.format ?? .text
    }
    private var heroImage: UIImage? {
        if let name = generator.heroImageName(for: article, edition: currentEdition), let img = UIImage(named: name) { return img }
        return heroes.image(for: article.imageURL)
    }
    private var mood: String {
        let calm: Set<PaletteName> = [.calm, .dusk, .night, .dawn]
        return calm.contains(theme.paletteName) ? "calm" : "focused"
    }
    private var pendingChange: UserState? {
        guard mode == .adapted, let p = pendingState, p.bucket != pageState.bucket else { return nil }
        return p
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RoundIconButton(symbol: "chevron.left", theme: theme) { dismiss() }
                StatePill(theme: theme) { showSignals = true }
                Spacer()
                RoundIconButton(symbol: "rectangle.split.2x1", theme: theme) { showCompare = true }
                Menu {
                    Button { mode = .original } label: { Label("Original article", systemImage: "doc.plaintext") }
                    Button { Task { await regenerate() } } label: { Label("Regenerate for now", systemImage: "arrow.clockwise") }
                    Button { showWhy = true } label: { Label("Why this version", systemImage: "info.circle") }
                    Link(destination: article.link) { Label("Open in Safari", systemImage: "safari") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.ink).frame(width: 44, height: 44).background(theme.surface, in: Circle())
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)

            content
        }
        .background(theme.palette.background.ignoresSafeArea())
        .environment(\.colorScheme, theme.palette.scheme)
        .animation(.easeInOut(duration: 0.5), value: theme.paletteName)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { dock }
        .sheet(isPresented: $showWhy) { WhyThisSheet(article: article, edition: currentEdition) }
        .sheet(isPresented: $showCompare) { CompareView(article: article) }
        .sheet(isPresented: $showSignals) { SignalSheet(mode: $mode) }
        .task {
            heroes.load(article.imageURL)
            article = await feeds.loadBody(for: article)
            heroes.load(article.imageURL)
            bodyLoaded = true
            shownState = liveState
            await generator.generate(article: article, intent: .adapt, state: liveState, sources: feeds.enabledSources)
        }
        .onChange(of: mode) { _, m in
            cardPage = 0
            switch m {
            case .longform: if longform == nil { Task { await readFull() } }
            case .preset(let p):
                if generator.edition(for: article, intent: .preset(p), state: pageState) == nil {
                    Task { await generator.generate(article: article, intent: .preset(p), state: pageState, sources: feeds.enabledSources) }
                }
            default: break
            }
        }
        .onChange(of: liveState.bucket) { _, _ in
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

    // MARK: content
    @ViewBuilder private var content: some View {
        if mode == .original {
            ScrollView { originalView }
        } else if let e = currentEdition {
            if effectiveFormat == .cards {
                CardsRenderer(edition: e, hero: heroImage, mood: mood, page: $cardPage, onReadFull: { mode = .longform })
                    .id(e.id)
            } else {
                ScrollView {
                    EditionRenderer(edition: e, hero: heroImage, mood: mood, onReadFull: { mode = .longform })
                        .id(e.id)
                        .transition(.opacity)
                }
            }
        } else {
            ScrollView { generatingOrError }
        }
    }

    private var intentForMode: GenerationIntent {
        switch mode {
        case .adapted, .original: return .adapt
        case .longform: return .longform
        case .preset(let p): return .preset(p)
        }
    }

    @ViewBuilder private var generatingOrError: some View {
        let status = generator.status(for: article, intent: intentForMode, state: pageState)
        VStack(alignment: .leading, spacing: 12) {
            if case .failed(let why) = status {
                Label("Couldn't adapt this story", systemImage: "exclamationmark.triangle").font(theme.font(17, weight: .bold))
                Text(why).font(theme.font(12)).foregroundStyle(theme.secondary)
                HStack {
                    Button("Try again") { Task { await regenerate() } }
                    Button("Show original") { mode = .original }
                }.buttonStyle(.bordered).tint(theme.accent)
                Divider()
                originalView
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(theme.ink)
                    Text(bodyLoaded ? "Writing this for \(pageState.timeOfDay.label), \(pageState.label.rawValue)…" : "Fetching the story…")
                        .font(theme.font(14, weight: .semibold)).foregroundStyle(theme.secondary)
                }
                if let img = heroImage {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(article.title).font(theme.font(24, weight: theme.heavy))
                Text(article.summary).font(theme.font(16)).foregroundStyle(theme.secondary)
            }
        }
        .foregroundStyle(theme.ink)
        .padding(20)
    }

    private var originalView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(FeedCatalog.source(article.sourceID)?.name ?? "") · ORIGINAL").font(theme.font(11, weight: .bold)).tracking(0.6).foregroundStyle(theme.secondary)
            Text(article.title).font(theme.font(26, weight: theme.heavy))
            if let img = heroImage {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            ForEach(Array((article.body ?? [article.summary]).enumerated()), id: \.offset) { _, p in
                Text(p).font(theme.font(17)).lineSpacing(5)
            }
        }
        .foregroundStyle(theme.ink)
        .padding(20)
    }

    // MARK: dock
    @ViewBuilder private var dock: some View {
        VStack(spacing: 10) {
            if let e = currentEdition, mode != .original {
                Button { showProposal = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(theme.accent)
                        Text(e.rationale).font(theme.font(13, weight: .bold)).lineLimit(1)
                        Spacer()
                        if pendingChange != nil { Circle().fill(theme.accent).frame(width: 8, height: 8) }
                        Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showProposal) {
                    ProposalSheet(edition: e,
                                  format: Binding(get: { effectiveFormat }, set: { formatOverride = $0 }),
                                  pending: pendingChange,
                                  pendingReady: pendingChange.map { generator.edition(for: article, intent: .adapt, state: $0) != nil } ?? false,
                                  onSwitch: { if let p = pendingChange { switchTo(p) } },
                                  onDismissPending: { pendingState = nil; pendingSince = nil },
                                  onReadFull: { mode = .longform },
                                  onKeep: {
                                      pendingState = nil
                                      generator.addFeedback("At \(pageState.timeOfDay.label) while \(pageState.motion.rawValue) I kept: \(e.density.rawValue), \(e.palette.rawValue), \(e.typeface.rawValue), \(effectiveFormat.rawValue)")
                                  },
                                  onNotMe: { showSignals = true },
                                  onWhy: { showWhy = true })
                }
            }
            HStack(spacing: 10) {
                dockButton("Cards", "rectangle.on.rectangle", on: effectiveFormat == .cards && mode != .longform && mode != .original) {
                    if mode == .longform || mode == .original { mode = .adapted }
                    formatOverride = .cards
                }
                dockButton("Text", "text.alignleft", on: effectiveFormat == .text && mode != .longform && mode != .original) {
                    if mode == .longform || mode == .original { mode = .adapted }
                    formatOverride = .text
                }
                dockButton("Full", "text.book.closed", on: mode == .longform) { mode = .longform }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .background(LinearGradient(colors: [theme.palette.background.opacity(0), theme.palette.background, theme.palette.background], startPoint: .top, endPoint: .bottom))
    }

    private func dockButton(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(theme.font(12, weight: .heavy))
            }
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(on ? theme.ink : theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(on ? theme.palette.background : theme.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: actions
    private func switchTo(_ s: UserState) {
        withAnimation(.easeInOut(duration: 0.35)) {
            shownState = s; pendingState = nil; pendingSince = nil; formatOverride = nil; cardPage = 0
        }
        Task { await generator.generate(article: article, intent: .adapt, state: s, sources: feeds.enabledSources) }
    }
    private func readFull() async {
        await generator.generate(article: article, intent: .longform, state: pageState, sources: feeds.enabledSources)
    }
    private func regenerate() async {
        if mode == .original { mode = .adapted }
        shownState = liveState; pendingState = nil
        await generator.generate(article: article, intent: intentForMode, state: liveState, sources: feeds.enabledSources, force: true)
    }
}
