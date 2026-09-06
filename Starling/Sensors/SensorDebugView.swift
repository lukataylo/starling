import SwiftUI

/// Live signals. Debugging tool for us, "show the judges what it senses" panel for the demo.
struct SensorDebugView: View {
    @Environment(SignalHub.self) private var hub
    @State private var tick = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let s = hub.state
        List {
            Section("Phase") {
                Text(phaseText)
                if !hub.cameraSupported { Text("Face tracking not supported on this device (needs a TrueDepth front camera).").foregroundStyle(.red) }
                Button("Recalibrate") { hub.recalibrate() }
            }
            Section("Attention") {
                Gauge(value: s.attention) { Text("On screen") }.gaugeStyle(.accessoryLinear)
                LabeledContent("Face", value: s.faceDetected ? "tracked" : "not detected")
                LabeledContent("Blink rate", value: "\(Int(s.blinkRate)) / min")
                if let a = hub.lastAttentionSample, let g = a.gazeHit {
                    LabeledContent("Gaze hit (m)", value: String(format: "%.3f, %.3f", g.x, g.y))
                    LabeledContent("Head speed", value: String(format: "%.3f m/s", a.headSpeed))
                }
            }
            Section("Pulse") {
                LabeledContent("Fused", value: s.bpm.map { "\(Int($0)) bpm via \(s.pulseSource.rawValue) (\(Int(s.bpmConfidence * 100))%)" } ?? "—")
                if let p = hub.lastPulseEstimate {
                    LabeledContent("Camera raw", value: String(format: "%.0f bpm, conf %.2f, valid %.0f%%", p.bpm, p.confidence, p.validFraction * 100))
                    LabeledContent("ROI mean luma", value: String(format: "%.1f", p.roiMean))
                    LabeledContent("ROI rect", value: "\(Int(p.roiRect.minX)),\(Int(p.roiRect.minY)) \(Int(p.roiRect.width))×\(Int(p.roiRect.height))")
                }
                LabeledContent("Baseline", value: hub.baselineIsDefault ? "default 70" : "\(Int(hub.baselineBPM)) bpm")
                Toggle("Show ROI thumbnail", isOn: Binding(get: { hub.debugEnabled }, set: { hub.debugEnabled = $0 }))
                if hub.debugEnabled, let img = hub.debugThumbnail {
                    Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 180)
                }
            }
            Section("Context") {
                LabeledContent("Motion", value: s.motion.rawValue)
                LabeledContent("Posture", value: s.posture.rawValue)
                LabeledContent("Time", value: s.timeOfDay.label)
                LabeledContent("Stress", value: String(format: "%.2f", s.stress))
                LabeledContent("Predicted", value: "\(s.label.rawValue) (\(Int(s.labelConfidence * 100))%)")
                LabeledContent("Bucket", value: s.bucket).font(.caption2)
            }
        }
        .navigationTitle("Signals")
        .onReceive(timer) { _ in tick += 1 }
    }

    private var phaseText: String {
        switch hub.phase {
        case .idle: return "idle"
        case .unsupported: return "unsupported"
        case .calibrating(let p): return "calibrating \(Int(p * 100))% — keep reading normally"
        case .live: return "live"
        case .interrupted: return "interrupted (camera in use elsewhere?)"
        }
    }
}
