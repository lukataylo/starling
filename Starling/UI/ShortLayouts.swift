import SwiftUI

// Short edition: one editorial system (ruled boxes, uppercase headings, number callouts), five arrangements.

private func splitFact(_ s: String) -> (String, String) {
    for sep in [" — ", " – ", ": "] {
        if let r = s.range(of: sep) { return (String(s[..<r.lowerBound]).uppercased(), String(s[r.upperBound...])) }
    }
    return ("", s)
}
private func factList(_ e: Edition) -> [(String, String)] {
    let f = e.blocks.filter { $0.type == .keyFacts }.flatMap { $0.items ?? [] }.map(splitFact)
    return f.enumerated().map { i, x in (x.0.isEmpty ? ["THE IDEA", "WHY NOW", "WHAT CHANGES", "THE CATCH", "WHAT NEXT", "THE DETAIL"][min(i, 5)] : x.0, x.1) }
}
private func paragraphs(_ e: Edition) -> [String] { e.blocks.filter { $0.type == .paragraph || $0.type == .takeaway }.compactMap(\.text) }
private func stat(_ e: Edition) -> (String, String)? { e.blocks.first { $0.type == .stat }.map { ($0.text ?? "", $0.caption ?? "") } }

/// A ruled 2-column grid of fact boxes. Numbered variant puts a big numeral in each box.
struct FactGrid: View {
    let facts: [(String, String)]
    let theme: Theme
    var rule: Color
    var numbered = false
    var headingColor: Color? = nil
    var maxItems = 4
    var body: some View {
        let items = Array(facts.prefix(maxItems))
        let rows = (items.count + 1) / 2
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { c in
                        let i = r * 2 + c
                        if i < items.count {
                            VStack(alignment: .leading, spacing: 6) {
                                if numbered {
                                    Text(String(format: "%02d", i + 1)).font(Identity.grotesk(30, .black)).tracking(-1.5).foregroundStyle(headingColor ?? theme.accent)
                                }
                                Text(items[i].0).font(Identity.grotesk(11, .bold)).tracking(0.9).foregroundStyle(headingColor ?? theme.ink)
                                Text(items[i].1).font(Identity.grotesk(14)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: numbered ? 120 : 92, alignment: .topLeading)
                            .overlay(alignment: .trailing) { if c == 0 { Rectangle().fill(rule).frame(width: 1) } }
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .overlay(alignment: .bottom) { if r < rows - 1 { Rectangle().fill(rule).frame(height: 1) } }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 1) }
    }
}

/// Big-number callout. Three shapes: a ruled row, a solid block, a circle badge.
struct StatCallout: View {
    enum Style { case row, block, circle }
    let value: String
    let caption: String
    let theme: Theme
    var style: Style = .row
    var field: Color? = nil
    var body: some View {
        switch style {
        case .row:
            HStack(alignment: .center, spacing: 14) {
                Text(value).font(Identity.grotesk(52, .black)).tracking(-2.5).minimumScaleFactor(0.5).lineLimit(1)
                Rectangle().fill(theme.ink).frame(width: 1, height: 44)
                Text(caption).font(Identity.grotesk(14)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((field ?? theme.accent).opacity(theme.isDark ? 0.25 : 0.22))
        case .block:
            let f = field ?? Identity.acid
            let ink: Color = (f == Identity.acid || f == Identity.warmWhite) ? Identity.ink : Identity.warmWhite
            VStack(alignment: .leading, spacing: 6) {
                Text(value).font(Identity.grotesk(84, .black)).tracking(-4).minimumScaleFactor(0.5).lineLimit(1)
                Text(caption.uppercased()).font(Identity.grotesk(12, .bold)).tracking(1).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(f)
            .foregroundStyle(ink)
        case .circle:
            HStack(spacing: 16) {
                Text(value).font(Identity.grotesk(28, .black)).tracking(-1.5).minimumScaleFactor(0.4).lineLimit(1)
                    .foregroundStyle(Identity.ink)
                    .frame(width: 110, height: 110)
                    .background(Identity.acid, in: Circle())
                Text(caption).font(Identity.grotesk(15, .semibold)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

struct ShortHeader: View {
    let edition: Edition
    let article: Article
    let theme: Theme
    var serifStandfirst = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(sourceName(article)).font(Identity.grotesk(11, .bold)).tracking(1.2)
                Text("·").foregroundStyle(theme.secondary)
                Text("\(max(1, edition.estimatedReadSeconds / 60)) MIN").font(Identity.grotesk(11, .medium)).tracking(1)
            }
            Text(edition.headline).font(theme.typeface == .serif ? Identity.serif(36, .semibold) : Identity.grotesk(36, .heavy)).tracking(theme.typeface == .serif ? -0.5 : -1.2).lineSpacing(-4).fixedSize(horizontal: false, vertical: true)
            if let dek = edition.blocks.first(where: { $0.type == .dek })?.text {
                Text(dek).font(serifStandfirst ? Identity.serif(19) : Identity.grotesk(17, .medium)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ShortFooter: View {
    let edition: Edition
    let theme: Theme
    var onReadFull: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(edition.rationale).font(Identity.grotesk(11)).foregroundStyle(theme.secondary)
            Button(action: { onReadFull?() }) {
                HStack { Text("ADAPTED").font(Identity.grotesk(11, .bold)).tracking(1.2); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }
            }.buttonStyle(.plain)
        }
    }
}

/// The five short arrangements.
struct ShortEditionView: View {
    let edition: Edition
    let article: Article
    var hero: UIImage?
    var pendingText: String? = nil
    var onPending: (() -> Void)? = nil
    var onReadFull: (() -> Void)? = nil
    private var theme: Theme { Theme.forEdition(edition) }
    private var rule: Color { theme.ink }

    var body: some View {
        let facts = factList(edition)
        let s = stat(edition)
        let paras = paragraphs(edition)
        VStack(alignment: .leading, spacing: 0) {
            switch edition.resolvedLayout {
            case .poster:
                // Number first: a solid callout block, then the headline, then the grid.
                if let s { StatCallout(value: s.0, caption: s.1, theme: theme, style: .block, field: theme.isDark ? Identity.acid : Identity.ink) }
                ShortHeader(edition: edition, article: article, theme: theme, serifStandfirst: false).padding(16)
                FactGrid(facts: facts, theme: theme, rule: rule)
                paragraphsView(paras, 1)
            case .dossier:
                // Numbered boxes with big numerals, stat as a circle badge.
                ShortHeader(edition: edition, article: article, theme: theme).padding(16)
                if let s { StatCallout(value: s.0, caption: s.1, theme: theme, style: .circle) }
                FactGrid(facts: facts, theme: theme, rule: rule, numbered: true)
                paragraphsView(paras, 1)
            case .split:
                // Colour block header with the headline reversed out and the number inside it, thick-ruled grid below.
                VStack(alignment: .leading, spacing: 12) {
                    Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(1.6).opacity(0.75)
                    Text(edition.headline).font(Identity.grotesk(38, .heavy)).tracking(-1.4).lineSpacing(-5).fixedSize(horizontal: false, vertical: true)
                    if let s {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(s.0).font(Identity.grotesk(48, .black)).tracking(-2).foregroundStyle(Identity.acid)
                            Text(s.1).font(Identity.grotesk(13)).opacity(0.85)
                        }
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.isDark ? Identity.cobalt : Identity.ink).foregroundStyle(Identity.warmWhite)
                FactGrid(facts: facts, theme: theme, rule: rule).overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 3) }
                paragraphsView(paras, 1)
            case .zine:
                // Dark ground, acid rules and headings, stat huge.
                ShortHeader(edition: edition, article: article, theme: theme, serifStandfirst: false).padding(16)
                if let s {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(s.0).font(Identity.grotesk(72, .black)).tracking(-3.5).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(Identity.acid)
                        Text(s.1.uppercased()).font(Identity.grotesk(12, .bold)).tracking(1).fixedSize(horizontal: false, vertical: true)
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
                FactGrid(facts: facts, theme: theme, rule: Identity.acid, headingColor: Identity.acid)
                paragraphsView(paras, 1)
            default:
                // Classic: hero strip, headline, serif standfirst, 2×2 grid, stat row.
                if let hero {
                    Color.clear.overlay(Image(uiImage: hero).resizable().aspectRatio(contentMode: .fill)).frame(height: 190).clipped()
                        .overlay(alignment: .topTrailing) {
                            if let pendingText {
                                Button(action: { onPending?() }) {
                                    HStack(spacing: 6) { Text(pendingText).font(Identity.grotesk(11, .semibold)); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)) }
                                        .padding(.horizontal, 12).padding(.vertical, 8).background(Identity.ink, in: Capsule()).foregroundStyle(Identity.warmWhite)
                                }.buttonStyle(.plain).padding(12)
                            }
                        }
                }
                ShortHeader(edition: edition, article: article, theme: theme).padding(16)
                FactGrid(facts: facts, theme: theme, rule: rule)
                if let s { StatCallout(value: s.0, caption: s.1, theme: theme, style: .row); Rectangle().fill(rule).frame(height: 1) }
                paragraphsView(paras, 2)
            }
            ShortFooter(edition: edition, theme: theme, onReadFull: onReadFull).padding(16)
        }
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(edition.resolvedLayout == .zine ? Identity.night : theme.palette.background)
        .padding(.bottom, 24)
    }

    @ViewBuilder private func paragraphsView(_ paras: [String], _ n: Int) -> some View {
        ForEach(Array(paras.prefix(n).enumerated()), id: \.offset) { _, p in
            Text(p).font(theme.typeface == .serif ? Identity.serif(16) : Identity.grotesk(15)).lineSpacing(3).padding(.horizontal, 16).padding(.top, 14).fixedSize(horizontal: false, vertical: true)
        }
    }
}
