import Foundation
import ARKit
import Accelerate
import CoreVideo
import CoreGraphics

struct PulseEstimate {
    var bpm: Double
    var confidence: Double
    var validFraction: Double
    var roiMean: Float
    var roiRect: CGRect
}

/// Remote photoplethysmography from the forehead in ARFrame.capturedImage (luma plane).
final class PulseEstimator {
    private struct Sample { var t: TimeInterval; var y: Float; var valid: Bool }
    private var ring: [Sample] = []
    private var lastROICenter: CGPoint?
    private var lastMean: Float = 0
    private var lastEstimateTime: TimeInterval = 0
    private var bpmSmoothed: Double = 0
    private var lastBPM: Double = 0
    private var frameCount = 0
    private(set) var debugThumbnail: CGImage?
    var debugEnabled = false
    private var lastThumbTime: TimeInterval = 0

    func process(pixelBuffer: CVPixelBuffer, anchor: ARFaceAnchor, camera: ARCamera, timestamp: TimeInterval, headSpeed: Float) -> PulseEstimate? {
        frameCount += 1
        let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let size = CGSize(width: w, height: h)
        guard let roi = roiRect(anchor: anchor, camera: camera, imageSize: size) else {
            push(t: timestamp, y: lastMean, valid: false); return maybeEstimate(timestamp, roi: .zero)
        }
        let (mean, saturated) = Self.meanLuma(pixelBuffer, roi: roi)
        var valid = anchor.isTracked && headSpeed < 0.05 && saturated < 0.05 && mean > 40
        if let c = lastROICenter, hypot(c.x - roi.midX, c.y - roi.midY) > 3 { valid = false }
        if lastMean > 0, abs(mean - lastMean) / lastMean > 0.03 { valid = false }
        lastROICenter = CGPoint(x: roi.midX, y: roi.midY)
        lastMean = mean
        push(t: timestamp, y: mean, valid: valid)
        if debugEnabled, timestamp - lastThumbTime > 0.5 {
            lastThumbTime = timestamp
            debugThumbnail = Self.thumbnail(pixelBuffer, roi: roi)
        }
        return maybeEstimate(timestamp, roi: roi)
    }

    private func push(t: TimeInterval, y: Float, valid: Bool) {
        ring.append(Sample(t: t, y: y, valid: valid))
        while let first = ring.first, t - first.t > 15 { ring.removeFirst() }
    }

    func roiRect(anchor: ARFaceAnchor, camera: ARCamera, imageSize: CGSize) -> CGRect? {
        let A = anchor.transform
        func proj(_ p: SIMD4<Float>) -> CGPoint {
            let wp = A * p
            return camera.projectPoint(SIMD3<Float>(wp.x, wp.y, wp.z), orientation: .landscapeRight, viewportSize: imageSize)
        }
        let L = proj(anchor.leftEyeTransform.columns.3)
        let R = proj(anchor.rightEyeTransform.columns.3)
        let O = proj(SIMD4<Float>(0, 0, 0, 1))
        let U = proj(SIMD4<Float>(0, 0.05, 0, 1))
        let d = hypot(L.x - R.x, L.y - R.y)
        guard d.isFinite, d > 12 else { return nil }
        var up = CGPoint(x: U.x - O.x, y: U.y - O.y)
        let ul = hypot(up.x, up.y); guard ul > 0.001 else { return nil }
        up = CGPoint(x: up.x / ul, y: up.y / ul)
        let mid = CGPoint(x: (L.x + R.x) / 2, y: (L.y + R.y) / 2)
        let c = CGPoint(x: mid.x + 0.9 * d * up.x, y: mid.y + 0.9 * d * up.y)
        // Axis-aligned rect; orientation of the "wide" side follows the eye line.
        let horizontalEyes = abs(L.x - R.x) >= abs(L.y - R.y)
        let rw = horizontalEyes ? 1.1 * d : 0.45 * d
        let rh = horizontalEyes ? 0.45 * d : 1.1 * d
        var rect = CGRect(x: c.x - rw / 2, y: c.y - rh / 2, width: rw, height: rh).integral
        rect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard rect.width >= 16, rect.height >= 8 else { return nil }
        return rect
    }

    static func meanLuma(_ buffer: CVPixelBuffer, roi: CGRect) -> (mean: Float, saturatedFraction: Float) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return (0, 1) }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let x = Int(roi.minX), y = Int(roi.minY), w = Int(roi.width), h = Int(roi.height)
        let ptr = base.advanced(by: y * rowBytes + x)
        var sum: Int = 0, sat: Int = 0
        let p = ptr.assumingMemoryBound(to: UInt8.self)
        for row in 0..<h {
            let r = p.advanced(by: row * rowBytes)
            for col in 0..<w { let v = Int(r[col]); sum += v; if v >= 254 { sat += 1 } }
        }
        let n = max(1, w * h)
        return (Float(sum) / Float(n), Float(sat) / Float(n))
    }

    private func maybeEstimate(_ now: TimeInterval, roi: CGRect) -> PulseEstimate? {
        guard now - lastEstimateTime >= 1.0 else { return nil }
        lastEstimateTime = now
        let window = ring.filter { now - $0.t <= 12 }
        guard window.count >= 90 else { return nil }
        let validFraction = Double(window.filter(\.valid).count) / Double(window.count)
        guard validFraction >= 0.66 else {
            return PulseEstimate(bpm: bpmSmoothed, confidence: 0, validFraction: validFraction, roiMean: lastMean, roiRect: roi)
        }
        // Interpolate invalid samples (short gaps) by carrying the previous value.
        var y: [Float] = []
        var t: [Double] = []
        var carry: Float = window.first(where: { $0.valid })?.y ?? lastMean
        for s in window { if s.valid { carry = s.y }; y.append(carry); t.append(s.t) }
        let n = y.count
        let fs = Double(n - 1) / max(0.001, t[n - 1] - t[0])
        guard fs > 10 else { return nil }
        // Normalising detrend: y / movingAverage(1.5s) - 1
        let win = max(3, Int(1.5 * fs))
        var m = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - win / 2), hi = min(n - 1, i + win / 2)
            var s: Float = 0; for j in lo...hi { s += y[j] }
            let avg = s / Float(hi - lo + 1)
            m[i] = avg > 0 ? y[i] / avg - 1 : 0
        }
        // Hann window + zero pad to 1024, real FFT via vDSP.
        let N = 1024
        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var x = [Float](repeating: 0, count: N)
        for i in 0..<n { x[i] = m[i] * hann[i] }
        let log2n = vDSP_Length(log2(Double(N)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }
        var real = [Float](repeating: 0, count: N / 2)
        var imag = [Float](repeating: 0, count: N / 2)
        var power = [Float](repeating: 0, count: N / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: N / 2) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(N / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(N / 2))
            }
        }
        let binHz = fs / Double(N)
        let lo = Int(0.7 / binHz), hi = min(N / 2 - 2, Int(3.0 / binHz))
        guard hi > lo + 2 else { return nil }
        var best = lo, bandSum: Float = 0
        for i in lo...hi { bandSum += power[i]; if power[i] > power[best] { best = i } }
        // Harmonic guard: prefer a half-frequency peak if it's strong.
        let half = best / 2
        if half >= lo, power[half] >= 0.6 * power[best] { best = half }
        // Parabolic interpolation
        let p0 = power[best - 1], p1 = power[best], p2 = power[best + 1]
        let denom = (p0 - 2 * p1 + p2)
        let delta = denom != 0 ? 0.5 * (p0 - p2) / denom : 0
        let freq = (Double(best) + Double(delta)) * binHz
        let bpm = freq * 60
        let snr = bandSum > 0 ? Double((p0 + p1 + p2) / bandSum) : 0
        var conf = max(0, min(1, (snr - 0.12) / 0.28)) * validFraction
        // Autocorrelation cross-check
        if let acfBPM = acfEstimate(m, fs: fs), abs(acfBPM - bpm) < 6 { conf = min(1, conf + 0.2) }
        if lastBPM > 0, abs(bpm - lastBPM) > 12 { conf *= 0.5 }
        lastBPM = bpm
        if bpmSmoothed == 0 { bpmSmoothed = bpm } else { bpmSmoothed += 0.5 * conf * (bpm - bpmSmoothed) }
        return PulseEstimate(bpm: bpmSmoothed, confidence: conf, validFraction: validFraction, roiMean: lastMean, roiRect: roi)
    }

    private func acfEstimate(_ m: [Float], fs: Double) -> Double? {
        let n = m.count
        let minLag = Int(fs / 3.0), maxLag = min(n - 2, Int(fs / 0.7))
        guard maxLag > minLag else { return nil }
        var bestLag = minLag, bestVal: Float = -.greatestFiniteMagnitude
        for lag in minLag...maxLag {
            var s: Float = 0
            for i in 0..<(n - lag) { s += m[i] * m[i + lag] }
            if s > bestVal { bestVal = s; bestLag = lag }
        }
        return 60 * fs / Double(bestLag)
    }

    private static func thumbnail(_ buffer: CVPixelBuffer, roi: CGRect) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        // Downsample whole luma plane by 4 and draw ROI box, so we can see where it landed.
        let dw = w / 4, dh = h / 4
        var pixels = [UInt8](repeating: 0, count: dw * dh)
        let p = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<dh { for x in 0..<dw { pixels[y * dw + x] = p[(y * 4) * rowBytes + x * 4] } }
        let rx0 = Int(roi.minX) / 4, ry0 = Int(roi.minY) / 4, rx1 = Int(roi.maxX) / 4, ry1 = Int(roi.maxY) / 4
        for x in max(0, rx0)..<min(dw, rx1) { if ry0 >= 0 && ry0 < dh { pixels[ry0 * dw + x] = 255 }; if ry1 >= 0 && ry1 < dh { pixels[ry1 * dw + x] = 255 } }
        for y in max(0, ry0)..<min(dh, ry1) { if rx0 >= 0 && rx0 < dw { pixels[y * dw + rx0] = 255 }; if rx1 >= 0 && rx1 < dw { pixels[y * dw + rx1] = 255 } }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: dw, height: dh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: dw, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
