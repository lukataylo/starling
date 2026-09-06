import SwiftUI

enum ReaderMode: Hashable { case adapted, preset(GenerationIntent.Preset), longform, original }

struct ReaderView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @Environment(HeroImageStore.self) private var heroes
    @Environment(Newsreader.self) private var newsreader
    @Environment(Bookmarks.self) private var bookmarks
    @Environment(\.dismiss) private var dismiss
    @State var article: Article
    @State private var bodyLoaded = false
    @State private var mode: ReaderMode = .adapted
    @State private var showWhy = false
    @State private var showCompare = false
    @State private var showSignals = false
    @State private var shownState: UserState?
    @State private var pendingState: UserState?
    @State private var pendingSince: Date?
    @State private var formatOverride: EditionFormat?
    @State private var cardPage = 0
    @State private var dockExpanded = false
    @State private var showCall = false
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
    private var theme: Theme {
        if let e = currentEdition, e.resolvedLayout == .zine, mode != .longform { return Theme(paletteName: .night, accentName: .sage, scale: .large, typeface: .sans) }
        return currentEdition.map(Theme.forEdition) ?? hub.theme
    }
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
                StatePill(theme: theme, badge: pendingChange != nil, suffix: currentEdition.map { $0.density == .glance || $0.density == .brief ? "Short edition" : "Article" }) { showSignals = true }
                Spacer()
                RoundIconButton(symbol: isKept ? "bookmark.fill" : "bookmark", theme: theme, filled: isKept) { keep() }
                RoundIconButton(symbol: "phone.fill", theme: theme, filled: newsreader.callState == .live) {
                    showCall = true
                    if newsreader.callState != .live { Task { await newsreader.startCall(article: article, state: liveState, currentVersion: modeTitle, sources: feeds.enabledSources) } }
                }
                Menu {
                    Button { keep() } label: { Label(isKept ? "Kept" : "Keep", systemImage: isKept ? "bookmark.fill" : "bookmark") }
                    Button { Task { await regenerate() } } label: { Label(isRegenerating ? "Regenerating…" : "Regenerate", systemImage: "arrow.clockwise") }
                    Button { showSignals = true } label: { Label("Not how I feel", systemImage: "face.smiling") }
                    Divider()
                    Button { showCompare = true } label: { Label("Compare generations", systemImage: "rectangle.split.2x1") }
                    Button { showWhy = true } label: { Label("Why this version", systemImage: "info.circle") }
                    Link(destination: article.link) { Label("Open in Safari", systemImage: "safari") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.ink).frame(width: 44, height: 44).background(theme.surface, in: Circle())
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)

            content
                .overlay(alignment: .bottomLeading) {
                    ModeFab(symbol: effectiveFormat == .cards ? "text.alignleft" : "rectangle.on.rectangle",
                            label: effectiveFormat == .cards ? "Short" : "Cards",
                            theme: theme) { flipFormat() }
                        .padding(.leading, 16).padding(.bottom, 12)
                }
        }
        .background(theme.palette.background.ignoresSafeArea())
        .environment(\.colorScheme, theme.palette.scheme)
        .animation(.easeInOut(duration: 0.5), value: theme.paletteName)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { dock }
        .sheet(isPresented: $showWhy) { WhyThisSheet(article: article, edition: currentEdition) }
        .sheet(isPresented: $showCompare) { CompareView(article: article) }
        .sheet(isPresented: $showCall) { CallSheet(article: article, theme: theme, onApply: { applyVersion($0) }) }
        .sheet(isPresented: $showSignals) {
            SignalSheet(theme: theme, mode: $mode, edition: currentEdition,
                        format: Binding(get: { effectiveFormat }, set: { formatOverride = $0 }),
                        pending: pendingChange,
                        pendingReady: pendingChange.map { generator.edition(for: article, intent: .adapt, state: $0) != nil } ?? false,
                        onSwitch: { if let p = pendingChange { switchTo(p) } },
                        onDismissPending: { pendingState = nil; pendingSince = nil },
                        onKeep: {
                            pendingState = nil
                            if let e = currentEdition { generator.addFeedback("At \(pageState.timeOfDay.label) while \(pageState.motion.rawValue) I kept: \(e.density.rawValue), \(e.palette.rawValue), \(e.typeface.rawValue), \(effectiveFormat.rawValue)") }
                        },
                        onWhy: { showWhy = true })
        }
        .task {
            heroes.load(article.imageURL)
            article = await feeds.loadBody(for: article)
            heroes.load(article.imageURL)
            bodyLoaded = true
            // Stage 1 of the voice pipeline starts the moment the story opens, so tapping Call is only the handshake.
            newsreader.author(article: article, sources: feeds.enabledSources)
            newsreader.onApplyVersion = { kind in applyVersion(kind) }
            if newsreader.callState == .live { await newsreader.moveTo(article: article, currentVersion: modeTitle) }
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
                CardsRenderer(edition: e, article: article, hero: heroImage, mood: mood, page: $cardPage, onReadFull: { mode = .longform })
                    .id(e.id)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if mode == .longform || (e.resolvedLayout == .article && mode != .adapted) {
                            articleSwitcher
                            ArticleView(edition: e, article: article, hero: heroImage)
                        } else {
                            ShortEditionView(edition: e, article: article, hero: heroImage,
                                             pendingText: pendingChange != nil ? "New version available" : nil,
                                             onPending: { showSignals = true },
                                             onReadFull: { mode = .longform })
                        }
                    }
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

    // MARK: dock — Cards · Short · Adapted · Original
    private var articleSwitcher: some View {
        HStack(spacing: 4) {
            segment("Focused", on: mode == .preset(.focused)) { mode = .preset(.focused) }
            segment("Calm", on: mode == .preset(.calm)) { mode = .preset(.calm) }
            segment("Original", on: mode == .original) { mode = .original }
        }
        .padding(4)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 22).padding(.top, 6)
    }

    @ViewBuilder private var dock: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.25)) { dockExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        if !dockExpanded { Text(modeTitle).font(Identity.grotesk(11, .semibold)) }
                        Image(systemName: dockExpanded ? "chevron.down" : "chevron.up").font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.ink.opacity(0.2)))
                    .foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain)
            }
            if dockExpanded {
            HStack(spacing: 4) {
                segment("Cards", on: effectiveFormat == .cards && mode != .longform && mode != .original) { if mode == .longform || mode == .original { mode = .adapted }; formatOverride = .cards }
                segment("Short", on: effectiveFormat == .text && mode != .longform && mode != .original) { if mode == .longform || mode == .original { mode = .adapted }; formatOverride = .text }
                segment("Adapted", on: mode == .longform) { mode = .longform }
                segment("Original", on: mode == .original) { mode = .original }
            }
            .padding(4)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6)
        .background(dockExpanded ? theme.palette.background : Color.clear)
    }

    private var modeTitle: String {
        switch mode {
        case .original: return "Original"
        case .longform: return "Adapted"
        default: return effectiveFormat == .cards ? "Cards" : "Short"
        }
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Identity.grotesk(12, .semibold)).tracking(-0.2)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(on ? theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(on ? theme.palette.background : theme.ink)
        }
        .buttonStyle(.plain)
    }

    private var isKept: Bool { bookmarks.contains(article) }

    /// Keep: save the story. Also tells the generator what was kept so the taste model learns from it.
    private func keep() {
        let saving = !isKept
        bookmarks.toggle(article)
        guard saving else { return }
        pendingState = nil
        if let e = currentEdition { generator.addFeedback("At \(pageState.timeOfDay.label) while \(pageState.motion.rawValue) I kept: \(e.density.rawValue), \(e.palette.rawValue), \(e.typeface.rawValue), \(effectiveFormat.rawValue)") }
    }

    /// The bottom-left fab: one tap flips cards ↔ short.
    private func flipFormat() {
        withAnimation(.snappy(duration: 0.3)) {
            let toText = effectiveFormat == .cards
            if mode == .longform || mode == .original { mode = .adapted }
            formatOverride = toText ? .text : .cards
        }
    }

    /// The newsreader's confirmed change, or the reader's tap on the proposal card.
    private func applyVersion(_ kind: String) {
        switch kind {
        case "cards": if mode == .longform || mode == .original { mode = .adapted }; formatOverride = .cards
        case "short", "text", "brief": if mode == .longform || mode == .original { mode = .adapted }; formatOverride = .text
        case "adapted", "full", "longform", "article": mode = .longform
        case "original": mode = .original
        default: break
        }
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
    @State private var isRegenerating = false
    /// Force a fresh generation of the current view from the live state — the judges' "do it again" button.
    private func regenerate() async {
        guard !isRegenerating else { return }
        if mode == .original { mode = .adapted }
        isRegenerating = true
        shownState = liveState; pendingState = nil; cardPage = 0
        await generator.generate(article: article, intent: intentForMode, state: liveState, sources: feeds.enabledSources, force: true)
        isRegenerating = false
    }
}

/// The reader hides the navigation bar, which switches off the interactive back swipe. Put it back.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { viewControllers.count > 1 }
}
