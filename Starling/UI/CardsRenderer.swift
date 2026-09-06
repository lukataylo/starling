import SwiftUI

/// Image-first story cards. Card 1: the headline over the cover image. Stat cards: a big figure and one line on a flat field.
/// Image cards: a generated illustration full-bleed with its caption. Everything else: big type on a tile.
struct CardsRenderer: View {
    @Environment(ImageGenerator.self) private var imageGen
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
    private func poster(_ i: Int) -> UIImage? {
        guard i < posters.count, let p = posters[i] else { return nil }
        return imageGen.imageAnyMood(prompt: p, mood: mood)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<cards.count, id: \.self) { i in
                    Capsule().fill(i <= page ? theme.ink : theme.surface).frame(height: 5)
                }
            }
            .padding(.horizontal, 20)
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, blocks in
                    card(i, blocks)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .padding(.horizontal, 16)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .padding(.top, 6)
        .foregroundStyle(theme.ink)
        .background(theme.palette.background)
        .environment(\.colorScheme, theme.palette.scheme)
        .task {
            for p in posters { if let p, imageGen.imageAnyMood(prompt: p, mood: mood) == nil { imageGen.request(prompt: p, mood: mood) } }
        }
    }

    @ViewBuilder private func card(_ i: Int, _ blocks: [Edition.Block]) -> some View {
        let tile = theme.tiles[i % theme.tiles.count]
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
                    .font(theme.font(11, weight: .bold)).tracking(0.6).foregroundStyle(theme.ink.opacity(0.7))
                Text(edition.posterHeadline ?? edition.headline)
                    .font(theme.font(38, weight: theme.heavy)).tracking(-1).lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack(spacing: 8) {
                    if posters.first != nil && !imageGen.isFailed(prompt: posters[0]!, mood: mood) {
                        ProgressView().tint(theme.ink).scaleEffect(0.8)
                        Text("Drawing poster…").font(theme.font(11, weight: .bold)).foregroundStyle(theme.secondary)
                    }
                    Spacer()
                    swipeHint(i, light: false)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.accent.opacity(theme.isDark ? 0.55 : 0.8))
        } else if b.type == .stat {
            VStack(alignment: .leading, spacing: 6) {
                Text(b.text ?? "").font(theme.font(76, weight: theme.heavy)).tracking(-2).minimumScaleFactor(0.5).lineLimit(1)
                Text(b.caption ?? b.items?.first ?? "").font(theme.font(24, weight: .semibold)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                swipeHint(i, light: false)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(i % 2 == 0 ? theme.accent.opacity(theme.isDark ? 0.55 : 0.75) : tile)
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
                Text("\(i + 1) of \(cards.count)").font(theme.font(11, weight: .bold)).tracking(0.6).foregroundStyle(theme.secondary)
                Spacer(minLength: 0)
                EditionRenderer.blockView(b, edition: edition, scale: 1.2, onReadFull: onReadFull)
                Spacer(minLength: 0)
                swipeHint(i, light: false)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                Text("Read full").font(theme.font(12, weight: .heavy)).onTapGesture { onReadFull?() }
            }
        }
        .foregroundStyle(light ? Color.white.opacity(0.8) : theme.secondary)
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
