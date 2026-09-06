import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @State private var showSources = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if feeds.articles.isEmpty && feeds.isLoading {
                    ProgressView("Fetching your sources…")
                } else if feeds.articles.isEmpty {
                    ContentUnavailableView("No stories yet", systemImage: "newspaper", description: Text("Pick some sources to get started."))
                } else {
                    List(feeds.articles) { article in
                        NavigationLink(value: article) {
                            ArticleRow(article: article)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await feeds.refresh() }
                }
            }
            .navigationTitle("Starling")
            .safeAreaInset(edge: .bottom) {
                StateChip().padding(.bottom, 6)
            }
            .navigationDestination(for: Article.self) { article in
                ReaderView(article: article)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSources = true } label: { Label("Sources", systemImage: "square.stack.3d.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .sheet(isPresented: $showSources) { SourcePicker() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task { if feeds.articles.isEmpty { await feeds.refresh() } }
            .onChange(of: feeds.enabledIDs, initial: true) { _, ids in
                generator.sourceSignature = ids.sorted().joined(separator: ",")
            }
            .onChange(of: feeds.lastRefresh) { _, _ in prefetch() }
            .onChange(of: hub.phase) { _, p in if p == .live { prefetch() } }
        }
    }
}

extension FeedView {
    /// Prefetch once the state is stable (calibrated or sensing off).
    func prefetch() {
        guard hub.phase == .live || !hub.isSensingEnabled || !hub.cameraSupported else { return }
        generator.prefetch(feeds.articles, state: hub.state, sources: feeds.enabledSources, feeds: feeds)
    }
}

struct ArticleRow: View {
    let article: Article
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let s = FeedCatalog.source(article.sourceID) {
                    Image(systemName: s.symbol).font(.caption2)
                    Text(s.name).font(.caption).foregroundStyle(.secondary)
                }
                if let d = article.published {
                    Text("· \(d, style: .relative)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Text(article.title).font(.headline).lineLimit(3)
            if !article.summary.isEmpty {
                Text(article.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourcePicker: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(FeedCatalog.all) { source in
                Button {
                    feeds.toggle(source)
                } label: {
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
