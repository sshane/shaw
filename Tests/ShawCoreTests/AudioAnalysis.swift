import Foundation
@testable import ShawCore

/// Measurements for checking sounds without listening: spectra, loudness, pitch, and tails.
enum AudioAnalysis {
    /// In-place iterative radix-2 FFT. `re.count` must be a power of two.
    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2 * Double.pi / Double(len)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0
                for k in 0..<(len / 2) {
                    let a = i + k, b = i + k + len / 2
                    let tr = re[b] * cr - im[b] * ci
                    let ti = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                    let ncr = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = ncr
                }
                i += len
            }
            len <<= 1
        }
    }

    /// Power spectrum (linear power per bin, 0...n/2) of `x[start..<start+len]`, zero-padded to a power of two,
    /// with a Blackman-Harris window (low leakage, so aliasing measurements are honest).
    static func powerSpectrum(_ x: [Float], start: Int = 0, length: Int? = nil, size: Int? = nil, window: Bool = true) -> [Double] {
        let len = min(length ?? (x.count - start), x.count - start)
        var n = 1
        while n < max(size ?? len, len) { n <<= 1 }
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        for i in 0..<len {
            let t = Double(i) / Double(max(1, len - 1))
            let w = 0.35875 - 0.48829 * cos(2 * .pi * t) + 0.14128 * cos(4 * .pi * t) - 0.01168 * cos(6 * .pi * t)
            re[i] = Double(x[start + i]) * (window ? w : 1)
        }
        fft(&re, &im)
        return (0...(n / 2)).map { re[$0] * re[$0] + im[$0] * im[$0] }
    }

    static func binHz(_ spec: [Double], _ sr: Double) -> Double { sr / Double((spec.count - 1) * 2) }

    /// Fraction of energy between f1 and f2.
    static func bandFraction(_ spec: [Double], _ sr: Double, _ f1: Double, _ f2: Double) -> Double {
        let hz = binHz(spec, sr)
        let total = spec.reduce(0, +)
        guard total > 0 else { return 0 }
        var s = 0.0
        for (i, p) in spec.enumerated() where Double(i) * hz >= f1 && Double(i) * hz < f2 { s += p }
        return s / total
    }

    /// The strongest local maxima of the spectrum between f1 and f2, as (Hz, dB relative to the strongest).
    static func peaks(_ spec: [Double], _ sr: Double, count: Int, from f1: Double = 20, to f2: Double = 20000) -> [(Double, Double)] {
        let hz = binHz(spec, sr)
        var found: [(Double, Double)] = []
        let lo = max(2, Int(f1 / hz)), hi = min(spec.count - 3, Int(f2 / hz))
        guard hi > lo else { return [] }
        for i in lo...hi where spec[i] > spec[i - 1] && spec[i] >= spec[i + 1] && spec[i] > spec[i - 2] && spec[i] >= spec[i + 2] {
            // Parabolic interpolation on dB for a finer frequency.
            let a = 10 * log10(spec[i - 1] + 1e-30), b = 10 * log10(spec[i] + 1e-30), c = 10 * log10(spec[i + 1] + 1e-30)
            let d = (a - c) / (2 * (a - 2 * b + c))
            found.append(((Double(i) + (d.isFinite ? d : 0)) * hz, b))
        }
        found.sort { $0.1 > $1.1 }
        // Drop maxima within 3% of a stronger one (window side lobes, noise ripples).
        var kept: [(Double, Double)] = []
        for f in found where !kept.contains(where: { abs($0.0 - f.0) < max(8, $0.0 * 0.03) }) {
            kept.append(f)
            if kept.count == count { break }
        }
        let top = kept.first?.1 ?? 0
        return kept.map { ($0.0, $0.1 - top) }
    }

    static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    static func db(_ v: Double) -> Double { 20 * log10(max(v, 1e-9)) }

    static func rms(_ x: [Float], _ a: Int = 0, _ b: Int? = nil) -> Double {
        let e = min(b ?? x.count, x.count)
        guard e > a else { return 0 }
        var s = 0.0
        for i in a..<e { s += Double(x[i]) * Double(x[i]) }
        return sqrt(s / Double(e - a))
    }

    static func mean(_ x: [Float]) -> Double { x.reduce(0.0) { $0 + Double($1) } / Double(max(1, x.count)) }

    /// Frequency by counting zero crossings of a low-passed copy in `x[a..<b]`.
    static func zeroCrossingHz(_ x: [Float], _ sr: Double, _ a: Int, _ b: Int, lowpass: Double = 600) -> Double {
        var lp = Biquad()
        lp.set(.lowpass, freq: lowpass, q: 0.707, sampleRate: sr)
        let y = x.map { lp.process($0) }
        var crossings: [Double] = []
        for i in max(1, a)..<min(b, y.count) where (y[i - 1] < 0) != (y[i] < 0) {
            let f = Double(y[i - 1]) / Double(y[i - 1] - y[i])
            crossings.append(Double(i - 1) + f)
        }
        guard crossings.count >= 3 else { return 0 }
        return Double(crossings.count - 1) / 2 / ((crossings.last! - crossings.first!) / sr)
    }

    /// Seconds until the envelope stays below `db` relative to the peak.
    static func decayTime(_ x: [Float], _ sr: Double, db: Double = -60) -> Double {
        let p = Double(peak(x))
        let thr = p * pow(10, db / 20)
        var last = 0
        for i in x.indices where Double(abs(x[i])) > thr { last = i }
        return Double(last) / sr
    }

    /// Energy that isn't near a harmonic of f0, relative to the total, in dB. Measures aliasing.
    static func inharmonicDb(_ x: [Float], _ sr: Double, f0: Double, start: Int = 0, length: Int = 32768) -> Double {
        let spec = powerSpectrum(x, start: start, length: length)
        let hz = binHz(spec, sr)
        var harm = 0.0, other = 0.0
        for (i, p) in spec.enumerated() {
            let f = Double(i) * hz
            if f < 20 { continue }
            let k = (f / f0).rounded()
            if k >= 1 && abs(f - k * f0) <= 6 * hz { harm += p } else { other += p }
        }
        return 10 * log10(max(other, 1e-30) / max(harm + other, 1e-30))
    }
}

extension Synth {
    /// Render one note for testing: held for `hold` seconds, then released for `tail` seconds.
    static func renderNote(_ params: [String: Double], note: Int, velocity: Float = 0.8, hold: Double, tail: Double = 0,
                           sampleRate sr: Double = 48000) -> (l: [Float], r: [Float]) {
        let s = Synth(sampleRate: sr)
        let p = SynthParams.defs.resolve(params)
        let total = Int((hold + tail) * sr)
        var outL = [Float](repeating: 0, count: total), outR = [Float](repeating: 0, count: total)
        let block = 512
        let l = UnsafeMutablePointer<Float>.allocate(capacity: block); defer { l.deallocate() }
        let r = UnsafeMutablePointer<Float>.allocate(capacity: block); defer { r.deallocate() }
        s.noteOn(note, velocity: velocity, params: p)
        var f = 0
        let off = Int(hold * sr)
        while f < total {
            let n = min(block, total - f, f < off ? off - f : block)
            l.initialize(repeating: 0, count: n); r.initialize(repeating: 0, count: n)
            s.render(l, r, frames: n, params: p)
            for i in 0..<n { outL[f + i] = l[i]; outR[f + i] = r[i] }
            f += n
            if f == off { s.noteOff(note, params: p) }
        }
        return (outL, outR)
    }
}
