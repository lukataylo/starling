import SwiftUI

/// The same Edition as swipeable cards: one block per card. For walking, standing, transport.
struct CardsRenderer: View {
    let edition: Edition
    var onReadFull: (() -> Void)? = nil
    @State private var page = 0

    private var palette: Palette { DesignGenome.palette(edition.palette) }
    private var accent: Color { DesignGenome.accent(edition.accent, palette: edition.palette) }
    private var design: Font.Design { DesignGenome.design(edition.typeface) }
    private var m: (body: CGFloat, headline: CGFloat, lineSpacing: CGFloat) { DesignGenome.metrics(edition.typeScale) }

    /// Group headline + dek into the first card; every other block is its own card.
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
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, blocks in
                    VStack(alignment: .leading, spacing: 18) {
                        Spacer(minLength: 0)
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                            EditionRenderer.blockView(b, edition: edition, scale: 1.15, onReadFull: onReadFull)
                        }
                        Spacer(minLength: 0)
                        HStack {
                            Text("\(i + 1) / \(cards.count)").font(.caption).foregroundStyle(palette.secondary)
                            Spacer()
                            if i < cards.count - 1 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(palette.secondary) }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 14)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: UIScreen.main.bounds.height * 0.66)
            HStack(spacing: 6) {
                ForEach(0..<cards.count, id: \.self) { i in
                    Capsule().fill(i == page ? accent : palette.secondary.opacity(0.3)).frame(width: i == page ? 18 : 6, height: 6)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .foregroundStyle(palette.text)
        .background(palette.background)
        .environment(\.colorScheme, palette.scheme)
    }
}
