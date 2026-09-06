import SwiftUI

/// "Kept": the reader's saved stories. Tap to read, swipe to let go.
struct BookmarksView: View {
    @Environment(Bookmarks.self) private var bookmarks
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.saved.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark").font(.system(size: 28, weight: .semibold))
                        Text("Nothing kept yet.").font(Identity.grotesk(17, .heavy)).tracking(-0.4)
                        Text("Tap the bookmark on any story.").font(Identity.serif(15)).foregroundStyle(Identity.grey)
                    }
                    .foregroundStyle(Identity.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Identity.warmWhite.ignoresSafeArea())
                } else {
                    List {
                        ForEach(bookmarks.saved) { article in
                            NavigationLink(value: article) { BookmarkRow(article: article) }
                                .listRowBackground(Identity.warmWhite)
                                .listRowSeparatorTint(Identity.rule.opacity(0.15))
                        }
                        .onDelete { offsets in
                            for i in offsets { bookmarks.remove(bookmarks.saved[i]) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Identity.warmWhite.ignoresSafeArea())
                }
            }
            .navigationTitle("Kept")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Identity.warmWhite, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Identity.grotesk(15, .bold)).foregroundStyle(Identity.ink)
                }
            }
            .navigationDestination(for: Article.self) { article in ReaderView(article: article) }
        }
        .tint(Identity.ink)
    }
}

struct BookmarkRow: View {
    let article: Article
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(sourceName(article)).font(Identity.grotesk(10, .bold)).tracking(1.2)
                Text("·").foregroundStyle(Identity.grey)
                Text(readTime(article)).font(Identity.grotesk(10, .medium)).tracking(1)
            }
            .foregroundStyle(Identity.grey)
            Text(article.title).font(Identity.grotesk(17, .heavy)).tracking(-0.5).lineSpacing(-1).lineLimit(3)
        }
        .foregroundStyle(Identity.ink)
        .padding(.vertical, 8)
    }
}
