import Foundation
import AVFoundation
import Accelerate
import Observation

/// Fingertip photoplethysmography on the rear camera with the torch on. Reliable where face rPPG is not.
@Observable
final class FingerPulseMeasurer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Phase: Equatable { case idle, waitingForFinger, measuring(Double), done(Double, Double), failed(String) }
    var phase: Phase = .idle
    var waveform: [Float] = []          // last ~3s of normalised signal for the UI
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "starling.finger", qos: .userInitiated)
    private var samples: [(t: Double, v: Float)] = []
    private var startTime: Double?
    private let duration: Double = 15
    private var device: AVCaptureDevice?

    func start() {
        samples = []; waveform = []; startTime = nil
        phase = .waitingForFinger
        queue.async { [self] in
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async { self.phase = .failed("No rear camera") }; return
            }
            device = dev
            session.beginConfiguration()
            session.sessionPreset = .low
            if let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) { session.addInput(input) }
            let out = AVCaptureVideoDataOutput()
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(out) { session.addOutput(out) }
            session.commitConfiguration()
            session.startRunning()
            try? dev.lockForConfiguration()
            if dev.hasTorch { try? dev.setTorchModeOn(level: 0.6) }
            if dev.isExposureModeSupported(.locked) { dev.exposureMode = .continuousAutoExposure }
            dev.unlockForConfiguration()
        }
    }

    func stop() {
        queue.async { [self] in
            if let d = device, d.hasTorch { try? d.lockForConfiguration(); d.torchMode = .off; d.unlockForConfiguration() }
            if session.isRunning { session.stopRunning() }
            for i in session.inputs { session.removeInput(i) }
            for o in session.outputs { session.removeOutput(o) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), rb = CVPixelBufferGetBytesPerRow(pb)
        let p = base.assumingMemoryBound(to: UInt8.self)
        // Mean red over the centre, subsampled.
        var sum = 0, n = 0, gsum = 0
        var y = h / 4
        while y < 3 * h / 4 { var x = w / 4; while x < 3 * w / 4 { let o = y * rb + x * 4; sum += Int(p[o + 2]); gsum += Int(p[o + 1]); n += 1; x += 4 }; y += 4 }
        let red = Float(sum) / Float(max(1, n)), green = Float(gsum) / Float(max(1, n))
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        // Finger present when the frame is dominated by red (torch through skin).
        let fingerOn = red > 120 && red > green * 1.6
        DispatchQueue.main.async { [self] in
            if !fingerOn {
                if case .measuring = phase { phase = .waitingForFinger; samples = []; startTime = nil; waveform = [] }
                else if case .done = phase { } else { phase = .waitingForFinger }
                return
            }
            if startTime == nil { startTime = t; samples = [] }
            samples.append((t, red))
            let elapsed = t - (startTime ?? t)
            phase = .measuring(min(1, elapsed / duration))
            updateWaveform()
            if elapsed >= duration { finish() }
        }
    }

    private func updateWaveform() {
        let tail = samples.suffix(90).map(\.v)
        guard tail.count > 10 else { return }
        let mean = tail.reduce(0, +) / Float(tail.count)
        let dev = max(0.5, (tail.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(tail.count)).squareRoot())
        waveform = tail.map { ($0 - mean) / dev }
    }

    private func finish() {
        let n = samples.count
        guard n > 100 else { phase = .failed("Not enough signal"); stop(); return }
        let fs = Double(n - 1) / max(0.001, samples[n - 1].t - samples[0].t)
        let y = samples.map(\.v)
        let win = max(3, Int(1.5 * fs))
        var m = [Float](repeating: 0, count: n)
        for i in 0..<n { let lo = max(0, i - win / 2), hi = min(n - 1, i + win / 2); var s: Float = 0; for j in lo...hi { s += y[j] }; let avg = s / Float(hi - lo + 1); m[i] = avg > 0 ? y[i] / avg - 1 : 0 }
        let N = 2048
        var hann = [Float](repeating: 0, count: n); vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var x = [Float](repeating: 0, count: N); for i in 0..<n { x[i] = m[i] * hann[i] }
        let log2n = vDSP_Length(log2(Double(N)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { phase = .failed("FFT"); stop(); return }
        defer { vDSP_destroy_fftsetup(setup) }
        var real = [Float](repeating: 0, count: N / 2), imag = [Float](repeating: 0, count: N / 2), power = [Float](repeating: 0, count: N / 2)
        real.withUnsafeMutableBufferPointer { rp in imag.withUnsafeMutableBufferPointer { ip in
            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
            x.withUnsafeBufferPointer { xp in xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: N / 2) { cp in vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(N / 2)) } }
            vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(N / 2))
        } }
        let binHz = fs / Double(N)
        let lo = Int(0.7 / binHz), hi = min(N / 2 - 2, Int(3.0 / binHz))
        guard hi > lo + 2 else { phase = .failed("Frame rate too low"); stop(); return }
        var best = lo; var band: Float = 0
        for i in lo...hi { band += power[i]; if power[i] > power[best] { best = i } }
        let p0 = power[best - 1], p1 = power[best], p2 = power[best + 1]
        let denom = p0 - 2 * p1 + p2
        let delta = denom != 0 ? 0.5 * (p0 - p2) / denom : 0
        let bpm = (Double(best) + Double(delta)) * binHz * 60
        let snr = band > 0 ? Double((p0 + p1 + p2) / band) : 0
        let conf = max(0.3, min(1, (snr - 0.1) / 0.3))
        phase = .done(bpm, conf)
        stop()
    }
}
