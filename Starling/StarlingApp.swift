import SwiftUI

@main
struct StarlingApp: App {
    @State private var feeds = FeedStore()
    @State private var generator = Generator()
    @State private var hub = SignalHub()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environment(feeds)
                .environment(generator)
                .environment(hub)
                .task { hub.start() }
                .onChange(of: scenePhase) { _, p in
                    if p == .background { hub.pauseCamera() } else if p == .active { hub.resumeCamera() }
                }
        }
    }
}
