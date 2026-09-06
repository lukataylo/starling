import SwiftUI

enum HomeMode: String { case tiles, stack }

struct FeedView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @Environment(HeroImageStore.self) private var heroes
    @Environment(ImageGenerator.self) private var imageGen
    @Environment(StateRules.self) private var rules
    @State private var showSources = false
    @State private var showSettings = false
    @State private var showSignals = false
    @State private var mode: HomeMode = .tiles
    @State private var manualModeUntilMotionChanges = false
    @State private var lastMoving = false

    private var theme: Theme { hub.theme }
    private var moving: Bool { [.walking, .running, .automotive].contains(hub.state.motion) }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .stack { StackHome(mode: $mode, onManual: { manualModeUntilMotionChanges = true }) }
                else { TileHome(mode: $mode, showSources: $showSources, showSettings: $showSettings, showSignals: $showSignals, onManual: { manualModeUntilMotionChanges = true }) }
            }
            .background((mode == .stack ? Identity.night : theme.palette.background).ignoresSafeArea())
            .environment(\.colorScheme, mode == .stack ? .dark : theme.palette.scheme)
            .animation(.easeInOut(duration: 0.35), value: mode)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Article.self) { article in ReaderView(article: article) }
            .sheet(isPresented: $showSources) { SourcePicker() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSignals) { SignalSheet(theme: theme) }
            .task { if feeds.articles.isEmpty { await feeds.refresh() } }
            .onChange(of: feeds.enabledIDs, initial: true) { _, ids in generator.sourceSignature = ids.sorted().joined(separator: ",") }
            .onChange(of: feeds.lastRefresh) { _, _ in prefetch(); feeds.articles.prefix(12).forEach { heroes.load($0.imageURL) } }
            .onChange(of: hub.phase) { _, p in if p == .live { prefetch() } }
            .onChange(of: hub.state.bucket) { _, _ in prefetch() }
            .onChange(of: hub.state.bucket, initial: true) { _, _ in
                // The per-state rules decide the home layout (stack when walking or tense by default). A manual choice sticks until motion changes.
                let m = moving
                if m != lastMoving { manualModeUntilMotionChanges = false; lastMoving = m }
                guard !manualModeUntilMotionChanges else { return }
                let wanted: HomeMode = rules.homeLayout(for: hub.state) == .stack ? .stack : .tiles
                if wanted != mode { withAnimation { mode = wanted } }
            }
        }
    }

    func prefetch() {
        guard hub.phase == .live || !hub.isSensingEnabled || !hub.cameraSupported else { return }
        generator.prefetch(feeds.articles, state: hub.state, sources: feeds.enabledSources, feeds: feeds, images: imageGen, mood: PosterPrompts.mood(for: hub.theme.paletteName))
    }
}

func readTime(_ a: Article) -> String { "\(max(1, max(a.wordCount, 120) / 220)) MIN" }
func sourceName(_ a: Article) -> String { (FeedCatalog.source(a.sourceID)?.name ?? "").uppercased() }

/// Story art: bundled generated hero, else the publisher's image.
struct StoryArt: View {
    @Environment(HeroImageStore.self) private var heroes
    @Environment(Generator.self) private var generator
    let article: Article
    var mono = false
    var body: some View {
        Group {
            if let img = generator.heroImageName(for: article, edition: nil).flatMap(UIImage.init(named:)) ?? heroes.image(for: article.imageURL) {
                Color.clear.overlay(Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)).saturation(mono ? 0 : 1)
            } else {
                Color.clear
            }
        }
        .clipped()
        .task { heroes.load(article.imageURL) }
    }
}

// MARK: - Screen 1: Tile view

struct TileHome: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(SignalHub.self) private var hub
    @Binding var mode: HomeMode
    @Binding var showSources: Bool
    @Binding var showSettings: Bool
    @Binding var showSignals: Bool
    let onManual: () -> Void
    private var theme: Theme { hub.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("Starling").font(Identity.grotesk(56, .black)).tracking(-3.5).foregroundStyle(theme.ink)
                    Spacer()
                    HStack(spacing: 6) {
                        RoundIconButton(symbol: "square.stack.3d.down.forward", theme: theme) { onManual(); mode = .stack }
                        RoundIconButton(symbol: "line.3.horizontal", theme: theme) { showSources = true }
                        RoundIconButton(symbol: "gearshape", theme: theme) { showSettings = true }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 16).padding(.top, 4)
                StatePill(theme: theme) { showSignals = true }.padding(.horizontal, 16).padding(.top, 2)

                if !feeds.failedSourceIDs.isEmpty {
                    Text((feeds.usedSnapshot ? "Couldn't reach some sources · showing saved stories" : "Couldn't reach some sources").uppercased())
                        .font(Identity.grotesk(10, .bold)).tracking(0.8).foregroundStyle(theme.secondary).padding(.horizontal, 16).padding(.top, 10)
                }

                if feeds.articles.isEmpty {
                    VStack(spacing: 10) {
                        if feeds.isLoading { ProgressView().tint(theme.ink) } else { Button("TRY AGAIN") { Task { await feeds.refresh() } }.font(Identity.grotesk(12, .bold)) }
                    }.frame(maxWidth: .infinity).padding(.top, 80).foregroundStyle(theme.ink)
                } else {
                    let a = feeds.articles
                    VStack(spacing: 4) {
                        ForEach(Array(stride(from: 0, to: a.count, by: 4)), id: \.self) { i in
                            NavigationLink(value: a[i]) { LeadTile(article: a[i]) }.buttonStyle(.plain)
                            if i + 1 < a.count {
                                HStack(spacing: 4) {
                                    NavigationLink(value: a[i + 1]) { HalfTile(article: a[i + 1], color: Identity.cobalt, graphic: true) }.buttonStyle(.plain)
                                    if i + 2 < a.count { NavigationLink(value: a[i + 2]) { HalfTile(article: a[i + 2], color: Identity.ink, graphic: false) }.buttonStyle(.plain) }
                                    else { Color.clear }
                                }
                            }
                            if i + 3 < a.count { NavigationLink(value: a[i + 3]) { WideTile(article: a[i + 3]) }.buttonStyle(.plain) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 14)
                }
            }
            .padding(.bottom, 30)
        }
        .refreshable { await feeds.refresh() }
    }
}

/// Full-width lead: dramatic photo, headline over a warm-white band at the bottom.
struct LeadTile: View {
    let article: Article
    var body: some View {
        VStack(spacing: 0) {
            StoryArt(article: article).frame(height: 200)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(1.2)
                    Text("·").foregroundStyle(Identity.grey)
                    Text(readTime(article)).font(Identity.grotesk(10, .medium)).tracking(1)
                }
                .foregroundStyle(Identity.ink)
                HStack(alignment: .bottom) {
                    Text(article.title).font(Identity.grotesk(26, .heavy)).tracking(-0.8).lineSpacing(-2).lineLimit(3).foregroundStyle(Identity.ink)
                    Spacer(minLength: 12)
                    ArrowDot(light: false)
                }
            }
            .padding(14)
            .background(Identity.warmWhite)
        }
        .overlay(Rectangle().strokeBorder(Identity.rule, lineWidth: 1))
    }
}

/// Half-width: cobalt graphic or dark photographic.
struct HalfTile: View {
    let article: Article
    let color: Color
    let graphic: Bool
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if graphic {
                color
                Circle().fill(Identity.ink.opacity(0.8)).frame(width: 110, height: 110).offset(x: 60, y: -110)
            } else {
                StoryArt(article: article, mono: true).overlay(Color.black.opacity(0.35))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(sourceName(article)).font(Identity.grotesk(9, .bold)).tracking(1.2)
                    Spacer()
                    Text(readTime(article)).font(Identity.grotesk(9, .medium)).tracking(1)
                }
                Text(article.title).font(Identity.grotesk(17, .heavy)).tracking(-0.5).lineSpacing(-1).lineLimit(4)
                HStack { Spacer(); ArrowDot(light: true) }
            }
            .foregroundStyle(Identity.warmWhite)
            .padding(12)
        }
        .frame(height: 210)
        .clipped()
    }
}

/// Wide deep-red tile with abstract art and oversized black type.
struct WideTile: View {
    let article: Article
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Identity.red
            HStack { Spacer(); StoryArt(article: article).frame(width: 150, height: 150).clipShape(Circle()).offset(x: 20, y: -20).opacity(0.9) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(sourceName(article)).font(Identity.grotesk(9, .bold)).tracking(1.2)
                    Text("·").opacity(0.6)
                    Text(readTime(article)).font(Identity.grotesk(9, .medium)).tracking(1)
                }
                .foregroundStyle(Identity.ink)
                HStack(alignment: .bottom) {
                    Text(article.title).font(Identity.grotesk(28, .black)).tracking(-1).lineSpacing(-3).lineLimit(3).foregroundStyle(Identity.ink).frame(maxWidth: 240, alignment: .leading)
                    Spacer()
                    ArrowDot(light: false)
                }
            }
            .padding(14)
        }
        .frame(height: 170)
        .clipped()
    }
}

// MARK: - Screen 2: Card stack

struct StackHome: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(SignalHub.self) private var hub
    @Binding var mode: HomeMode
    let onManual: () -> Void
    @State private var index = 0
    @State private var drag: CGFloat = 0
    @State private var showSignals = false

    private var colours: [Color] { [Identity.acid, Identity.cobalt, Identity.red] }

    var body: some View {
        let a = feeds.articles
        VStack(spacing: 0) {
            HStack {
                StatePill(theme: hub.theme) { showSignals = true }
                Spacer()
                RoundIconButton(symbol: "square.grid.2x2", theme: Theme(paletteName: .night, accentName: .sage, scale: .regular, typeface: .sans)) { onManual(); mode = .tiles }
            }
            .padding(.horizontal, 16).padding(.top, 6)
            if a.isEmpty {
                Spacer(); ProgressView().tint(.white); Spacer()
            } else {
                GeometryReader { geo in
                    let h = geo.size.height - 40
                    ZStack {
                        ForEach(Array((0..<min(4, a.count)).reversed()), id: \.self) { depth in
                            let i = (index + depth) % a.count
                            NavigationLink(value: a[i]) {
                                StackCard(article: a[i], color: colours[i % colours.count], serif: i % colours.count != 0)
                            }
                            .buttonStyle(.plain)
                            .frame(height: h)
                            .offset(y: CGFloat(depth) * -36 + (depth == 0 ? drag : 0))
                            .scaleEffect(1 - CGFloat(depth) * 0.02, anchor: .top)
                            .zIndex(Double(10 - depth))
                            .opacity(depth == 0 ? 1 : 1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16)
                    .gesture(DragGesture(minimumDistance: 12).onChanged { v in drag = min(0, v.translation.height) * 0.6 }
                        .onEnded { v in
                            if v.translation.height < -70 { withAnimation(.snappy(duration: 0.3)) { index = (index + 1) % a.count; drag = 0 } }
                            else if v.translation.height > 70 { withAnimation(.snappy(duration: 0.3)) { index = (index - 1 + a.count) % a.count; drag = 0 } }
                            else { withAnimation(.snappy) { drag = 0 } }
                        })
                }
                .padding(.top, 120)
                Text("SWIPE UP FOR NEXT  →").font(Identity.grotesk(10, .semibold)).tracking(2).foregroundStyle(Identity.warmWhite.opacity(0.7)).padding(.vertical, 14)
            }
        }
        .sheet(isPresented: $showSignals) { SignalSheet(theme: hub.theme) }
    }
}

/// A magazine-cover card: flat colour, enormous headline, cinematic image in the lower third.
struct StackCard: View {
    let article: Article
    let color: Color
    let serif: Bool
    private var ink: Color { color == Identity.acid ? Identity.ink : Identity.warmWhite }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(1.4)
                Spacer()
                Text(readTime(article)).font(Identity.grotesk(10, .bold)).tracking(1.2)
            }
            .foregroundStyle(ink)
            .padding(16)
            Text(serif ? article.title : article.title.uppercased())
                .font(serif ? Identity.serif(38, .regular) : Identity.grotesk(44, .black))
                .tracking(serif ? -0.5 : -2)
                .lineSpacing(serif ? -2 : -8)
                .lineLimit(5)
                .minimumScaleFactor(0.7)
                .foregroundStyle(ink)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            ZStack(alignment: .bottomLeading) {
                StoryArt(article: article, mono: true)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom) {
                    Text(article.summary).font(Identity.serif(15)).lineLimit(2).foregroundStyle(Identity.warmWhite)
                    Spacer(minLength: 10)
                    ArrowDot(light: false)
                }
                .padding(16)
            }
            .frame(height: 220)
            .background(Identity.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SourcePicker: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(FeedCatalog.all) { source in
                Button { feeds.toggle(source) } label: {
                    HStack {
                        Image(systemName: source.symbol).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(source.name)
                            Text(source.style).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if feeds.enabledIDs.contains(source.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .tint(.primary)
            }
            .navigationTitle("Your sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
