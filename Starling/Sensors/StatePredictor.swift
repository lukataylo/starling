import Foundation

enum StatePredictor {
    /// Map fused signals to a label the reader can read and correct.
    static func predict(_ s: UserState) -> (ReaderLabel, Double) {
        let moving = s.motion == .walking || s.motion == .running || s.motion == .automotive
        let late = s.timeOfDay == .night || s.timeOfDay == .earlyMorning
        let sensing = s.sensingEnabled && s.faceDetected
        if sensing && s.attention < 0.35 { return (.distracted, 0.6 + 0.3 * (0.35 - s.attention) / 0.35) }
        if s.stress > 0.6 && !moving { return (.tense, min(0.95, 0.5 + s.stress * 0.5)) }
        if late && (s.posture == .lyingDown || s.posture == .reclined) && s.stress < 0.4 { return (.tired, 0.65) }
        if sensing && s.blinkRate > 22 && s.attention < 0.6 { return (.tired, 0.55) }
        if s.stress < 0.3 && (s.posture == .reclined || s.posture == .lyingDown) { return (.calm, 0.7) }
        if sensing && s.attention > 0.75 && s.stress < 0.5 { return (.focused, 0.75) }
        if !sensing && !moving { return (.calm, 0.35) }
        return (.focused, 0.4)
    }
}
