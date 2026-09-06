import Foundation
import Observation
import SwiftUI
import CoreGraphics

/// Fuses every sensor into one UserState and applies the reader's overrides.
@Observable @MainActor
final class SignalHub {
    enum Phase: Equatable { case idle, unsupported, calibrating(Double), live, interrupted }

    private(set) var state = UserState()
    private(set) var phase: Phase = .idle
    private(set) var baselineBPM: Double = 70
    private(set) var baselineBlink: Double = 15
    private(set) var baselineIsDefault = true

    var isSensingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSensingEnabled, forKey: "sensingEnabled"); state.sensingEnabled = isSensingEnabled
            if started { if isSensingEnabled { startCamera() } else { pauseCamera(); phase = .live } }
            recompute()
        }
    }
    /// Reader-corrected label. Wins over prediction until cleared.
    var labelOverride: ReaderLabel? { didSet { recompute() } }
    /// Debug clock for demos (nil = real time).
    var clockOverride: Date? { didSet { recompute() } }

    private let context = ContextMonitor()
    private var face: FaceSessionController?
    private var watch: WatchPulseSource?
    private var ticker: Timer?
    private var started = false
    private var faceStartedAt: Date?
    private var calibrationDone = false
    private var calibBPMs: [Double] = []
    private var calibBlink: Double = 0
    var cameraSupported: Bool { FaceSessionController.isSupported }
    var debugThumbnail: CGImage? { face?.pulse.debugThumbnail }
    var debugEnabled = false { didSet { face?.pulse.debugEnabled = debugEnabled } }
    private(set) var lastPulseEstimate: PulseEstimate?
    private(set) var lastAttentionSample: AttentionSample?

    // Raw inputs from sources
    private var motionSample = MotionSample(posture: .unknown, motion: .unknown, isMovingNow: false)
    private var attention: Double = 0
    private var blinkRate: Double = 0
    private var faceDetected = false
    private var cameraBPM: Double?
    private var cameraConf: Double = 0
    private var watchBPM: Double?
    private var watchAt: Date?
    private var stressEMA: Double = 0
    private var candidateLabel: ReaderLabel?
    private var candidateSince = Date()

    init() {
        isSensingEnabled = UserDefaults.standard.object(forKey: "sensingEnabled") as? Bool ?? true
        state.sensingEnabled = isSensingEnabled
        recompute()
    }

    func start() {
        guard !started else { return }
        started = true
        context.start { [weak self] m in
            guard let self else { return }
            self.motionSample = m
            self.recompute()
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        watch = WatchPulseSource { [weak self] bpm, at, live in self?.ingestWatchPulse(bpm: bpm, at: at, live: live) }
        watch?.start()
        if isSensingEnabled { startCamera() } else { phase = .live }
    }

    func startCamera() {
        guard FaceSessionController.isSupported else { phase = .unsupported; return }
        if face == nil {
            face = FaceSessionController(
                onAttention: { [weak self] s in Task { @MainActor in self?.ingest(sample: s) } },
                onPulse: { [weak self] p in Task { @MainActor in self?.ingest(pulse: p) } },
                onInterruption: { [weak self] interrupted in Task { @MainActor in self?.phase = interrupted ? .interrupted : (self?.calibrationDone == true ? .live : .calibrating(0)) } })
            face?.pulse.debugEnabled = debugEnabled
        }
        face?.run()
        faceStartedAt = nil
        calibrationDone = false
        calibBPMs = []
        phase = .calibrating(0)
    }

    func pauseCamera() { face?.pause() }
    func resumeCamera() { if isSensingEnabled { face?.run() } }

    func recalibrate() {
        faceStartedAt = nil; calibrationDone = false; calibBPMs = []; baselineIsDefault = true; baselineBPM = 70
        face?.attention.gazeCenter = nil
        phase = .calibrating(0)
    }

    /// Histogram of (time of day | label | motion) seen, one count per minute, for overnight pre-generation.
    private var lastHistoryTick = Date.distantPast
    private func recordHistory() {
        guard Date().timeIntervalSince(lastHistoryTick) > 60 else { return }
        lastHistoryTick = .now
        var h = UserDefaults.standard.dictionary(forKey: "stateHistory") as? [String: Int] ?? [:]
        let key = "\(state.timeOfDay.rawValue)|\(state.label.rawValue)|\(state.motion.rawValue)"
        h[key, default: 0] += 1
        UserDefaults.standard.set(h, forKey: "stateHistory")
    }

    /// The states this reader is most often in, synthesised from the history.
    func frequentStates() -> [(String, UserState)] {
        let h = UserDefaults.standard.dictionary(forKey: "stateHistory") as? [String: Int] ?? [:]
        return h.sorted { $0.value > $1.value }.prefix(3).compactMap { entry in
            let p = entry.key.components(separatedBy: "|")
            guard p.count == 3, let tod = TimeOfDay(rawValue: p[0]), let label = ReaderLabel(rawValue: p[1]), let motion = MotionState(rawValue: p[2]) else { return nil }
            var s = UserState(); s.timeOfDay = tod; s.label = label; s.motion = motion
            s.stress = label == .tense ? 0.65 : (label == .calm ? 0.1 : 0.3)
            s.attention = label == .distracted ? 0.3 : 0.85
            let hour: Int = [.earlyMorning: 7, .morning: 9, .midday: 12, .afternoon: 15, .evening: 20, .night: 23][tod] ?? 12
            s.clock = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
            return ("\(tod.label), \(label.rawValue)\(motion == .walking ? ", walking" : "")", s)
        }
    }

    private func tick() {
        recordHistory()
        // Calibration progress: 20s after the face is first seen (extend to 45s if pulse is slow to lock).
        if let t0 = faceStartedAt, !calibrationDone {
            let elapsed = Date().timeIntervalSince(t0)
            let watchFresh = watchAt.map { Date().timeIntervalSince($0) < 90 } ?? false
            let enough = calibBPMs.count >= 5 || watchFresh
            if elapsed >= 20 && (enough || elapsed >= 45) {
                calibrationDone = true
                if let c = face?.attention.medianHit() { face?.attention.gazeCenter = c }
                if watchFresh, let w = watchBPM { setBaseline(bpm: w, blink: blinkRate) }
                else if calibBPMs.count >= 5 { setBaseline(bpm: calibBPMs.sorted()[calibBPMs.count / 2], blink: blinkRate) }
                else { setBaseline(bpm: nil, blink: blinkRate) }
                face?.lockExposureIfPossible()
                phase = .live
            } else {
                phase = .calibrating(min(1, elapsed / 20))
            }
        }
        recompute()
    }

    private func ingest(sample s: AttentionSample) {
        lastAttentionSample = s
        if s.tracked && faceStartedAt == nil { faceStartedAt = .now }
        ingestAttention(attention: s.attention, blinkRate: s.blinkRate, faceDetected: s.tracked)
    }

    private func ingest(pulse p: PulseEstimate) {
        lastPulseEstimate = p
        if !calibrationDone, p.confidence > 0.5 { calibBPMs.append(p.bpm) }
        ingestCameraPulse(bpm: p.bpm, confidence: p.confidence)
    }

    // MARK: - Ingest (later sources call these)
    func ingestAttention(attention: Double, blinkRate: Double, faceDetected: Bool) {
        self.attention = attention; self.blinkRate = blinkRate; self.faceDetected = faceDetected
        recompute()
    }
    private var fingerAt: Date?
    func ingestCameraPulse(bpm: Double, confidence: Double) {
        // A recent fingertip measurement is more trustworthy than a weak face estimate.
        if let f = fingerAt, Date().timeIntervalSince(f) < 180, confidence < 0.5 { return }
        cameraBPM = bpm; cameraConf = confidence
        recompute()
    }
    func ingestFingerPulse(bpm: Double, confidence: Double) {
        fingerAt = .now
        cameraBPM = bpm; cameraConf = max(0.6, confidence)
        if baselineIsDefault { setBaseline(bpm: bpm, blink: nil) }
        recompute()
    }
    private(set) var watchIsLive = false
    private var lastLiveAt: Date?
    func ingestWatchPulse(bpm: Double, at: Date, live: Bool) {
        // Never let an older HealthKit sync overwrite a fresher live reading.
        if let existing = watchAt, at < existing { return }
        watchBPM = bpm; watchAt = at
        if live { lastLiveAt = .now }
        watchIsLive = lastLiveAt.map { Date().timeIntervalSince($0) < 15 } ?? false
        if !calibrationDone, calibBPMs.count < 5 { calibBPMs.append(bpm) }
        recompute()
    }
    func setPhase(_ p: Phase) { phase = p }
    func setBaseline(bpm: Double?, blink: Double?) {
        if let bpm { baselineBPM = bpm; baselineIsDefault = false }
        if let blink { baselineBlink = blink }
    }

    // MARK: - Fusion
    private func recompute() {
        var s = state
        s.sensingEnabled = isSensingEnabled
        s.clock = clockOverride ?? .now
        s.timeOfDay = .from(s.clock)
        s.motion = motionSample.isMovingNow && motionSample.motion == .unknown ? .walking : motionSample.motion
        if motionSample.isMovingNow && motionSample.motion == .stationary { s.motion = .walking }
        s.posture = motionSample.posture
        s.faceDetected = isSensingEnabled && faceDetected
        s.attention = isSensingEnabled ? attention : 0
        s.blinkRate = isSensingEnabled ? blinkRate : 0

        // Pulse fusion: fresh Watch sample wins, else camera, else none.
        if isSensingEnabled, let watchBPM, let watchAt, Date().timeIntervalSince(watchAt) < 90 {
            s.bpm = watchBPM; s.bpmConfidence = 0.95; s.pulseSource = .watch
        } else if isSensingEnabled, let cameraBPM, cameraConf > 0 {
            s.bpm = cameraBPM; s.bpmConfidence = motionSample.isMovingNow ? 0 : cameraConf; s.pulseSource = .camera
        } else {
            s.bpm = nil; s.bpmConfidence = 0; s.pulseSource = .none
        }

        // Stress
        let hr = max(0, min(1, ((s.bpm ?? baselineBPM) - baselineBPM) / 25))
        let blink = max(0, min(1, (s.blinkRate - baselineBlink) / 15))
        let wHR = 0.6 * s.bpmConfidence * (motionSample.isMovingNow ? 0 : 1)
        let raw = isSensingEnabled ? (wHR * hr + 0.4 * blink) / (wHR + 0.4) : 0
        stressEMA = stressEMA + 0.2 * (raw - stressEMA)
        s.stress = stressEMA

        let (label, conf) = StatePredictor.predict(s)
        if let o = labelOverride {
            s.label = o; s.labelConfidence = 1
        } else if label == state.label {
            s.label = label; s.labelConfidence = conf; candidateLabel = nil
        } else {
            // Hysteresis: a new label has to hold for 4s before the page reacts to it.
            if candidateLabel != label { candidateLabel = label; candidateSince = .now }
            if Date().timeIntervalSince(candidateSince) >= 4 { s.label = label; s.labelConfidence = conf; candidateLabel = nil }
            else { s.label = state.label; s.labelConfidence = state.labelConfidence }
        }
        if s != state { state = s }
    }
}
