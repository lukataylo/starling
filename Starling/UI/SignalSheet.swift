import SwiftUI

/// Behind the state pill: the readout (HR / EYES / MOTION), the view chips, and — in the reader — the adaptation controls.
/// Styled by the current theme so it matches the page it opens from.
struct SignalSheet: View {
    @Environment(SignalHub.self) private var hub
    @Environment(Generator.self) private var generator
    @Environment(\.dismiss) private var dismiss
    let theme: Theme
    var mode: Binding<ReaderMode>? = nil
    var edition: Edition? = nil
    var format: Binding<EditionFormat>? = nil
    var pending: UserState? = nil
    var pendingReady = false
    var onSwitch: (() -> Void)? = nil
    var onDismissPending: (() -> Void)? = nil
    var onKeep: (() -> Void)? = nil
    var onWhy: (() -> Void)? = nil
    @State private var showCorrect = false

    private var mono: Font { .system(size: 11, weight: .medium, design: .monospaced) }
    private var card: Color { theme.surface }

    var body: some View {
        let s = hub.state
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("STARLING").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    HStack(spacing: 8) {
                        Circle().fill(theme.accent).frame(width: 8, height: 8)
                        Text(s.label.rawValue.uppercased()).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(theme.accent)
                    }
                }
                HStack(spacing: 10) {
                    tile("HR · \(s.pulseSource == .watch ? "WATCH" : (s.pulseSource == .camera ? "CAMERA" : "—"))") {
                        HStack {
                            Text(s.bpm.map { s.bpmConfidence >= 0.4 ? "\(Int($0))" : "—" } ?? "—").font(.system(size: 28, weight: .bold, design: .rounded))
                            Spacer()
                            bars(s)
                        }
                    }
                    tile("EYES") {
                        HStack {
                            Text(!s.sensingEnabled || !hub.cameraSupported ? "—" : (s.faceDetected ? (s.attention >= 0.5 ? "ON" : "OFF") : "—")).font(.system(size: 28, weight: .bold, design: .rounded))
                            Spacer()
                            Image(systemName: s.faceDetected && s.attention >= 0.5 ? "eye" : "eye.slash")
                        }
                    }
                    tile("MOTION") {
                        HStack {
                            Text(motionText(s)).font(.system(size: 14, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                            Spacer()
                            Image(systemName: s.motion == .walking || s.motion == .running ? "figure.walk" : (s.motion == .automotive ? "tram" : "figure.seated.side"))
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
                if let e = edition {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").foregroundStyle(theme.accent)
                            Text(e.stateSummary.prefix(1).uppercased() + e.stateSummary.dropFirst()).font(theme.font(15, weight: .bold))
                            Spacer()
                            Text("~\(max(5, e.estimatedReadSeconds))s").font(mono).foregroundStyle(theme.secondary)
                        }
                        Text(e.rationale).font(theme.font(14)).foregroundStyle(theme.secondary)
                        Text("\(e.density.rawValue) · \(e.tone.rawValue) · \(e.typeface.rawValue) \(e.typeScale.rawValue) · \(e.palette.rawValue)".uppercased()).font(mono).foregroundStyle(theme.secondary)
                        if let p = pending {
                            HStack(spacing: 10) {
                                Image(systemName: p.label.symbol)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("You seem \(p.label.rawValue) now\(p.motion == .walking ? ", walking" : "")").font(theme.font(14, weight: .bold))
                                    Text(pendingReady ? "A version for this moment is ready." : "Preparing a version for this moment…").font(theme.font(12)).foregroundStyle(theme.secondary)
                                }
                                Spacer()
                                Button("Switch") { onSwitch?(); dismiss() }.disabled(!pendingReady).buttonStyle(.borderedProminent).tint(theme.accent)
                                Button { onDismissPending?() } label: { Image(systemName: "xmark") }.buttonStyle(.bordered)
                            }
                            .padding(12).background(theme.palette.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let format {
                            Picker("Format", selection: format) {
                                Text("Cards").tag(EditionFormat.cards)
                                Text("Text").tag(EditionFormat.text)
                            }.pickerStyle(.segmented)
                        }
                        HStack(spacing: 10) {
                            Button { onKeep?(); dismiss() } label: { Label("Keep this", systemImage: "checkmark") }
                            Button { showCorrect = true } label: { Label("Not how I feel", systemImage: "hand.raised") }
                            Button { dismiss(); onWhy?() } label: { Label("Why", systemImage: "info.circle") }
                        }
                        .buttonStyle(.bordered).tint(theme.accent).font(theme.font(13, weight: .bold))
                    }
                    .padding(14)
                    .background(card, in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 8) {
                    row("STRESS", String(format: "%.2f", s.stress))
                    row("BLINKS", "\(Int(s.blinkRate)) / MIN")
                    row("ATTENTION", "\(Int(s.attention * 100))%")
                    row("BASELINE", hub.baselineIsDefault ? "DEFAULT 70" : "\(Int(hub.baselineBPM)) BPM")
                    row("CONFIDENCE", "\(Int(s.labelConfidence * 100))%")
                }
                HStack(spacing: 10) {
                    if edition == nil {
                        Button { showCorrect = true } label: { Text("NOT HOW I FEEL").font(mono).padding(.horizontal, 14).padding(.vertical, 10).background(card, in: RoundedRectangle(cornerRadius: 8)) }
                    }
                    Button { hub.recalibrate() } label: { Text("RECALIBRATE").font(mono).padding(.horizontal, 14).padding(.vertical, 10).background(card, in: RoundedRectangle(cornerRadius: 8)) }
                    Spacer()
                    Text("SENSING").font(mono).foregroundStyle(theme.secondary)
                    Toggle("", isOn: Binding(get: { hub.isSensingEnabled }, set: { hub.isSensingEnabled = $0 })).labelsHidden().tint(theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.background)
        .foregroundStyle(theme.ink)
        .environment(\.colorScheme, theme.palette.scheme)
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
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
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
                RoundedRectangle(cornerRadius: 1).fill(theme.accent).frame(width: 3, height: CGFloat(4 + (base + i * 3) % 12))
            }
        }
        .frame(height: 14)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(theme.secondary); Spacer(); Text(v) }.font(mono)
    }

    private func chip(_ title: String, _ m: ReaderMode, _ binding: Binding<ReaderMode>) -> some View {
        let on = binding.wrappedValue == m
        return Button { binding.wrappedValue = m; dismiss() } label: {
            Text(title).font(mono)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(on ? theme.ink : card, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(on ? theme.palette.background : theme.ink)
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
