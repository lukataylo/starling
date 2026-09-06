import SwiftUI

/// Split "HEADING — text" key facts into a heading and a body for the info grid.
private func splitFact(_ s: String) -> (String, String) {
    for sep in [" — ", " – ", ": "] {
        if let r = s.range(of: sep) { return (String(s[..<r.lowerBound]).uppercased(), String(s[r.upperBound...])) }
    }
    return ("", s)
}

/// Screen 3 — Quick edition: compressed, poster-like, easy to scan while walking.
struct QuickEditionView: View {
    let edition: Edition
    let article: Article
    var hero: UIImage?
    var pendingText: String? = nil
    var onPending: (() -> Void)? = nil
    var onReadFull: (() -> Void)? = nil
    private var theme: Theme { Theme.forEdition(edition) }
    private var rule: Color { theme.ink }
    private func head(_ size: CGFloat) -> Font { theme.typeface == .serif ? Identity.serif(size, .semibold) : Identity.grotesk(size, .heavy) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hero {
                Color.clear.overlay(Image(uiImage: hero).resizable().aspectRatio(contentMode: .fill))
                    .frame(height: 190).clipped()
                    .overlay(alignment: .topTrailing) {
                        if let pendingText {
                            Button(action: { onPending?() }) {
                                HStack(spacing: 6) { Text(pendingText).font(Identity.grotesk(11, .semibold)); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)) }
                                    .padding(.horizontal, 12).padding(.vertical, 8).background(Identity.ink, in: Capsule()).foregroundStyle(Identity.warmWhite)
                            }.buttonStyle(.plain).padding(12)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(sourceName(article)).font(Identity.grotesk(11, .bold)).tracking(1.2)
                    Text("·").foregroundStyle(theme.secondary)
                    Text("\(max(1, edition.estimatedReadSeconds / 60)) MIN").font(Identity.grotesk(11, .medium)).tracking(1)
                }
                .padding(.top, 16)
                Text(edition.headline).font(head(36)).tracking(theme.typeface == .serif ? -0.5 : -1.2).lineSpacing(-4).fixedSize(horizontal: false, vertical: true)
                if let dek = edition.blocks.first(where: { $0.type == .dek })?.text {
                    Text(dek).font(Identity.serif(19)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            Rectangle().fill(rule).frame(height: 1).padding(.top, 14)
            // Info grid from key facts + stat
            let facts = edition.blocks.filter { $0.type == .keyFacts }.flatMap { $0.items ?? [] }
            let stat = edition.blocks.first { $0.type == .stat }
            let paras = edition.blocks.filter { $0.type == .paragraph || $0.type == .takeaway }.compactMap(\.text)
            if !facts.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                    ForEach(Array(facts.prefix(4).enumerated()), id: \.offset) { i, f in
                        let (h, t) = splitFact(f)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(h.isEmpty ? "FACT \(i + 1)" : h).font(Identity.grotesk(11, .bold)).tracking(0.8)
                            Text(t).font(Identity.grotesk(14)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .overlay(alignment: .trailing) { if i % 2 == 0 { Rectangle().fill(rule).frame(width: 1) } }
                        .overlay(alignment: .bottom) { if i < 2 && facts.count > 2 { Rectangle().fill(rule).frame(height: 1) } }
                    }
                }
                Rectangle().fill(rule).frame(height: 1)
            }
            if let stat {
                HStack(alignment: .center, spacing: 14) {
                    Text(stat.text ?? "").font(Identity.grotesk(50, .black)).tracking(-2).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(theme.accent == Identity.acid ? theme.ink : theme.accent)
                    Rectangle().fill(rule).frame(width: 1, height: 44)
                    Text(stat.caption ?? "").font(Identity.grotesk(14)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(theme.isDark ? Color.white.opacity(0.06) : theme.accent.opacity(0.18))
                Rectangle().fill(rule).frame(height: 1)
            }
            ForEach(Array(paras.prefix(2).enumerated()), id: \.offset) { _, p in
                Text(p).font(Identity.grotesk(15)).lineSpacing(2).padding(.horizontal, 16).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
            }
            Text(edition.rationale).font(Identity.grotesk(11)).foregroundStyle(theme.secondary).padding(.horizontal, 16).padding(.top, 14)
            Button(action: { onReadFull?() }) {
                HStack { Text("FULL STORY").font(Identity.grotesk(11, .bold)).tracking(1.2); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }
            }
            .buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 10)
        }
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
    }
}

/// Screen 4 — Article: calm, spacious, literary.
struct ArticleView: View {
    let edition: Edition
    let article: Article
    var hero: UIImage?
    private var theme: Theme { Theme.forEdition(edition) }
    private var rule: Color { theme.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(2).padding(.top, 10)
            Text(edition.headline).font(theme.typeface == .serif ? Identity.serif(42, .regular) : Identity.grotesk(40, .heavy)).tracking(theme.typeface == .serif ? -0.8 : -1.5).lineSpacing(-4).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            if let dek = edition.blocks.first(where: { $0.type == .dek })?.text {
                Text(dek).font(Identity.serif(19)).lineSpacing(5).padding(.top, 14).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Text(FeedCatalog.source(article.sourceID)?.name ?? "").font(Identity.grotesk(11, .semibold))
                if let d = article.published { Text("·").foregroundStyle(theme.secondary); Text(d.formatted(.dateTime.day().month(.abbreviated))).font(Identity.grotesk(11)).tracking(0.5) }
            }
            .foregroundStyle(theme.secondary).padding(.top, 12)
            if let hero {
                Color.clear.overlay(Image(uiImage: img(hero)).resizable().aspectRatio(contentMode: .fill)).frame(height: 190).clipped().padding(.top, 18)
                if let cap = edition.blocks.first(where: { $0.type == .imageCard })?.caption {
                    Text(cap).font(Identity.grotesk(10)).foregroundStyle(theme.secondary).padding(.top, 6)
                }
            }
            let blocks = edition.blocks.filter { ![.headline, .dek, .imageCard, .readFullPrompt].contains($0.type) }
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                switch b.type {
                case .pullQuote:
                    HStack(alignment: .top, spacing: 14) {
                        Rectangle().fill(theme.accent).frame(width: 4)
                        Text("“\(b.text ?? "")”").font(Identity.serif(28)).italic().lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 22)
                    Rectangle().fill(rule).frame(height: 1)
                case .keyFacts, .timeline:
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array((b.items ?? []).enumerated()), id: \.offset) { _, it in
                            let (h, t) = splitFact(it)
                            VStack(alignment: .leading, spacing: 3) {
                                if !h.isEmpty { Text(h).font(Identity.grotesk(10, .bold)).tracking(1.6) }
                                Text(t).font(Identity.serif(17)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding(.top, 20)
                case .stat:
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.text ?? "").font(Identity.grotesk(44, .black)).tracking(-1.5)
                        Text(b.caption ?? "").font(Identity.grotesk(12)).foregroundStyle(theme.secondary)
                    }.padding(.top, 22)
                case .takeaway:
                    Text("WHAT IT MEANS").font(Identity.grotesk(10, .bold)).tracking(2).padding(.top, 26)
                    Text(b.text ?? "").font(Identity.serif(17)).lineSpacing(6).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                default:
                    if i == 0 || (i > 0 && blocks[i - 1].type == .pullQuote) {
                        Text(sectionTitle(i)).font(Identity.grotesk(10, .bold)).tracking(2).padding(.top, 26)
                    }
                    Text(b.text ?? "").font(Identity.serif(17)).lineSpacing(6).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }
    private func img(_ u: UIImage) -> UIImage { u }
    private func sectionTitle(_ i: Int) -> String { i == 0 ? "THE STORY" : "CONTINUED" }
}
