import Foundation
import ARKit
import AVFoundation

/// The single ARSession. No view. Fans every frame out to the attention and pulse estimators.
final class FaceSessionController: NSObject, ARSessionDelegate {
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    let attention = AttentionEstimator()
    let pulse = PulseEstimator()
    private let session = ARSession()
    private let queue = DispatchQueue(label: "starling.sensing.ar", qos: .userInitiated)
    private let onAttention: (AttentionSample) -> Void
    private let onPulse: (PulseEstimate) -> Void
    private let onInterruption: (Bool) -> Void
    private var lastHeadSpeed: Float = 0
    private var running = false
    /// Timestamp of the most recent `didUpdate frame`. Written on the delegate queue, read on main by the hub's watchdog.
    nonisolated(unsafe) private(set) var lastFrameAt: Date?

    init(onAttention: @escaping (AttentionSample) -> Void, onPulse: @escaping (PulseEstimate) -> Void, onInterruption: @escaping (Bool) -> Void) {
        self.onAttention = onAttention
        self.onPulse = onPulse
        self.onInterruption = onInterruption
        super.init()
        session.delegate = self
        session.delegateQueue = queue
    }

    private func makeConfig() -> ARFaceTrackingConfiguration {
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = false
        config.isWorldTrackingEnabled = false
        let formats = ARFaceTrackingConfiguration.supportedVideoFormats
        if let f = formats.filter({ $0.framesPerSecond == 30 }).min(by: { $0.imageResolution.width < $1.imageResolution.width }) {
            config.videoFormat = f
        }
        return config
    }

    func run() {
        guard Self.isSupported else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            self.session.run(self.makeConfig(), options: [.resetTracking, .removeExistingAnchors])
            self.running = true
            self.lastFrameAt = .now   // give the fresh session a full grace period before the watchdog judges it
        }
    }

    func pause() { session.pause(); running = false }

    /// Try to freeze exposure/white balance so rPPG sees a stable baseline. Best effort.
    func lockExposureIfPossible() {
        guard let device = ARFaceTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.unlockForConfiguration()
        } catch { }
    }

    // MARK: ARSessionDelegate (background queue). Never retain the frame.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrameAt = .now
        let anchor = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        if let s = attention.process(anchor: anchor, camera: frame.camera, timestamp: frame.timestamp) {
            lastHeadSpeed = s.headSpeed
            onAttention(s)
        }
        if let anchor, anchor.isTracked {
            if let p = pulse.process(pixelBuffer: frame.capturedImage, anchor: anchor, camera: frame.camera, timestamp: frame.timestamp, headSpeed: lastHeadSpeed) {
                onPulse(p)
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) { onInterruption(true) }
    func sessionInterruptionEnded(_ session: ARSession) {
        session.run(makeConfig(), options: [.resetTracking])
        onInterruption(false)
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        onInterruption(true)
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.session.run(self.makeConfig(), options: [.resetTracking, .removeExistingAnchors])
        }
    }
}
