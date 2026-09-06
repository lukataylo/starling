import SwiftUI

/// Renders an Edition through the genome. Applies palette and typeface to the whole page.
struct EditionRenderer: View {
    let edition: Edition
    var hero: UIImage? = nil
    var mood: String = "focused"
    var onReadFull: (() -> Void)? = nil

    private var palette: Palette { DesignGenome.palette(edition.palette) }
    private var accent: Color { DesignGenome.accent(edition.accent, palette: edition.palette) }
    private var design: Font.Design { DesignGenome.design(edition.typeface) }
    private var m: (body: CGFloat, headline: CGFloat, lineSpacing: CGFloat) {
        let base = DesignGenome.metrics(edition.typeScale)
        return (base.body * scale, base.headline * scale, base.lineSpacing * scale)
    }
    private var pad: CGFloat { DesignGenome.padding(edition.margins) }

    /// Shared block renderer used by both the page and the cards.
    static func blockView(_ b: Edition.Block, edition: Edition, scale: CGFloat = 1, onReadFull: (() -> Void)?) -> some View {
        var r = EditionRenderer(edition: edition, onReadFull: onReadFull)
        r.scale = scale
        return r.render(b)
    }
    var scale: CGFloat = 1

    /// Where the hero goes: the first imageCard, else right after the headline/dek.
    private var heroIndex: Int? {
        guard hero != nil else { return nil }
        // The hero goes after the headline; imageCards render their own (generated) image.
        var i = 0
        while i < edition.blocks.count, edition.blocks[i].type == .headline || edition.blocks[i].type == .dek { i += 1 }
        return i
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.lineSpacing * 2.2) {
            ForEach(Array(edition.blocks.enumerated()), id: \.offset) { i, block in
                if i == heroIndex, let hero {
                    if block.type == .imageCard {
                        heroView(hero, caption: block.caption)
                    } else {
                        heroView(hero, caption: nil)
                        render(block)
                    }
                } else {
                    render(block)
                }
            }
            if let hi = heroIndex, hi == edition.blocks.count, let hero { heroView(hero, caption: nil) }
        }
        .padding(.horizontal, pad)
        .padding(.vertical, pad * 0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.text)
        .background(palette.background)
        .environment(\.colorScheme, palette.scheme)
    }

    @ViewBuilder
    func render(_ b: Edition.Block) -> some View {
        switch b.type {
        case .headline:
            Text(b.text ?? "")
                .font(.system(size: m.headline, weight: DesignGenome.weight(edition.headlineWeight), design: design))
                .lineSpacing(m.lineSpacing * 0.6)
                .fixedSize(horizontal: false, vertical: true)
        case .dek:
            Text(b.text ?? "")
                .font(.system(size: m.body * 1.12, weight: .regular, design: design))
                .foregroundStyle(palette.secondary)
                .lineSpacing(m.lineSpacing)
        case .paragraph:
            Text(b.text ?? "")
                .font(.system(size: m.body, design: design))
                .lineSpacing(m.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        case .keyFacts:
            VStack(alignment: .leading, spacing: m.lineSpacing * 1.5) {
                ForEach(Array((b.items ?? []).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(accent).frame(width: 8, height: 8).offset(y: -2)
                        Text(item).font(.system(size: m.body * 1.05, weight: .medium, design: design)).lineSpacing(m.lineSpacing * 0.8)
                    }
                }
            }
            .padding(pad * 0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        case .pullQuote:
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4)
                Text(b.text ?? "")
                    .font(.system(size: m.body * 1.25, weight: .medium, design: design == .default ? .serif : design))
                    .italic()
                    .lineSpacing(m.lineSpacing)
            }
            .padding(.vertical, 4)
        case .imageCard:
            ImageCardView(block: b, edition: edition, hero: (b.imagePrompt ?? "").isEmpty ? hero : nil, mood: mood, height: 200 * scale)
        case .timeline:
            VStack(alignment: .leading, spacing: m.lineSpacing * 1.4) {
                ForEach(Array((b.items ?? []).enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            Circle().fill(accent).frame(width: 9, height: 9)
                            if i < (b.items?.count ?? 0) - 1 { Rectangle().fill(accent.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity) }
                        }
                        Text(item).font(.system(size: m.body * 0.95, design: design)).lineSpacing(m.lineSpacing * 0.6)
                    }
                }
            }
        case .takeaway:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(accent)
                Text(b.text ?? "").font(.system(size: m.body * 1.05, weight: .semibold, design: design)).lineSpacing(m.lineSpacing * 0.8)
            }
            .padding(pad * 0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        case .readFullPrompt:
            Button {
                onReadFull?()
            } label: {
                HStack {
                    Text(b.text ?? "Read the full story")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: m.body * 0.95, weight: .medium, design: design))
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    func heroView(_ img: UIImage, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 190 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .saturation(edition.palette == .night ? 0.6 : 1)
            if let caption, !caption.isEmpty {
                Text(caption).font(.system(size: m.body * 0.85, design: design)).foregroundStyle(palette.secondary)
            }
        }
    }

    private func validSymbol(_ s: String?) -> String {
        guard let s, UIImage(systemName: s) != nil else { return "newspaper" }
        return s
    }
}
