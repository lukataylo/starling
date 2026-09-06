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
                HStack { Text("ADAPTED").font(Identity.grotesk(11, .bold)).tracking(1.2); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }
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
                    if i == 0 || (i > 0 && blocks[i - 1].type == .pullQuote) || i % 4 == 0 {
                        Text(sectionTitle(i)).font(Identity.grotesk(10, .bold)).tracking(2).padding(.top, 28)
                        Rectangle().fill(theme.ink.opacity(0.25)).frame(height: 1).padding(.top, 6)
                    }
                    Text(b.text ?? "")
                        .font(theme.typeface == .serif ? Identity.serif(i == 0 ? 19 : 17) : Identity.grotesk(i == 0 ? 18 : 16))
                        .lineSpacing(theme.typeface == .serif ? 7 : 5)
                        .padding(.top, i == 0 ? 14 : 16)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }
    private func img(_ u: UIImage) -> UIImage { u }
    private func sectionTitle(_ i: Int) -> String { ["THE STORY", "THE DETAIL", "WHAT IT MEANS", "WHERE IT GOES"][min(3, i / 4)] }
}

// MARK: - Layout archetypes: poster, dossier, split, zine

private func facts(_ e: Edition) -> [String] { e.blocks.filter { $0.type == .keyFacts }.flatMap { $0.items ?? [] } }
private func paras(_ e: Edition) -> [String] { e.blocks.filter { $0.type == .paragraph || $0.type == .takeaway }.compactMap(\.text) }

/// Poster: the number or the headline enormous on a solid accent field.
struct PosterLayout: View {
    let edition: Edition
    let article: Article
    private var theme: Theme { Theme.forEdition(edition) }
    private var field: Color { theme.accent == Identity.acid ? Identity.acid : theme.accent }
    private var ink: Color { field == Identity.acid ? Identity.ink : Identity.warmWhite }
    var body: some View {
        let stat = edition.blocks.first { $0.type == .stat }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(sourceName(article)).font(Identity.grotesk(11, .bold)).tracking(1.6)
                Spacer(minLength: 20)
                if let stat {
                    Text(stat.text ?? "").font(Identity.grotesk(96, .black)).tracking(-5).minimumScaleFactor(0.5).lineLimit(1)
                    Text(stat.caption ?? "").font(Identity.grotesk(22, .semibold)).lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(edition.posterHeadline ?? edition.headline).font(Identity.grotesk(54, .black)).tracking(-2.5).lineSpacing(-8).fixedSize(horizontal: false, vertical: true)
                }
                Text(edition.headline).font(Identity.grotesk(15, .medium)).opacity(0.85).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 470, alignment: .topLeading)
            .background(field)
            .foregroundStyle(ink)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(facts(edition).prefix(3).enumerated()), id: \.offset) { i, f in
                    let (h, t) = splitFact(f)
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(theme.secondary).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            if !h.isEmpty { Text(h).font(Identity.grotesk(10, .bold)).tracking(1.4).foregroundStyle(theme.secondary) }
                            Text(t).font(Identity.grotesk(17, .semibold)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 14)
                    Rectangle().fill(theme.ink.opacity(0.9)).frame(height: 1)
                }
                Text(edition.rationale).font(Identity.grotesk(11)).foregroundStyle(theme.secondary).padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .foregroundStyle(theme.ink)
        }
        .padding(.bottom, 24)
    }
}

/// Dossier: numbered sections with big numerals in the margin and mono labels.
struct DossierLayout: View {
    let edition: Edition
    let article: Article
    private var theme: Theme { Theme.forEdition(edition) }
    var body: some View {
        let items: [(String, String)] = facts(edition).map(splitFact) + paras(edition).map { ("", $0) } + (edition.blocks.first { $0.type == .timeline }?.items ?? []).map { ("TIMELINE", $0) }
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("DOSSIER").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2); Spacer(); Text(sourceName(article)).font(.system(size: 11, weight: .medium, design: .monospaced)) }
                .foregroundStyle(theme.secondary).padding(.horizontal, 20).padding(.top, 12)
            Text(edition.headline).font(theme.typeface == .serif ? Identity.serif(34, .semibold) : Identity.grotesk(32, .heavy)).tracking(-1).lineSpacing(-2).padding(.horizontal, 20).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            if let stat = edition.blocks.first(where: { $0.type == .stat }) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(stat.text ?? "").font(Identity.grotesk(40, .black)).tracking(-1.5)
                    Text(stat.caption ?? "").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
                }.padding(.horizontal, 20).padding(.top, 14)
            }
            Rectangle().fill(theme.ink).frame(height: 2).padding(.horizontal, 20).padding(.top, 16)
            ForEach(Array(items.prefix(7).enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 14) {
                    Text(String(format: "%02d", i + 1)).font(Identity.grotesk(34, .black)).tracking(-1.5).foregroundStyle(theme.accent == Identity.acid ? theme.ink.opacity(0.25) : theme.accent).frame(width: 54, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        if !item.0.isEmpty { Text(item.0).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(theme.secondary) }
                        Text(item.1).font(theme.typeface == .serif ? Identity.serif(17) : Identity.grotesk(16)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                Rectangle().fill(theme.ink.opacity(0.25)).frame(height: 1).padding(.horizontal, 20)
            }
            Text(edition.rationale).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.secondary).padding(20)
        }
        .foregroundStyle(theme.ink)
        .padding(.bottom, 20)
    }
}

/// Split: a solid colour block up top with the headline reversed out, facts as a ruled list below.
struct SplitLayout: View {
    let edition: Edition
    let article: Article
    var hero: UIImage?
    private var theme: Theme { Theme.forEdition(edition) }
    private var block: Color { theme.isDark ? Identity.cobalt : Identity.ink }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(1.6); Spacer(); Text("\(max(1, edition.estimatedReadSeconds / 60)) MIN").font(Identity.grotesk(10, .bold)).tracking(1.2) }.opacity(0.75)
                Text(edition.headline).font(theme.typeface == .serif ? Identity.serif(40, .regular) : Identity.grotesk(38, .heavy)).tracking(-1.2).lineSpacing(-4).fixedSize(horizontal: false, vertical: true)
                if let stat = edition.blocks.first(where: { $0.type == .stat }) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(stat.text ?? "").font(Identity.grotesk(44, .black)).tracking(-2).foregroundStyle(Identity.acid)
                        Text(stat.caption ?? "").font(Identity.grotesk(13)).opacity(0.85)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .bottomLeading)
            .background(block)
            .foregroundStyle(Identity.warmWhite)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(facts(edition).prefix(5).enumerated()), id: \.offset) { _, f in
                    let (h, t) = splitFact(f)
                    VStack(alignment: .leading, spacing: 3) {
                        if !h.isEmpty { Text(h).font(Identity.grotesk(10, .bold)).tracking(1.4).foregroundStyle(theme.secondary) }
                        Text(t).font(Identity.grotesk(16, .medium)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    Rectangle().fill(theme.ink).frame(height: 1)
                }
                if let p = paras(edition).first {
                    Text(p).font(theme.typeface == .serif ? Identity.serif(17) : Identity.grotesk(15)).lineSpacing(5).padding(.top, 16).fixedSize(horizontal: false, vertical: true)
                }
                Text(edition.rationale).font(Identity.grotesk(11)).foregroundStyle(theme.secondary).padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .foregroundStyle(theme.ink)
        }
        .padding(.bottom, 24)
    }
}

/// Zine: dark, uppercase condensed headline in the accent, oversized bullets, an italic pull quote.
struct ZineLayout: View {
    let edition: Edition
    let article: Article
    private var accent: Color { Identity.acid }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(2); Spacer(); Text(edition.stateSummary.uppercased()).font(Identity.grotesk(10, .bold)).tracking(1.5).foregroundStyle(accent) }
            Text(edition.headline.uppercased()).font(Identity.grotesk(44, .black)).tracking(-2).lineSpacing(-9).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
            if let stat = edition.blocks.first(where: { $0.type == .stat }) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(stat.text ?? "").font(Identity.grotesk(64, .black)).tracking(-3)
                    Text(stat.caption ?? "").font(Identity.grotesk(14, .semibold)).foregroundStyle(Identity.warmWhite.opacity(0.7))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(facts(edition).prefix(5).enumerated()), id: \.offset) { _, f in
                    let (_, t) = splitFact(f)
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(accent).frame(width: 12, height: 12).padding(.top, 7)
                        Text(t).font(Identity.grotesk(21, .bold)).lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let q = edition.blocks.first(where: { $0.type == .pullQuote })?.text ?? paras(edition).first {
                Text("“\(q)”").font(Identity.serif(24)).italic().lineSpacing(1).foregroundStyle(Identity.warmWhite.opacity(0.85)).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            }
            Text(edition.rationale).font(Identity.grotesk(11)).foregroundStyle(Identity.warmWhite.opacity(0.5))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Identity.warmWhite)
        .background(Identity.night)
        .padding(.bottom, 20)
    }
}
