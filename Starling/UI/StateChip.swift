import SwiftUI

/// The honest readout. Raw numbers, so the reader can see the interface respond to them.
struct StateChip: View {
    @Environment(SignalHub.self) private var hub
    var compact = false

    var body: some View {
        let s = hub.state
        HStack(spacing: 8) {
            Image(systemName: s.label.symbol)
            Text(s.label.rawValue.capitalized).fontWeight(.semibold)
            if !compact {
                Divider().frame(height: 12)
                Group {
                    if let bpm = s.bpm, s.bpmConfidence >= 0.4 {
                        Label("\(Int(bpm))", systemImage: s.pulseSource == .watch ? "applewatch" : "camera")
                    } else if s.sensingEnabled {
                        Label("calibrating", systemImage: "heart")
                    }
                    if s.sensingEnabled {
                        Label("\(Int(s.attention * 100))%", systemImage: s.faceDetected ? "eye" : "eye.slash")
                    }
                    Label(motionText(s), systemImage: motionSymbol(s))
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private func motionText(_ s: UserState) -> String {
        switch s.motion {
        case .walking: return "walking"
        case .running: return "running"
        case .automotive: return "in transit"
        default:
            switch s.posture {
            case .lyingDown: return "lying down"
            case .reclined: return "reclined"
            case .flat: return "on table"
            default: return "still"
            }
        }
    }
    private func motionSymbol(_ s: UserState) -> String {
        switch s.motion {
        case .walking, .running: return "figure.walk"
        case .automotive: return "tram"
        default: return s.posture == .lyingDown || s.posture == .reclined ? "bed.double" : "figure.seated.side"
        }
    }
}
