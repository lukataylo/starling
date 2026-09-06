import SwiftUI

/// Renders an Edition through the genome. Applies palette and typeface to the whole page.
struct EditionRenderer: View {
    let edition: Edition
    var onReadFull: (() -> Void)? = nil

    private var palette: Palette { DesignGenome.palette(edition.palette) }
    private var accent: Color { DesignGenome.accent(edition.accent, palette: edition.palette) }
    private var design: Font.Design { DesignGenome.design(edition.typeface) }
    private var m: (body: CGFloat, headline: CGFloat, lineSpacing: CGFloat) { DesignGenome.metrics(edition.typeScale) }
    private var pad: CGFloat { DesignGenome.padding(edition.margins) }

    var body: some View {
        VStack(alignment: .leading, spacing: m.lineSpacing * 2.2) {
            ForEach(Array(edition.blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .padding(.horizontal, pad)
        .padding(.vertical, pad * 0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.text)
        .background(palette.background)
        .environment(\.colorScheme, palette.scheme)
    }

    @ViewBuilder
    private func render(_ b: Edition.Block) -> some View {
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
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: validSymbol(b.symbol))
                    .font(.system(size: m.headline * 1.3, weight: .light))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: m.headline * 2.6)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                if let c = b.caption, !c.isEmpty {
                    Text(c).font(.system(size: m.body * 0.85, design: design)).foregroundStyle(palette.secondary)
                }
            }
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

    private func validSymbol(_ s: String?) -> String {
        guard let s, UIImage(systemName: s) != nil else { return "newspaper" }
        return s
    }
}
