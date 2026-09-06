import SwiftUI

/// "Measure pulse with the camera": cover the rear camera and flash with a fingertip for 15 seconds.
struct FingerPulseView: View {
    @Environment(SignalHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    let theme: Theme
    @State private var measurer = FingerPulseMeasurer()

    var body: some View {
        VStack(spacing: 22) {
            Text("MEASURE PULSE · CAMERA").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1)
            Text(instruction).font(Identity.grotesk(17, .semibold)).multilineTextAlignment(.center).padding(.horizontal, 24).fixedSize(horizontal: false, vertical: true)
            waveform.frame(height: 90).padding(.horizontal, 24)
            switch measurer.phase {
            case .measuring(let p):
                ProgressView(value: p).tint(Identity.acid).padding(.horizontal, 40)
                Text("\(Int((1 - p) * 15))s").font(Identity.grotesk(13)).foregroundStyle(theme.secondary)
            case .done(let bpm, let conf):
                Text("\(Int(bpm))").font(Identity.grotesk(72, .black)).tracking(-3)
                Text("BPM · CONFIDENCE \(Int(conf * 100))%").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
                HStack(spacing: 10) {
                    Button("Use this") { hub.ingestFingerPulse(bpm: bpm, confidence: conf); dismiss() }.buttonStyle(.borderedProminent).tint(Identity.acid).foregroundStyle(Identity.ink)
                    Button("Again") { measurer.start() }.buttonStyle(.bordered)
                }
            case .failed(let why):
                Text(why).foregroundStyle(.red)
                Button("Try again") { measurer.start() }.buttonStyle(.bordered)
            default:
                EmptyView()
            }
            Spacer()
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.background)
        .foregroundStyle(theme.ink)
        .environment(\.colorScheme, theme.palette.scheme)
        .onAppear { hub.pauseCamera(); measurer.start() }
        .onDisappear { measurer.stop(); hub.resumeCamera() }
    }

    private var instruction: String {
        switch measurer.phase {
        case .idle, .waitingForFinger: return "Cover the rear camera and the flash completely with your fingertip. Hold still."
        case .measuring: return "Keep your finger still. Reading…"
        case .done: return "Done."
        case .failed: return "Couldn't get a clean reading."
        }
    }

    private var waveform: some View {
        GeometryReader { geo in
            let pts = measurer.waveform
            Path { p in
                guard pts.count > 1 else { return }
                let w = geo.size.width, h = geo.size.height
                for (i, v) in pts.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(pts.count - 1)
                    let y = h / 2 - CGFloat(max(-2.5, min(2.5, v))) * h / 6
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Identity.acid, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}
