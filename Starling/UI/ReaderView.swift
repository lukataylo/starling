import SwiftUI

struct ReaderView: View {
    @Environment(FeedStore.self) private var feeds
    @Environment(Generator.self) private var generator
    @Environment(SignalHub.self) private var hub
    @State var article: Article
    @State private var bodyLoaded = false
    @State private var mode: Mode = .adapted
    @State private var showWhy = false
    @State private var showCompare = false
    @State private var showStatePicker = false
    /// The state the page on screen was generated for. The page never swaps on its own.
    @State private var shownState: UserState?
    @State private var pendingState: UserState?
    @State private var pendingSince: Date?
    @State private var formatOverride: EditionFormat?
    @State private var trayExpanded = true
    private let stableAfter: TimeInterval = 5

    enum Mode { case adapted, longform, original }

    private var liveState: UserState { hub.state }
    private var pageState: UserState { shownState ?? liveState }
    private var adapted: Edition? { generator.edition(for: article, intent: .adapt, state: pageState) }
    private var longform: Edition? { generator.edition(for: article, intent: .longform, state: pageState) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                content
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { tray }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StateChip(compact: true) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCompare = true } label: { Label("Compare generations", systemImage: "rectangle.split.2x1") }
                    Button { mode = .original } label: { Label("Original article", systemImage: "doc.plaintext") }
                    Button { Task { await regenerate() } } label: { Label("Regenerate for now", systemImage: "arrow.clockwise") }
                    Link(destination: article.link) { Label("Open in Safari", systemImage: "safari") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showWhy) { WhyThisSheet(article: article, edition: currentEdition) }
        .sheet(isPresented: $showCompare) { CompareView(article: article) }
        .confirmationDialog("How do you feel right now?", isPresented: $showStatePicker, titleVisibility: .visible) {
            ForEach(ReaderLabel.allCases, id: \.self) { l in
                Button(l.rawValue.capitalized) { correctState(to: l) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            article = await feeds.loadBody(for: article)
            bodyLoaded = true
            shownState = liveState
            await generator.generate(article: article, intent: .adapt, state: liveState, sources: feeds.enabledSources)
        }
        .onChange(of: liveState.bucket) { _, _ in
            // Live state moved. Don't swap the page: wait until it is stable, prefetch, then propose.
            guard bodyLoaded, mode == .adapted, let shown = shownState else { return }
            if liveState.bucket == shown.bucket { pendingState = nil; pendingSince = nil; return }
            pendingState = liveState
            pendingSince = .now
            let candidate = liveState
            Task {
                try? await Task.sleep(for: .seconds(stableAfter))
                guard pendingState?.bucket == candidate.bucket else { return }
                await generator.generate(article: article, intent: .adapt, state: candidate, sources: feeds.enabledSources)
            }
        }
    }

    private var currentEdition: Edition? {
        switch mode {
        case .adapted: return adapted
        case .longform: return longform
        case .original: return nil
        }
    }

    private var pageBackground: Color {
        if let e = currentEdition { return DesignGenome.palette(e.palette).background }
        return Color(.systemBackground)
    }

    private var effectiveFormat: EditionFormat { formatOverride ?? currentEdition?.format ?? .text }

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            Text("Adapted").tag(Mode.adapted)
            Text("Full").tag(Mode.longform)
            Text("Original").tag(Mode.original)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16).padding(.top, 6)
        .onChange(of: mode) { _, m in
            if m == .longform, longform == nil { Task { await readFull() } }
        }
    }

    @ViewBuilder private var tray: some View {
        VStack(spacing: 8) {
            if mode == .adapted, let p = pendingState, p.bucket != pageState.bucket {
                StateChangeProposal(from: pageState, to: p,
                                    ready: generator.edition(for: article, intent: .adapt, state: p) != nil,
                                    onSwitch: { switchTo(p) },
                                    onDismiss: { pendingState = nil; pendingSince = nil })
            }
            header
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
        .background(.clear)
    }

    @ViewBuilder private var header: some View {
        if mode == .adapted, let e = adapted {
            ProposalBanner(edition: e,
                           expanded: $trayExpanded,
                           format: Binding(get: { effectiveFormat }, set: { formatOverride = $0 }),
                           onReadFull: { Task { await readFull() } },
                           onKeep: {
                               pendingState = nil
                               generator.addFeedback("At \(pageState.timeOfDay.label) while \(pageState.motion.rawValue) I kept: \(e.density.rawValue), \(e.palette.rawValue), \(e.typeface.rawValue), \(effectiveFormat.rawValue)")
                           },
                           onNotMe: { showStatePicker = true },
                           onWhy: { showWhy = true })
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .adapted:
            if let e = adapted {
                if effectiveFormat == .cards {
                    CardsRenderer(edition: e, onReadFull: { Task { await readFull() } }).id(e.id)
                } else {
                    EditionRenderer(edition: e, onReadFull: { Task { await readFull() } }).id(e.id)
                }
            } else {
                generatingOrError(intent: .adapt)
            }
        case .longform:
            if let e = longform {
                EditionRenderer(edition: e)
            } else {
                generatingOrError(intent: .longform)
            }
        case .original:
            originalView
        }
    }

    @ViewBuilder private func generatingOrError(intent: GenerationIntent) -> some View {
        let status = generator.status(for: article, intent: intent, state: pageState)
        VStack(alignment: .leading, spacing: 12) {
            if case .failed(let why) = status {
                Label("Couldn't adapt this story", systemImage: "exclamationmark.triangle").font(.headline)
                Text(why).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Try again") { Task { await regenerate() } }
                    Button("Show original") { mode = .original }
                }.buttonStyle(.bordered)
                Divider()
                originalView
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(bodyLoaded ? "Writing this for \(pageState.timeOfDay.label), \(pageState.label.rawValue)…" : "Fetching the story…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                Text(article.title).font(.title2.bold())
                Text(article.summary).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var originalView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = FeedCatalog.source(article.sourceID) {
                Label(s.name, systemImage: s.symbol).font(.caption).foregroundStyle(.secondary)
            }
            Text(article.title).font(.title.bold())
            ForEach(Array((article.body ?? [article.summary]).enumerated()), id: \.offset) { _, p in
                Text(p)
            }
        }
        .padding()
    }

    private func switchTo(_ s: UserState) {
        withAnimation(.easeInOut(duration: 0.35)) {
            shownState = s
            pendingState = nil
            pendingSince = nil
            formatOverride = nil
        }
        Task { await generator.generate(article: article, intent: .adapt, state: s, sources: feeds.enabledSources) }
    }

    private func readFull() async {
        mode = .longform
        await generator.generate(article: article, intent: .longform, state: pageState, sources: feeds.enabledSources)
    }

    private func regenerate() async {
        let intent: GenerationIntent = mode == .longform ? .longform : .adapt
        if mode == .original { mode = .adapted }
        shownState = liveState
        pendingState = nil
        await generator.generate(article: article, intent: intent, state: liveState, sources: feeds.enabledSources, force: true)
    }

    private func correctState(to label: ReaderLabel) {
        hub.labelOverride = label
        generator.addFeedback("When the app guessed '\(pageState.label.rawValue)' at \(pageState.timeOfDay.label) I actually felt '\(label.rawValue)'.")
        Task {
            let s = hub.state
            shownState = s
            pendingState = nil
            await generator.generate(article: article, intent: .adapt, state: s, sources: feeds.enabledSources, force: true)
        }
    }
}

/// "Your state changed" — a proposal, never an automatic swap.
struct StateChangeProposal: View {
    let from: UserState
    let to: UserState
    let ready: Bool
    let onSwitch: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: to.label.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text("Now \(describe(to))").font(.caption.weight(.semibold))
                Text(ready ? "A version for this moment is ready." : "Preparing a version for this moment…").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Switch", action: onSwitch).disabled(!ready)
            Button { onDismiss() } label: { Image(systemName: "xmark") }
        }
        .font(.caption)
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.mini)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func describe(_ s: UserState) -> String {
        var parts: [String] = []
        if s.motion != from.motion { parts.append(s.motion == .stationary ? "still" : s.motion.rawValue) }
        if s.posture != from.posture && s.motion == .stationary { parts.append(s.posture.rawValue) }
        if s.label != from.label { parts.append(s.label.rawValue) }
        if s.timeOfDay != from.timeOfDay { parts.append(s.timeOfDay.label) }
        return parts.isEmpty ? "a different moment" : parts.joined(separator: ", ")
    }
}
