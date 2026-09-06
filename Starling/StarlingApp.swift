import SwiftUI

@main
struct StarlingApp: App {
    @State private var feeds = FeedStore()
    @State private var generator = Generator()
    @State private var hub = SignalHub()
    @State private var heroes = HeroImageStore()
    @State private var imageGen = ImageGenerator()
    @State private var rules = StateRules()
    @State private var overnight = OvernightPregen()
    @State private var newsreader = Newsreader()
    @State private var bookmarks = Bookmarks()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environment(feeds)
                .environment(generator)
                .environment(hub)
                .environment(heroes)
                .environment(imageGen)
                .environment(rules)
                .environment(overnight)
                .environment(newsreader)
                .environment(bookmarks)
                .animation(.easeInOut(duration: 0.6), value: hub.theme.paletteName)
                .animation(.easeInOut(duration: 0.6), value: hub.theme.resolvedPaletteName)
                .animation(.easeInOut(duration: 0.6), value: appearance)
                .onChange(of: systemScheme, initial: true) { _, s in hub.systemIsDark = s == .dark }
                .task {
                    generator.rulesTextProvider = { [rules] s in rules.promptText(for: s) }
                    generator.rulesSignature = rules.signature
                    overnight.register(feeds: feeds, generator: generator, images: imageGen, hub: hub)
                    hub.start()
                }
                .onChange(of: scenePhase) { _, p in
                    hub.setAppActive(p == .active)
                    if p == .background { hub.pauseCamera() } else if p == .active { hub.resumeCamera() }
                }
        }
    }
}
