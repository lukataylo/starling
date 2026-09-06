import Foundation

enum Posture: String, Codable, CaseIterable { case upright, reclined, lyingDown, flat, unknown }
enum MotionState: String, Codable, CaseIterable { case stationary, walking, running, automotive, unknown }
enum TimeOfDay: String, Codable, CaseIterable {
    case earlyMorning, morning, midday, afternoon, evening, night
    static func from(_ date: Date) -> TimeOfDay {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<8: return .earlyMorning
        case 8..<11: return .morning
        case 11..<14: return .midday
        case 14..<18: return .afternoon
        case 18..<22: return .evening
        default: return .night
        }
    }
    var label: String {
        switch self {
        case .earlyMorning: return "early morning"
        case .morning: return "morning"
        case .midday: return "midday"
        case .afternoon: return "afternoon"
        case .evening: return "evening"
        case .night: return "night"
        }
    }
}
enum PulseSource: String, Codable { case watch, camera, none }
enum ReaderLabel: String, Codable, CaseIterable {
    case calm, focused, tense, tired, distracted
    var symbol: String {
        switch self {
        case .calm: return "leaf"
        case .focused: return "scope"
        case .tense: return "bolt.heart"
        case .tired: return "moon.zzz"
        case .distracted: return "eye.slash"
        }
    }
}

struct UserState: Codable, Equatable {
    var faceDetected = false
    var attention: Double = 0          // 0..1
    var blinkRate: Double = 0          // blinks / minute
    var bpm: Double? = nil
    var bpmConfidence: Double = 0
    var pulseSource: PulseSource = .none
    var stress: Double = 0             // 0..1
    var posture: Posture = .unknown
    var motion: MotionState = .unknown
    var timeOfDay: TimeOfDay = .from(.now)
    var clock: Date = .now
    var label: ReaderLabel = .focused
    var labelConfidence: Double = 0
    var sensingEnabled = true

    /// Quantised key so small sensor jitter doesn't refetch a generation.
    var bucket: String {
        let s = stress < 0.33 ? "lo" : (stress < 0.66 ? "mid" : "hi")
        return "\(timeOfDay.rawValue)|\(motion.rawValue)|\(posture.rawValue)|\(s)|\(label.rawValue)"
    }

    /// Compact JSON + honesty hints for the model.
    func promptSummary() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_GB")
        var lines: [String] = []
        lines.append("local_time: \(f.string(from: clock)) (\(timeOfDay.label))")
        lines.append("motion: \(motion.rawValue), posture: \(posture.rawValue)")
        if sensingEnabled {
            lines.append("face_detected: \(faceDetected), attention: \(String(format: "%.2f", attention)), blink_rate_per_min: \(Int(blinkRate))")
            if let bpm, bpmConfidence >= 0.3 {
                lines.append("heart_rate_bpm: \(Int(bpm)) (source: \(pulseSource.rawValue), confidence \(String(format: "%.2f", bpmConfidence)))")
            } else {
                lines.append("heart_rate_bpm: unavailable or low confidence — ignore")
            }
            lines.append("stress_estimate: \(String(format: "%.2f", stress)) (0 calm .. 1 tense)")
            lines.append("predicted_state: \(label.rawValue) (confidence \(String(format: "%.2f", labelConfidence)))")
        } else {
            lines.append("sensing: off by user choice — use only time, motion and posture")
        }
        return lines.joined(separator: "\n")
    }
}
