import SwiftUI

/// "Call the newsreader": live transcript, speaking indicator, a proposal card when the agent asks to change the version.
struct CallSheet: View {
    @Environment(Newsreader.self) private var reader
    @Environment(\.dismiss) private var dismiss
    let article: Article
    let theme: Theme
    let onApply: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("NEWSREADER").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(statusText).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
                }
            }
            Text(article.title).font(Identity.grotesk(20, .heavy)).tracking(-0.6).lineSpacing(-2).fixedSize(horizontal: false, vertical: true)
            if let p = reader.proposal {
                VStack(alignment: .leading, spacing: 8) {
                    Text("THE NEWSREADER SUGGESTS").font(Identity.grotesk(10, .bold)).tracking(1.4).foregroundStyle(theme.secondary)
                    Text("Switch to the \(p.kind) version?").font(Identity.grotesk(15, .bold))
                    Text(p.reason).font(Identity.grotesk(13)).foregroundStyle(theme.secondary)
                    HStack { Button("Yes, switch") { onApply(p.kind) }.buttonStyle(.borderedProminent).tint(Identity.acid).foregroundStyle(Identity.ink); Text("or just say yes").font(Identity.grotesk(11)).foregroundStyle(theme.secondary) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(reader.transcript.enumerated()), id: \.offset) { i, line in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(line.role.uppercased()).font(Identity.grotesk(9, .bold)).tracking(1.4).foregroundStyle(line.role == "you" ? theme.accent : theme.secondary)
                                Text(line.text).font(line.role == "you" ? Identity.grotesk(15, .medium) : Identity.serif(16)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            }
                            .id(i)
                        }
                        if reader.transcript.isEmpty { Text(emptyText).font(Identity.serif(16)).foregroundStyle(theme.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: reader.transcript.count) { _, n in withAnimation { proxy.scrollTo(max(0, n - 1), anchor: .bottom) } }
            }
            HStack(spacing: 10) {
                Button { Task { await reader.toggleMute() } } label: { Label(reader.isMuted ? "Unmute" : "Mute", systemImage: reader.isMuted ? "mic.slash" : "mic") }
                Button { Task { await reader.interrupt() } } label: { Label("Interrupt", systemImage: "hand.raised") }
                Spacer()
                Button { Task { await reader.endCall() }; dismiss() } label: { Label("End", systemImage: "phone.down.fill") }.buttonStyle(.borderedProminent).tint(Identity.red)
            }
            .buttonStyle(.bordered).font(Identity.grotesk(12, .semibold))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.background)
        .foregroundStyle(theme.ink)
        .environment(\.colorScheme, theme.palette.scheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(reader.callState == .live)
    }

    private var dotColor: Color {
        switch reader.callState {
        case .live: return reader.agentSpeaking ? Identity.acid : Color.green
        case .connecting, .authoring: return .orange
        case .failed: return Identity.red
        default: return theme.secondary
        }
    }
    private var statusText: String {
        switch reader.callState {
        case .idle: return "IDLE"
        case .authoring: return "WRITING THE STORY"
        case .connecting: return "CALLING"
        case .live: return reader.agentSpeaking ? "SPEAKING" : "LISTENING"
        case .ended: return "ENDED"
        case .failed(let why): return "FAILED · " + why.uppercased().prefix(40)
        }
    }
    private var emptyText: String {
        switch reader.callState {
        case .authoring: return "Writing this story for the newsreader…"
        case .connecting: return "Connecting…"
        case .live: return "The newsreader is about to start. Interrupt any time."
        case .failed(let why): return why
        default: return ""
        }
    }
}
