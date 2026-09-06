import SwiftUI

/// The readout behind the state pill: night palette, mono labels, HR / EYES / MOTION, and the view chips.
struct SignalSheet: View {
    @Environment(SignalHub.self) private var hub
    @Environment(Generator.self) private var generator
    @Environment(\.dismiss) private var dismiss
    var mode: Binding<ReaderMode>? = nil
    @State private var showCorrect = false

    private let bg = Color(red: 0.06, green: 0.07, blue: 0.08)
    private let card = Color(red: 0.10, green: 0.11, blue: 0.13)
    private let ink = Color(red: 0.91, green: 0.89, blue: 0.85)
    private let sec = Color(red: 0.55, green: 0.54, blue: 0.51)
    private let coral = Color(red: 0.95, green: 0.55, blue: 0.49)

    var body: some View {
        let s = hub.state
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("STARLING").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(ink)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(coral).frame(width: 8, height: 8)
                    Text(s.label.rawValue.uppercased()).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(coral)
                }
            }
            HStack(spacing: 10) {
                tile("HR · \(s.pulseSource == .watch ? "WATCH" : (s.pulseSource == .camera ? "CAMERA" : "—"))") {
                    HStack {
                        Text(s.bpm.map { s.bpmConfidence >= 0.4 ? "\(Int($0))" : "—" } ?? "—").font(.system(size: 30, weight: .bold, design: .rounded))
                        Spacer()
                        bars(s)
                    }
                }
                tile("EYES") {
                    HStack {
                        Text(!s.sensingEnabled || !hub.cameraSupported ? "—" : (s.faceDetected ? (s.attention >= 0.5 ? "ON" : "OFF") : "—")).font(.system(size: 30, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: s.faceDetected && s.attention >= 0.5 ? "eye" : "eye.slash").foregroundStyle(ink)
                    }
                }
                tile("MOTION") {
                    HStack {
                        Text(motionText(s)).font(.system(size: 15, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        Spacer()
                        Image(systemName: s.motion == .walking || s.motion == .running ? "figure.walk" : (s.motion == .automotive ? "tram" : "figure.seated.side")).foregroundStyle(ink)
                    }
                }
            }
            if let mode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("NOW", .adapted, mode); chip("CALM", .preset(.calm), mode); chip("FOCUSED", .preset(.focused), mode); chip("FULL", .longform, mode); chip("ORIGINAL", .original, mode)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                row("STRESS", String(format: "%.2f", s.stress))
                row("BLINKS", "\(Int(s.blinkRate)) / MIN")
                row("BASELINE", hub.baselineIsDefault ? "DEFAULT 70" : "\(Int(hub.baselineBPM)) BPM")
                row("CONFIDENCE", "\(Int(s.labelConfidence * 100))%")
            }
            HStack(spacing: 10) {
                Button { showCorrect = true } label: { Text("NOT HOW I FEEL").font(.system(size: 12, weight: .medium, design: .monospaced)).padding(.horizontal, 14).padding(.vertical, 10).background(card, in: RoundedRectangle(cornerRadius: 8)) }
                Button { hub.recalibrate() } label: { Text("RECALIBRATE").font(.system(size: 12, weight: .medium, design: .monospaced)).padding(.horizontal, 14).padding(.vertical, 10).background(card, in: RoundedRectangle(cornerRadius: 8)) }
                Spacer()
                Toggle("", isOn: Binding(get: { hub.isSensingEnabled }, set: { hub.isSensingEnabled = $0 })).labelsHidden().tint(coral)
            }
            .foregroundStyle(ink)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bg)
        .foregroundStyle(ink)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("How do you feel right now?", isPresented: $showCorrect, titleVisibility: .visible) {
            ForEach(ReaderLabel.allCases, id: \.self) { l in
                Button(l.rawValue.capitalized) {
                    hub.labelOverride = l
                    generator.addFeedback("When the app guessed '\(s.label.rawValue)' at \(s.timeOfDay.label) I actually felt '\(l.rawValue)'.")
                }
            }
            Button("Let the sensors decide") { hub.labelOverride = nil }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func tile<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(sec)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func bars(_ s: UserState) -> some View {
        let base = Int(max(1, min(12, ((s.bpm ?? 70) - 50) / 6)))
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(coral).frame(width: 3, height: CGFloat(4 + (base + i * 3) % 12))
            }
        }
        .frame(height: 14)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(sec); Spacer(); Text(v) }.font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private func chip(_ title: String, _ m: ReaderMode, _ binding: Binding<ReaderMode>) -> some View {
        let on = binding.wrappedValue == m
        return Button { binding.wrappedValue = m; dismiss() } label: {
            Text(title).font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(on ? card : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)))
                .foregroundStyle(on ? ink : sec)
        }
        .buttonStyle(.plain)
    }

    private func motionText(_ s: UserState) -> String {
        switch s.motion {
        case .walking: return "WALKING"
        case .running: return "RUNNING"
        case .automotive: return "TRANSIT"
        default:
            switch s.posture {
            case .lyingDown: return "LYING"
            case .reclined: return "RECLINED"
            case .flat: return "TABLE"
            default: return "STILL"
            }
        }
    }
}
