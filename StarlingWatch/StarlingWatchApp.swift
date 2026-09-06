import SwiftUI

@main
struct StarlingWatchApp: App {
    @State private var streamer = PulseStreamer()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(streamer)
        }
    }
}

struct ContentView: View {
    @Environment(PulseStreamer.self) private var streamer
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .font(.title2)
                .symbolEffect(.pulse, isActive: streamer.isRunning)
            Text(streamer.bpm.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            Text(streamer.status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(streamer.isRunning ? "Stop" : "Start streaming") {
                if streamer.isRunning { streamer.stop() } else { streamer.start() }
            }
            .tint(streamer.isRunning ? .gray : .red)
        }
        .padding()
        .task { streamer.activate() }
    }
}
