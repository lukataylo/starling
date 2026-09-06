import SwiftUI
import AVFoundation
import LiveKit

/// The call: full acid-green screen, timer, Starling wordmark, the story, the bird, what's being said, a waveform, and Speaker / End / Mute.
struct CallSheet: View {
    @Environment(Newsreader.self) private var reader
    @Environment(\.dismiss) private var dismiss
    let article: Article
    let theme: Theme
    let onApply: (String) -> Void
    @State private var started = Date()
    @State private var now = Date()
    @State private var speaker = true
    @State private var wave: [CGFloat] = Array(repeating: 0.2, count: 28)
    private let tick = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    /// Only the tail of what's being said: the last sentence or two, never the whole narrative.
    private var latestAgentLine: String {
        let full = reader.transcript.last { $0.role == "newsreader" }?.text ?? ""
        let sentences = full.split(whereSeparator: { ".!?".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !sentences.isEmpty else { return full }
        var out = sentences.suffix(1).joined(separator: ". ")
        if out.count < 60, sentences.count > 1 { out = sentences.suffix(2).joined(separator: ". ") }
        if out.count > 150 { out = String(out.suffix(150)); if let sp = out.firstIndex(of: " ") { out = "…" + out[out.index(after: sp)...] } }
        return out.hasSuffix(".") ? out : out + "."
    }
    @State private var nearEar = false
    private var elapsed: String {
        let s = Int(now.timeIntervalSince(started)); return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.72, green: 0.98, blue: 0.10), Identity.acid, Color(red: 0.82, green: 1.0, blue: 0.30)], center: .init(x: 0.6, y: 0.45), startRadius: 40, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Text(elapsed).font(Identity.grotesk(17, .medium)).padding(.top, 14)
                Text("Starling").font(Identity.grotesk(58, .semibold)).tracking(-2.8).padding(.top, 4)
                Text(article.title).font(Identity.grotesk(17, .medium)).multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 32).padding(.top, 2)
                Text(subtitle).font(Identity.grotesk(17, .medium)).opacity(0.85).padding(.top, 2)
                Spacer(minLength: 10)
                Image("Bird").resizable().aspectRatio(contentMode: .fit).frame(width: 250)
                    .scaleEffect(reader.agentSpeaking ? 1.03 : 1).animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: reader.agentSpeaking)
                Spacer(minLength: 10)
                Text(statusLabel).font(Identity.grotesk(11, .medium)).tracking(3).opacity(0.7)
                Group {
                    if let p = reader.proposal {
                        VStack(spacing: 8) {
                            Text("Switch to the \(p.kind) version?").font(Identity.grotesk(26, .semibold)).tracking(-0.8).multilineTextAlignment(.center)
                            Button("Yes, switch") { onApply(p.kind) }.font(Identity.grotesk(14, .bold)).padding(.horizontal, 16).padding(.vertical, 9).background(Identity.ink, in: Capsule()).foregroundStyle(Identity.acid)
                        }
                    } else {
                        Text(latestAgentLine.isEmpty ? placeholder : latestAgentLine)
                            .font(Identity.grotesk(26, .semibold)).tracking(-0.8).lineSpacing(-1)
                            .multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.75)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: latestAgentLine)
                    }
                }
                .frame(minHeight: 130)
                .padding(.horizontal, 28).padding(.top, 10)
                Text(reader.agentSpeaking ? "Interrupt with a question" : "Ask anything about the story").font(Identity.grotesk(15)).opacity(0.7).padding(.top, 6)
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(wave.enumerated()), id: \.offset) { _, h in
                        Capsule().fill(Identity.ink).frame(width: 3, height: 4 + 44 * h)
                    }
                }
                .frame(height: 52).padding(.top, 18)
                Spacer(minLength: 10)
                HStack(spacing: 0) {
                    callButton("Speaker", speaker ? "speaker.wave.2.fill" : "speaker.fill", fill: Identity.ink.opacity(speaker ? 0.62 : 0.3)) { toggleSpeaker() }
                    Spacer()
                    callButton("End", "phone.down.fill", fill: Identity.red, size: 84) { Task { await reader.endCall() }; dismiss() }
                    Spacer()
                    callButton("Mute", reader.isMuted ? "mic.slash.fill" : "mic.fill", fill: Identity.ink.opacity(reader.isMuted ? 0.3 : 0.62)) { Task { await reader.toggleMute() } }
                }
                .padding(.horizontal, 44).padding(.bottom, 26)
            }
            .foregroundStyle(Identity.ink)
        }
        .environment(\.colorScheme, .light)
        .onReceive(tick) { t in
            now = t
            let live = reader.callState == .live
            let energy: CGFloat = live ? (reader.agentSpeaking ? 1 : (reader.isMuted ? 0.05 : 0.25)) : 0.08
            wave = wave.indices.map { i in
                let centre = 1 - abs(CGFloat(i) - 13.5) / 14
                return max(0.05, min(1, CGFloat.random(in: 0...1) * energy * centre + 0.05))
            }
        }
        .onAppear {
            started = .now
            AudioManager.shared.isSpeakerOutputPreferred = true
            // Like the Phone app: the proximity sensor darkens the screen and routes audio to the earpiece against your head.
            UIDevice.current.isProximityMonitoringEnabled = true
        }
        .onDisappear { UIDevice.current.isProximityMonitoringEnabled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)) { _ in
            nearEar = UIDevice.current.proximityState
            AudioManager.shared.isSpeakerOutputPreferred = nearEar ? false : speaker
        }
        .onChange(of: reader.callState) { _, s in if s == .ended { dismiss() } }
    }

    private var subtitle: String {
        switch reader.callState {
        case .authoring: return "Writing the story"
        case .connecting: return "Calling"
        case .live: return "Talking to the article"
        case .ended: return "Call ended"
        case .failed: return "Couldn't connect"
        default: return ""
        }
    }
    private var statusLabel: String {
        switch reader.callState {
        case .live: return reader.agentSpeaking ? "STARLING IS SPEAKING" : "STARLING IS LISTENING"
        case .connecting, .authoring: return "CONNECTING"
        case .failed(let why): return why.uppercased().prefix(48).description
        default: return ""
        }
    }
    private var placeholder: String {
        switch reader.callState {
        case .authoring: return "Reading the story so it can tell it well."
        case .connecting: return "One moment."
        case .live: return "Starling is about to begin."
        case .failed(let why): return why
        default: return ""
        }
    }

    private func toggleSpeaker() {
        speaker.toggle()
        AudioManager.shared.isSpeakerOutputPreferred = speaker
    }

    private func callButton(_ title: String, _ symbol: String, fill: Color, size: CGFloat = 72, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: size, height: size).background(fill, in: Circle())
            }
            .buttonStyle(.plain)
            Text(title).font(Identity.grotesk(14, .medium))
        }
    }
}
