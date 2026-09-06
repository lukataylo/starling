import Foundation
import ARKit
import simd

struct AttentionSample {
    var tracked: Bool
    var attention: Double
    var blinkRate: Double
    var gazeHit: SIMD2<Float>?
    var headSpeed: Float
}

/// Pure math over ARFaceAnchor values. Called on the AR delegate queue, every frame.
final class AttentionEstimator {
    /// Set by the hub after calibration: where "reading the screen" lands on the camera plane (metres).
    var gazeCenter: SIMD2<Float>?
    private var onScreen = false
    private var bits: [Bool] = []           // last 60 frames
    private var attention: Double = 0
    private var blinkTimes: [TimeInterval] = []
    private var eyesClosed = false
    private var closedSince: TimeInterval = 0
    private var lastPos: SIMD3<Float>?
    private var lastTime: TimeInterval = 0
    private var frameCount = 0
    private var startTime: TimeInterval?
    private var lastSeen: TimeInterval = 0
    private(set) var recentHits: [SIMD2<Float>] = []   // for calibration
    private var offScreenSince: TimeInterval?

    func process(anchor: ARFaceAnchor?, camera: ARCamera, timestamp: TimeInterval) -> AttentionSample? {
        if startTime == nil { startTime = timestamp }
        frameCount += 1
        var bit = false
        var hit: SIMD2<Float>? = nil
        var headSpeed: Float = 0

        if let anchor, anchor.isTracked {
            lastSeen = timestamp
            let A = anchor.transform
            let Cinv = camera.transform.inverse
            let eyeL = A * anchor.leftEyeTransform.columns.3
            let eyeR = A * anchor.rightEyeTransform.columns.3
            let eyeW = (eyeL + eyeR) * 0.5
            let lookW = A * SIMD4<Float>(anchor.lookAtPoint, 1)
            var g = SIMD3<Float>(lookW.x - eyeW.x, lookW.y - eyeW.y, lookW.z - eyeW.z)
            g = simd_normalize(g)
            let eC = Cinv * eyeW
            let gC4 = Cinv * SIMD4<Float>(g, 0)
            let gC = SIMD3<Float>(gC4.x, gC4.y, gC4.z)
            if abs(gC.z) > 1e-4 {
                let t = -eC.z / gC.z
                if t > 0 {
                    let p = SIMD3<Float>(eC.x, eC.y, eC.z) + t * gC
                    hit = SIMD2<Float>(p.x, p.y)
                }
            }
            // Head facing camera?
            let faceFwd4 = A * SIMD4<Float>(0, 0, 1, 0)
            let faceFwd = simd_normalize(SIMD3<Float>(faceFwd4.x, faceFwd4.y, faceFwd4.z))
            let camPos = camera.transform.columns.3
            let toCam = simd_normalize(SIMD3<Float>(camPos.x - eyeW.x, camPos.y - eyeW.y, camPos.z - eyeW.z))
            let facing = acos(max(-1, min(1, simd_dot(faceFwd, toCam)))) < (30 * .pi / 180)

            // Gaze on screen: calibrated radius with hysteresis, else angular fallback.
            var gazeOK: Bool
            if let hit, let c = gazeCenter {
                let d = simd_length(hit - c)
                if onScreen { gazeOK = d < 0.12 } else { gazeOK = d < 0.08 }
            } else {
                let ang = acos(max(-1, min(1, simd_dot(g, toCam))))
                gazeOK = ang < (25 * .pi / 180)
            }
            onScreen = gazeOK
            // Self-correction: if a calibrated centre says "off screen" for 20s while the face is
            // tracked and facing the phone, the calibration was wrong. Drop it and use the angular test.
            if gazeCenter != nil && facing && !gazeOK {
                if offScreenSince == nil { offScreenSince = timestamp }
                if timestamp - (offScreenSince ?? timestamp) > 20 { gazeCenter = nil; recentHits.removeAll(); offScreenSince = nil }
            } else { offScreenSince = nil }

            // Blinks
            let bl = (anchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0 + (anchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0)) / 2
            let bAvg = ((anchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0) + (anchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0)) / 2
            _ = bl
            var longClosed = false
            if !eyesClosed && bAvg > 0.5 { eyesClosed = true; closedSince = timestamp }
            else if eyesClosed && bAvg < 0.3 {
                eyesClosed = false
                let dur = timestamp - closedSince
                if dur >= 0.05 && dur <= 0.5 { blinkTimes.append(timestamp) }
            }
            if eyesClosed && timestamp - closedSince > 0.5 { longClosed = true }

            // Head speed
            let pos = SIMD3<Float>(A.columns.3.x, A.columns.3.y, A.columns.3.z)
            if let lp = lastPos, timestamp > lastTime { headSpeed = simd_length(pos - lp) / Float(timestamp - lastTime) }
            lastPos = pos; lastTime = timestamp

            bit = gazeOK && facing && !longClosed
            if let hit, gazeOK && facing { recentHits.append(hit); if recentHits.count > 600 { recentHits.removeFirst(recentHits.count - 600) } }
        } else if timestamp - lastSeen > 1.5 {
            bit = false
        } else {
            bit = onScreen   // brief tracking loss: hold last value
        }

        bits.append(bit)
        if bits.count > 30 { bits.removeFirst(bits.count - 30) }
        blinkTimes.removeAll { timestamp - $0 > 60 }

        guard frameCount % 15 == 0 else { return nil }
        let raw = Double(bits.filter { $0 }.count) / Double(max(1, bits.count))
        attention = 0.5 * attention + 0.5 * raw
        let elapsed = max(15, timestamp - (startTime ?? timestamp))
        let blinkRate = Double(blinkTimes.count) * (60 / min(60, elapsed))
        let tracked = anchor?.isTracked == true || timestamp - lastSeen <= 1.5
        return AttentionSample(tracked: tracked, attention: attention, blinkRate: blinkRate, gazeHit: hit, headSpeed: headSpeed)
    }

    func medianHit() -> SIMD2<Float>? {
        guard recentHits.count >= 30 else { return nil }
        let xs = recentHits.map(\.x).sorted(), ys = recentHits.map(\.y).sorted()
        return SIMD2<Float>(xs[xs.count / 2], ys[ys.count / 2])
    }
}
