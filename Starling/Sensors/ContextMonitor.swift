import Foundation
import CoreMotion

struct MotionSample: Equatable {
    var posture: Posture
    var motion: MotionState
    var isMovingNow: Bool
}

/// CoreMotion activity + gravity-based posture. Publishes on the main queue.
final class ContextMonitor {
    private let activity = CMMotionActivityManager()
    private let motion = CMMotionManager()
    private var lastPosture: Posture = .unknown
    private var postureCandidate: Posture = .unknown
    private var postureCandidateSince = Date()
    private var accelWindow: [Double] = []
    private var current = MotionSample(posture: .unknown, motion: .unknown, isMovingNow: false)
    private var onSample: ((MotionSample) -> Void)?

    func start(onSample: @escaping (MotionSample) -> Void) {
        self.onSample = onSample
        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: .main) { [weak self] a in
                guard let self, let a else { return }
                var m: MotionState = .unknown
                if a.automotive { m = .automotive } else if a.running { m = .running } else if a.walking { m = .walking } else if a.stationary { m = .stationary }
                if m != .unknown && m != self.current.motion { self.current.motion = m; self.publish() }
            }
        }
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let g = dm.gravity
            let candidate: Posture
            if g.z > 0.5 { candidate = .lyingDown }
            else if g.y < -0.6 { candidate = .upright }
            else if g.z < -0.75 { candidate = .flat }
            else { candidate = .reclined }
            if candidate != self.postureCandidate { self.postureCandidate = candidate; self.postureCandidateSince = .now }
            if candidate != self.current.posture, Date().timeIntervalSince(self.postureCandidateSince) > 1.0 {
                self.current.posture = candidate; self.publish()
            }
            let ua = dm.userAcceleration
            let mag = (ua.x * ua.x + ua.y * ua.y + ua.z * ua.z).squareRoot()
            self.accelWindow.append(mag)
            if self.accelWindow.count > 10 { self.accelWindow.removeFirst() }
            let mean = self.accelWindow.reduce(0, +) / Double(self.accelWindow.count)
            let sd = (self.accelWindow.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(self.accelWindow.count)).squareRoot()
            let moving = sd > 0.08
            if moving != self.current.isMovingNow { self.current.isMovingNow = moving; self.publish() }
        }
    }

    func stop() {
        activity.stopActivityUpdates()
        motion.stopDeviceMotionUpdates()
    }

    private func publish() { onSample?(current) }
}
