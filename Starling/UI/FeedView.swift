import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @Environment(HeroImageStore.self) private var heroes
    @State private var showSources = false
    @State private var showSettings = false
    @State private var showSignals = false

    private var theme: Theme { hub.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        StatePill(theme: theme) { showSignals = true }
                        Spacer()
                        RoundIconButton(symbol: "square.stack.3d.up", theme: theme) { showSources = true }
                        RoundIconButton(symbol: "gearshape", theme: theme) { showSettings = true }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)

                    Text("Starling")
                        .font(theme.font(34, weight: theme.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 20)

                    if !feeds.failedSourceIDs.isEmpty {
                        Label(feeds.usedSnapshot ? "Couldn't reach \(failedNames). Showing saved stories." : "Couldn't reach \(failedNames).", systemImage: "wifi.exclamationmark")
                            .font(theme.font(12, weight: .semibold)).foregroundStyle(theme.secondary).padding(.horizontal, 20)
                    }

                    if feeds.articles.isEmpty {
                        VStack(spacing: 10) {
                            if feeds.isLoading { ProgressView().tint(theme.ink) } else {
                                Text("No stories yet").font(theme.font(18, weight: .bold))
                                Button("Try again") { Task { await feeds.refresh() } }.font(theme.font(14, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.top, 80).foregroundStyle(theme.ink)
                    } else {
                        if let lead = feeds.articles.first {
                            NavigationLink(value: lead) { LeadCard(article: lead, theme: theme) }.buttonStyle(.plain)
                                .padding(.horizontal, 20)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(Array(feeds.articles.dropFirst().enumerated()), id: \.element.id) { i, article in
                                NavigationLink(value: article) {
                                    Tile(article: article, color: theme.tiles[i % theme.tiles.count], theme: theme)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 30)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .environment(\.colorScheme, theme.palette.scheme)
            .animation(.easeInOut(duration: 0.6), value: theme.paletteName)
            .refreshable { await feeds.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Article.self) { article in ReaderView(article: article) }
            .sheet(isPresented: $showSources) { SourcePicker() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSignals) { SignalSheet() }
            .task { if feeds.articles.isEmpty { await feeds.refresh() } }
            .onChange(of: feeds.enabledIDs, initial: true) { _, ids in
                generator.sourceSignature = ids.sorted().joined(separator: ",")
            }
            .onChange(of: feeds.lastRefresh) { _, _ in prefetch(); feeds.articles.prefix(12).forEach { heroes.load($0.imageURL) } }
            .onChange(of: hub.phase) { _, p in if p == .live { prefetch() } }
        }
    }

    var failedNames: String {
        feeds.failedSourceIDs.compactMap { FeedCatalog.source($0)?.name }.sorted().joined(separator: ", ")
    }

    func prefetch() {
        guard hub.phase == .live || !hub.isSensingEnabled || !hub.cameraSupported else { return }
        generator.prefetch(feeds.articles, state: hub.state, sources: feeds.enabledSources, feeds: feeds)
    }
}

private func readTime(_ a: Article) -> String {
    let w = max(a.wordCount, 120)
    return "\(max(1, w / 220)) min"
}

struct LeadCard: View {
    @Environment(HeroImageStore.self) private var heroes
    @Environment(Generator.self) private var generator
    let article: Article
    let theme: Theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let img = generator.heroImageName(for: article, edition: nil).flatMap(UIImage.init(named:)) ?? heroes.image(for: article.imageURL) {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text("\(FeedCatalog.source(article.sourceID)?.name ?? "") · \(readTime(article))".uppercased())
                .font(theme.font(11, weight: .bold)).tracking(0.6).foregroundStyle(theme.secondary)
            Text(article.title).font(theme.font(20, weight: theme.heavy)).lineSpacing(1).foregroundStyle(theme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .task { heroes.load(article.imageURL) }
    }
}

struct Tile: View {
    @Environment(HeroImageStore.self) private var heroes
    let article: Article
    let color: Color
    let theme: Theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = heroes.image(for: article.imageURL) {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text((FeedCatalog.source(article.sourceID)?.name ?? "").uppercased())
                .font(theme.font(10, weight: .bold)).tracking(0.6).foregroundStyle(theme.secondary)
            Text(article.title).font(theme.font(15, weight: theme.heavy)).lineLimit(5).foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            Text(readTime(article)).font(theme.font(11, weight: .bold)).foregroundStyle(theme.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(color, in: RoundedRectangle(cornerRadius: 18))
        .task { heroes.load(article.imageURL) }
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
