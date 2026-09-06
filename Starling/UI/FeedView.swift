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
    @State private var modeChosen = false
    @State private var proposedMode: HomeMode?
    @State private var proposalSince: Date?

    private var theme: Theme { hub.theme }
    private var moving: Bool { [.walking, .running, .automotive].contains(hub.state.motion) }

    var body: some View {
        NavigationStack {
            homeContent
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
                // The home opens in the mode the rules want, then never swaps on its own: a change is proposed and the reader taps Switch.
                let wanted: HomeMode = rules.homeLayout(for: hub.state) == .stack ? .stack : .tiles
                if !modeChosen { mode = wanted; modeChosen = true; return }
                if wanted != mode {
                    if proposedMode != wanted { proposedMode = wanted; proposalSince = .now }
                } else { proposedMode = nil }
            }
            .safeAreaInset(edge: .bottom) { proposalBar }
        }
    }

    @ViewBuilder private var homeContent: some View {
        let bg: Color = mode == .stack ? Identity.night : theme.palette.background
        let scheme: ColorScheme = mode == .stack ? .dark : theme.palette.scheme
        Group {
            if mode == .stack { StackHome(mode: $mode, onManual: { proposedMode = nil }) }
            else { TileHome(mode: $mode, showSources: $showSources, showSettings: $showSettings, showSignals: $showSignals, onManual: { proposedMode = nil }) }
        }
        .background(bg.ignoresSafeArea())
        .environment(\.colorScheme, scheme)
    }

    @ViewBuilder private var proposalBar: some View {
        if let p = proposedMode, p != mode {
            HomeModeProposal(target: p, dark: mode == .stack,
                             onSwitch: { withAnimation { mode = p }; proposedMode = nil },
                             onDismiss: { proposedMode = nil })
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    func prefetch() {
        guard hub.phase == .live || !hub.isSensingEnabled || !hub.cameraSupported else { return }
        generator.prefetch(feeds.articles, state: hub.state, sources: feeds.enabledSources, feeds: feeds, images: imageGen, mood: PosterPrompts.mood(for: hub.theme.paletteName))
    }
}

func readTime(_ a: Article) -> String { "\(max(1, max(a.wordCount, 120) / 220)) MIN" }
func sourceName(_ a: Article) -> String { (FeedCatalog.source(a.sourceID)?.name ?? "").uppercased() }

/// Resolve art for a story: bundled hero, the publisher's image, or a pre-generated poster.
@MainActor
func storyArt(_ article: Article, generator: Generator, heroes: HeroImageStore, images: ImageGenerator) -> UIImage? {
    if let img = generator.heroImageName(for: article, edition: nil).flatMap(UIImage.init(named:)) { return img }
    if let img = heroes.image(for: article.imageURL) { return img }
    for m in ["focused", "calm"] {
        if let e = generator.bundled(article, .preset(m == "calm" ? .calm : .focused)),
           let p = PosterPrompts.prompts(edition: e, title: article.title, summary: article.summary, sourceName: FeedCatalog.source(article.sourceID)?.name ?? "Starling", mood: m).first ?? nil,
           let img = images.imageAnyMood(prompt: p, mood: m) { return img }
    }
    return nil
}

struct StoryArt: View {
    @Environment(HeroImageStore.self) private var heroes
    @Environment(Generator.self) private var generator
    @Environment(ImageGenerator.self) private var images
    let article: Article
    var mono = false
    var body: some View {
        Group {
            if let img = storyArt(article, generator: generator, heroes: heroes, images: images) {
                Color.clear.overlay(Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)).saturation(mono ? 0 : 1)
            } else {
                Identity.ink
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
                        RoundIconButton(symbol: "square.stack.3d.down.forward", theme: theme) { onManual(); withAnimation { mode = .stack } }
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
    @Environment(HeroImageStore.self) private var heroes
    @Environment(Generator.self) private var generator
    @Environment(ImageGenerator.self) private var images
    let article: Article
    var body: some View {
        let hasArt = storyArt(article, generator: generator, heroes: heroes, images: images) != nil
        VStack(spacing: 0) {
            if hasArt { StoryArt(article: article).frame(height: 200) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(1.2)
                    Text("·").foregroundStyle(Identity.grey)
                    Text(readTime(article)).font(Identity.grotesk(10, .medium)).tracking(1)
                }
                .foregroundStyle(Identity.ink)
                HStack(alignment: .bottom) {
                    Text(article.title).font(Identity.grotesk(hasArt ? 26 : 34, .heavy)).tracking(hasArt ? -0.8 : -1.4).lineSpacing(-2).lineLimit(hasArt ? 3 : 4).foregroundStyle(Identity.ink)
                    Spacer(minLength: 12)
                    ArrowDot(light: false)
                }
                if !hasArt, !article.summary.isEmpty {
                    Text(article.summary).font(Identity.serif(16)).lineSpacing(3).lineLimit(3).foregroundStyle(Identity.ink).padding(.top, 4)
                }
            }
            .padding(hasArt ? 14 : 18)
            .frame(minHeight: hasArt ? 0 : 200, alignment: .bottomLeading)
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
                StoryArt(article: article, mono: true).overlay(Color.black.opacity(0.3))
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
struct WideArt: View {
    @Environment(HeroImageStore.self) private var heroes
    @Environment(Generator.self) private var generator
    @Environment(ImageGenerator.self) private var images
    let article: Article
    var body: some View {
        if let img = storyArt(article, generator: generator, heroes: heroes, images: images) {
            HStack { Spacer(); Color.clear.overlay(Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)).frame(width: 150, height: 150).clipShape(Circle()).offset(x: 20, y: -20).opacity(0.9) }
        } else {
            HStack { Spacer(); Circle().fill(Identity.ink.opacity(0.85)).frame(width: 150, height: 150).offset(x: 40, y: -30) }
        }
    }
}

struct WideTile: View {
    let article: Article
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Identity.red
            WideArt(article: article)
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
    @State private var flying = false
    @State private var showSignals = false
    @State private var opened: Article?
    @State private var hintPhase = false

    private var colours: [Color] { [Identity.acid, Identity.cobalt, Identity.red] }
    private let peek: CGFloat = 34

    var body: some View {
        let a = feeds.articles
        VStack(spacing: 0) {
            HStack {
                StatePill(theme: hub.theme) { showSignals = true }
                Spacer()
                Text("\(a.isEmpty ? 0 : index + 1) / \(a.count)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Identity.warmWhite.opacity(0.6)).padding(.trailing, 8)
                RoundIconButton(symbol: "square.grid.2x2", theme: Theme(paletteName: .night, accentName: .sage, scale: .regular, typeface: .sans)) { onManual(); withAnimation { mode = .tiles } }
            }
            .padding(.horizontal, 16).padding(.top, 6)
            if a.isEmpty {
                Spacer(); ProgressView().tint(.white); Spacer()
            } else {
                GeometryReader { geo in
                    let cardH = geo.size.height - peek * 3 - 8
                    ZStack(alignment: .bottom) {
                        ForEach(Array((0..<min(4, a.count)).reversed()), id: \.self) { depth in
                            let i = (index + depth) % a.count
                            let progress = min(1, max(0, -drag / 160))   // how far the top card has been pushed
                            let d = CGFloat(depth)
                            // Cards behind rise into place as the top one leaves.
                            let lift = depth == 0 ? drag : -(d - progress) * peek
                            let scale = depth == 0 ? 1 - progress * 0.04 : 1 - (d - progress) * 0.035
                            StackCard(article: a[i], color: colours[i % colours.count], serif: i % colours.count != 0, height: cardH)
                                .onTapGesture { if depth == 0 { opened = a[i] } else { withAnimation(.snappy(duration: 0.35)) { index = i } } }
                                .frame(height: cardH)
                                .scaleEffect(scale, anchor: .top)
                                .rotationEffect(.degrees(depth == 0 ? Double(-drag / 60) : 0), anchor: .bottom)
                                .offset(y: lift)
                                .opacity(depth == 0 ? Double(1 - progress * 0.6) : 1)
                                .zIndex(Double(10 - depth))
                                .allowsHitTesting(!flying)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { v in
                                let dy = v.translation.height
                                drag = dy < 0 ? dy : dy * 0.25   // rubber-band on downward pulls
                            }
                            .onEnded { v in
                                let dy = v.translation.height
                                if dy < -70 || v.predictedEndTranslation.height < -220 { advance(count: a.count, height: geo.size.height) }
                                else if dy > 70 { withAnimation(.snappy(duration: 0.35)) { index = (index - 1 + a.count) % a.count; drag = 0 } }
                                else { withAnimation(.snappy(duration: 0.3)) { drag = 0 } }
                            })
                }
                .padding(.top, 14)
                HStack(spacing: 8) {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).offset(y: hintPhase ? -3 : 2)
                    Text("SWIPE UP FOR NEXT").font(Identity.grotesk(10, .semibold)).tracking(2)
                }
                .foregroundStyle(Identity.warmWhite.opacity(0.7))
                .padding(.vertical, 12)
                .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { hintPhase = true } }
            }
        }
        .sheet(isPresented: $showSignals) { SignalSheet(theme: hub.theme) }
        .navigationDestination(item: $opened) { ReaderView(article: $0) }
    }

    /// Fly the top card off the top, then bring the next one forward.
    private func advance(count: Int, height: CGFloat) {
        flying = true
        withAnimation(.easeIn(duration: 0.22)) { drag = -height }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            index = (index + 1) % count
            drag = 0
            flying = false
        }
    }
}

/// "You're walking — switch to cards?" A proposal, never an automatic swap.
struct HomeModeProposal: View {
    let target: HomeMode
    let dark: Bool
    let onSwitch: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: target == .stack ? "figure.walk" : "figure.seated.side").font(.system(size: 14, weight: .semibold))
            Text(target == .stack ? "Looks like you're on the move. Switch to cards?" : "You've settled. Switch to the tile view?")
                .font(Identity.grotesk(12, .semibold)).lineLimit(2)
            Spacer(minLength: 6)
            Button("Switch", action: onSwitch).font(Identity.grotesk(12, .bold)).padding(.horizontal, 12).padding(.vertical, 8).background(Identity.acid, in: Capsule()).foregroundStyle(Identity.ink)
            Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }.frame(width: 32, height: 32)
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8)
        .background(dark ? Color(white: 0.14) : Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Identity.rule.opacity(dark ? 0 : 1)))
        .foregroundStyle(dark ? Identity.warmWhite : Identity.ink)
        .buttonStyle(.plain)
    }
}

/// A magazine-cover card: flat colour, enormous headline, cinematic image in the lower third. Sized by the stack.
struct StackCard: View {
    let article: Article
    let color: Color
    let serif: Bool
    var height: CGFloat = 560
    private var ink: Color { color == Identity.acid ? Identity.ink : Identity.warmWhite }
    var body: some View {
        let imageH = max(150, height * 0.36)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(1.4)
                Spacer()
                Text(readTime(article)).font(Identity.grotesk(10, .bold)).tracking(1.2)
            }
            .foregroundStyle(ink)
            .padding(16)
            Text(serif ? article.title : article.title.uppercased())
                .font(serif ? Identity.serif(36, .regular) : Identity.grotesk(40, .black))
                .tracking(serif ? -0.5 : -1.8)
                .lineSpacing(serif ? -2 : -7)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .foregroundStyle(ink)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            ZStack(alignment: .bottomLeading) {
                StoryArt(article: article, mono: true)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom) {
                    Text(article.summary).font(Identity.serif(14)).lineLimit(2).foregroundStyle(Identity.warmWhite)
                    Spacer(minLength: 10)
                    ArrowDot(light: false)
                }
                .padding(16)
            }
            .frame(height: imageH)
            .frame(maxWidth: .infinity)
            .clipped()
            .background(Identity.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(LinearGradient(colors: [color, color.opacity(0.92), color.mix(with: .black, by: 0.35)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
