import SwiftUI

/// Image-first story cards. Card 1: the headline over the cover image. Stat cards: a big figure and one line on a flat field.
/// Image cards: a generated illustration full-bleed with its caption. Everything else: big type on a tile.
struct CardsRenderer: View {
    @Environment(ImageGenerator.self) private var imageGen
    @Environment(Generator.self) private var generator
    let edition: Edition
    let article: Article
    var hero: UIImage? = nil
    var mood: String = "focused"
    @Binding var page: Int
    var onReadFull: (() -> Void)? = nil

    private var theme: Theme { Theme.forEdition(edition) }

    private var cards: [[Edition.Block]] {
        var out: [[Edition.Block]] = []
        var first: [Edition.Block] = []
        for b in edition.blocks {
            if b.type == .headline || b.type == .dek { first.append(b) } else { out.append([b]) }
        }
        if !first.isEmpty { out.insert(first, at: 0) }
        return out
    }

    private var coverPrompt: String { ImageGenerator.coverPrompt(headline: article.title, summary: article.summary) }
    private var cover: UIImage? { imageGen.image(prompt: coverPrompt, mood: mood) ?? hero }

    /// Poster prompts for the first two cards; nil when there's nothing to say.
    static func posterPrompts(edition: Edition, article: Article, mood: String) -> [String?] {
        PosterPrompts.prompts(edition: edition, title: article.title, summary: article.summary, sourceName: FeedCatalog.source(article.sourceID)?.name ?? "Starling", mood: mood)
    }
    private var posters: [String?] { Self.posterPrompts(edition: edition, article: article, mood: mood) }

    private static let amber = Color(red: 0.85, green: 0.55, blue: 0.10)
    private static let moss = Color(red: 0.25, green: 0.45, blue: 0.30)

    /// Tile colours follow the edition's palette; the set is rotated by the accent and the rationale so two regenerations in the same palette still look different.
    private var tileSet: [Color] {
        let base: [Color]
        switch edition.palette {
        case .day:   base = [Identity.cobalt, Identity.ink, Identity.acid, Self.amber]
        case .focus: base = [Identity.ink, Identity.acid, Identity.cobalt, Self.amber]
        case .dawn:  base = [Self.amber, Identity.ink, Identity.acid, Identity.cobalt]
        case .calm:  base = [Self.moss, Identity.ink, Identity.acid, Identity.cobalt]
        case .dusk:  base = [Identity.cobalt, Self.moss, Identity.ink, Identity.acid]
        case .night: base = [Identity.ink, Identity.cobalt, Identity.acid, Self.moss]
        }
        let accentIndex = AccentName.allCases.firstIndex(of: edition.accent) ?? 0
        let shift = (Self.stableHash(edition.rationale) + accentIndex) % base.count
        return Array(base[shift...] + base[..<shift])
    }
    /// Deterministic across launches (String.hashValue is seeded per process).
    private static func stableHash(_ s: String) -> Int {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Int(h % 1000)
    }
    private func tile(_ i: Int) -> Color { tileSet[i % tileSet.count] }
    /// Light tiles take ink; everything else takes warm white.
    private func isLight(_ color: Color) -> Bool { color == Identity.acid || color == Self.amber }
    /// Keep every card to roughly five lines: cap words per block and items per list.
    private func trimmed(_ b: Edition.Block) -> Edition.Block {
        func cap(_ s: String, _ n: Int) -> String {
            let w = s.split(separator: " ")
            return w.count <= n ? s : w.prefix(n).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters) + "…"
        }
        var t = b
        if let text = b.text, b.type != .headline { t = Edition.Block(type: b.type, text: cap(text, 38), items: b.items, symbol: b.symbol, caption: b.caption, imagePrompt: b.imagePrompt) }
        if let items = t.items { t = Edition.Block(type: t.type, text: t.text, items: Array(items.prefix(3)).map { cap($0, 14) }, symbol: t.symbol, caption: t.caption, imagePrompt: t.imagePrompt) }
        return t
    }

    private func fg(on color: Color) -> Color { isLight(color) ? Identity.ink : Identity.warmWhite }
    private func fgSecondary(on color: Color) -> Color { isLight(color) ? Identity.ink.opacity(0.65) : Identity.warmWhite.opacity(0.7) }
    /// Card i's poster: the current edition's own, else the story's pre-generated poster for this mood (then the other mood).
    private func poster(_ i: Int) -> UIImage? {
        if i < posters.count, let p = posters[i], let img = imageGen.imageAnyMood(prompt: p, mood: mood) { return img }
        let src = FeedCatalog.source(article.sourceID)?.name ?? "Starling"
        for m in (mood == "calm" ? ["calm", "focused"] : ["focused", "calm"]) {
            guard let e = generator.bundled(article, .preset(m == "calm" ? .calm : .focused)) else { continue }
            let ps = PosterPrompts.prompts(edition: e, title: article.title, summary: article.summary, sourceName: src, mood: m)
            if i < ps.count, let p = ps[i], let img = imageGen.imageAnyMood(prompt: p, mood: m) { return img }
        }
        return nil
    }
    /// Only draw on demand when there is no pre-generated poster to fall back to.
    private var hasBundledPosters: Bool {
        generator.bundled(article, .preset(.calm)) != nil || generator.bundled(article, .preset(.focused)) != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<cards.count, id: \.self) { i in
                    Capsule().fill(i <= page ? theme.ink : theme.surface).frame(height: 5)
                }
            }
            .padding(.horizontal, 20)
            // Every card is exactly 2:3, the posters' ratio, sized to the space available, so nothing is cropped.
            GeometryReader { geo in
                let maxW = geo.size.width - 32
                let h = min(geo.size.height - 8, maxW * 1.5)
                let w = min(maxW, h / 1.5)
                TabView(selection: $page) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { i, blocks in
                        card(i, blocks)
                            .environment(\.colorScheme, isLight(tile(i)) || i == 0 ? .light : .dark)
                            .frame(width: w, height: h)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .padding(.top, 6)
        .foregroundStyle(theme.ink)
        .background(theme.palette.background)
        .environment(\.colorScheme, theme.palette.scheme)
        .task {
            guard !hasBundledPosters else { return }
            for p in posters { if let p, imageGen.imageAnyMood(prompt: p, mood: mood) == nil { imageGen.request(prompt: p, mood: mood) } }
        }
    }

    @ViewBuilder private func card(_ i: Int, _ blocks: [Edition.Block]) -> some View {
        let tile = tile(i)
        let b = blocks.first!
        if i < 2, let img = poster(i) {
            // Fully generated poster: the type is in the image.
            Color.clear
                .overlay(Image(uiImage: img).resizable().aspectRatio(contentMode: .fill))
                .clipped()
                .overlay(alignment: .bottomTrailing) { swipeHint(i, light: true).padding(22) }
                .background(tile)
        } else if i == 0 {
            // Cover: headline over the image
            // Poster not ready yet: a clean typographic card in the same spirit, never the scraped photo.
            VStack(alignment: .leading, spacing: 12) {
                Text("\(FeedCatalog.source(article.sourceID)?.name ?? "")".uppercased())
                    .font(theme.font(11, weight: .bold)).tracking(0.6).foregroundStyle(Identity.ink.opacity(0.7))
                Text(edition.posterHeadline ?? edition.headline)
                    .font(theme.font(38, weight: theme.heavy)).tracking(-1).lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if UserDefaults.standard.bool(forKey: "devMode"), let p = posters.first ?? nil {
                    Text("mood \(mood) · poster_\(PosterPrompts.key(p, mood: mood)) · bundled \(hasBundledPosters ? "yes" : "no") · \(ImageGenerator.bundled(PosterPrompts.key(p, mood: mood)) == nil ? "not in bundle" : "in bundle")")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Identity.ink.opacity(0.6))
                }
                HStack(spacing: 8) {
                    if !hasBundledPosters, posters.first != nil, !imageGen.isFailed(prompt: posters[0]!, mood: mood) {
                        ProgressView().tint(theme.ink).scaleEffect(0.8)
                        Text("Drawing poster…").font(theme.font(11, weight: .bold)).foregroundStyle(Identity.ink.opacity(0.65))
                    }
                    Spacer()
                    swipeHint(i, light: false)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(Identity.ink)
            .background(Identity.acid)
        } else if b.type == .stat {
            VStack(alignment: .leading, spacing: 6) {
                Text(b.text ?? "").font(theme.font(76, weight: theme.heavy)).tracking(-2).minimumScaleFactor(0.5).lineLimit(1)
                Text(b.caption ?? b.items?.first ?? "").font(theme.font(24, weight: .semibold)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                swipeHint(i, light: false)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(fg(on: i % 2 == 0 ? Identity.acid : tile))
            .background(i % 2 == 0 ? Identity.acid : tile)
        } else if b.type == .imageCard {
            Color.clear
                .overlay(ImageCardFill(block: b, edition: edition, hero: nil, mood: mood))
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let c = b.caption, !c.isEmpty { Text(c).font(theme.font(20, weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true) }
                        swipeHint(i, light: true)
                    }
                    .padding(22)
                }
                .background(tile)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(i + 1) of \(cards.count)").font(theme.font(11, weight: .bold)).tracking(0.6).foregroundStyle(fgSecondary(on: tile))
                Spacer(minLength: 0)
                let words = ((b.text ?? "") + " " + (b.items ?? []).joined(separator: " ")).split(separator: " ").count
                let scale: CGFloat = words <= 14 ? 2.1 : (words <= 26 ? 1.75 : (words <= 40 ? 1.45 : 1.25))
                EditionRenderer.blockView(trimmed(b), edition: edition, scale: scale, onReadFull: onReadFull)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(7)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                swipeHint(i, light: !isLight(tile))
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(fg(on: tile))
            .background(tile)
        }
    }

    private func swipeHint(_ i: Int, light: Bool) -> some View {
        HStack {
            Spacer()
            if i < cards.count - 1 {
                Text("Swipe").font(theme.font(12, weight: .heavy))
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
            } else {
                Text("Adapted").font(theme.font(12, weight: .heavy)).onTapGesture { onReadFull?() }
            }
        }
        .foregroundStyle(light ? Color.white.opacity(0.85) : Identity.ink.opacity(0.65))
    }
}

/// Full-bleed image for an image card: generated from the prompt, else the article's image, else an accent field.
struct ImageCardFill: View {
    @Environment(ImageGenerator.self) private var imageGen
    let block: Edition.Block
    let edition: Edition
    var hero: UIImage?
    var mood: String
    private var theme: Theme { Theme.forEdition(edition) }
    var body: some View {
        Group {
            if let p = block.imagePrompt, !p.isEmpty, let img = imageGen.imageAnyMood(prompt: p, mood: mood) {
                Color.clear.overlay(Image(uiImage: img).resizable().aspectRatio(contentMode: .fill))
            } else if let p = block.imagePrompt, !p.isEmpty, !imageGen.isFailed(prompt: p, mood: mood) {
                ZStack {
                    theme.accent.opacity(0.2)
                    VStack(spacing: 8) { ProgressView().tint(theme.ink); Text("Drawing…").font(theme.font(11, weight: .bold)).foregroundStyle(theme.secondary) }
                }
                .task { imageGen.request(prompt: p, mood: mood) }
            } else if let hero {
                Color.clear.overlay(Image(uiImage: hero).resizable().aspectRatio(contentMode: .fill))
            } else {
                ZStack { theme.accent.opacity(0.25); Image(systemName: "photo").font(.system(size: 40, weight: .light)).foregroundStyle(theme.accent) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// Inline image card for the text page.
struct ImageCardView: View {
    let block: Edition.Block
    let edition: Edition
    var hero: UIImage?
    var mood: String
    var height: CGFloat = 200
    private var theme: Theme { Theme.forEdition(edition) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ImageCardFill(block: block, edition: edition, hero: hero, mood: mood)
                .frame(maxWidth: .infinity).frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if let c = block.caption, !c.isEmpty {
                Text(c).font(theme.font(13)).foregroundStyle(theme.secondary)
            }
        }
    }
}
