import SwiftUI

@main
struct StarlingApp: App {
    @State private var feeds = FeedStore()
    @State private var generator = Generator()
    @State private var hub = SignalHub()
    @State private var heroes = HeroImageStore()
    @State private var imageGen = ImageGenerator()
    @State private var rules = StateRules()
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
                .task {
                    generator.rulesTextProvider = { [rules] s in rules.promptText(for: s) }
                    generator.rulesSignature = rules.signature
                    hub.start()
                }
                .onChange(of: scenePhase) { _, p in
                    if p == .background { hub.pauseCamera() } else if p == .active { hub.resumeCamera() }
                }
        }
    }
}
