import SwiftUI

/// One idea per card. Progress segments on top, pastel card, big type, swipe hint. D direction.
struct CardsRenderer: View {
    @Environment(ImageGenerator.self) private var imageGen
    let edition: Edition
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

    var body: some View {
        let m = theme.metrics
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<cards.count, id: \.self) { i in
                    Capsule().fill(i <= page ? theme.ink : theme.surface).frame(height: 5)
                }
            }
            .padding(.horizontal, 20)
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, blocks in
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(i + 1) of \(cards.count) · \(edition.stateSummary)".uppercased())
                            .font(theme.font(11, weight: .bold)).tracking(0.6).foregroundStyle(theme.secondary)
                        if i == 0, let hero, !blocks.contains(where: { $0.type == .imageCard }) {
                            Image(uiImage: hero).resizable().aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Spacer(minLength: 0)
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                            if b.type == .imageCard {
                                ImageCardView(block: b, edition: edition, hero: hero, mood: mood, height: 240)
                            } else {
                                EditionRenderer.blockView(b, edition: edition, scale: 1.15, onReadFull: onReadFull)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            if i < cards.count - 1 {
                                Text("Swipe").font(theme.font(12, weight: .heavy)).foregroundStyle(theme.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.secondary)
                            }
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(theme.tiles[i % theme.tiles.count], in: RoundedRectangle(cornerRadius: 24))
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
        .onAppear { _ = m }
    }
}

/// An image card: a generated illustration or diagram when the edition asked for one, else the article's own image, else a symbol.
struct ImageCardView: View {
    @Environment(ImageGenerator.self) private var imageGen
    let block: Edition.Block
    let edition: Edition
    var hero: UIImage?
    var mood: String
    var height: CGFloat = 200
    private var theme: Theme { Theme.forEdition(edition) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let p = block.imagePrompt, !p.isEmpty, let img = imageGen.image(prompt: p, mood: mood) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else if let p = block.imagePrompt, !p.isEmpty, !imageGen.isFailed(prompt: p, mood: mood) {
                    ZStack {
                        theme.accent.opacity(0.14)
                        VStack(spacing: 8) {
                            ProgressView().tint(theme.ink)
                            Text("Drawing…").font(theme.font(11, weight: .bold)).foregroundStyle(theme.secondary)
                        }
                    }
                    .task { imageGen.request(prompt: p, mood: mood) }
                } else if let hero {
                    Image(uiImage: hero).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        theme.accent.opacity(0.14)
                        Image(systemName: (block.symbol.flatMap { UIImage(systemName: $0) != nil ? $0 : nil }) ?? "newspaper")
                            .font(.system(size: 44, weight: .light)).foregroundStyle(theme.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            if let c = block.caption, !c.isEmpty {
                Text(c).font(theme.font(13)).foregroundStyle(theme.secondary)
            }
        }
    }
}
