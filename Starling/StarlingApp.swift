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
    @Environment(\.scenePhase) private var scenePhase

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
                .task {
                    generator.rulesTextProvider = { [rules] s in rules.promptText(for: s) }
                    generator.rulesSignature = rules.signature
                    overnight.register(feeds: feeds, generator: generator, images: imageGen, hub: hub)
                    hub.start()
                }
                .onChange(of: scenePhase) { _, p in
                    if p == .background { hub.pauseCamera() } else if p == .active { hub.resumeCamera() }
                }
        }
    }
}
