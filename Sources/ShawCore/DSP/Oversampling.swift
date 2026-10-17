import Foundation

/// Coefficients for polyphase IIR half-band filters: two chains of first-order allpasses whose
/// average is an elliptic lowpass at a quarter of the (higher) sample rate. This is the
/// Valenzuela and Constantinides design, as used by Laurent de Soras' HIIR library. The
/// passband is flat to within a millionth of a dB, the transition is steep, and the delay is only
/// a few samples, so oversampling adds no noticeable latency.
enum HalfbandDesign {
    /// - Parameters:
    ///   - count: number of allpass coefficients (even: half go in each chain).
    ///   - transition: transition bandwidth relative to the higher sample rate. The passband
    ///     ends at `0.25 - transition / 2` and the stopband starts at `0.25 + transition / 2`.
    static func coefficients(count: Int, transition: Double) -> [Float] {
        var k = tan((1 - transition * 2) * .pi / 4)
        k *= k
        let kksqrt = pow(1 - k * k, 0.25)
        let e = 0.5 * (1 - kksqrt) / (1 + kksqrt)
        let e2 = e * e, e4 = e2 * e2
        let q = e * (1 + e4 * (2 + e4 * (15 + 150 * e4)))
        let order = Double(count * 2 + 1)
        return (0..<count).map { index in
            let c = Double(index + 1)
            var num = 0.0, sign = 1.0
            for i in 0..<64 {
                let t = pow(q, Double(i * (i + 1))) * sin(Double(i * 2 + 1) * c * .pi / order) * sign
                num += t
                sign = -sign
                if abs(t) < 1e-100 { break }
            }
            num *= pow(q, 0.25)
            var den = 0.5
            sign = -1
            for i in 1..<64 {
                let t = pow(q, Double(i * i)) * cos(Double(i) * 2 * c * .pi / order) * sign
                den += t
                sign = -sign
                if abs(t) < 1e-100 { break }
            }
            let ww = num / den, wwsq = ww * ww
            let x = sqrt((1 - wwsq * k) * (1 - wwsq / k)) / (1 + wwsq)
            return Float((1 - x) / (1 + x))
        }
    }
}

/// One 2x half-band stage for a stereo signal (SIMD lanes are left and right), with separate
/// state for upsampling and downsampling. Upsampling then downsampling through the same stage
/// is an exact allpass: flat magnitude, a few samples of delay.
final class Halfband2x {
    let n: Int
    let coef: UnsafeMutablePointer<Float>
    let ux: UnsafeMutablePointer<SIMD2<Float>>, uy: UnsafeMutablePointer<SIMD2<Float>>
    let dx: UnsafeMutablePointer<SIMD2<Float>>, dy: UnsafeMutablePointer<SIMD2<Float>>

    init(coefficients c: [Float]) {
        precondition(c.count >= 2 && c.count % 2 == 0)
        n = c.count
        coef = .allocate(capacity: n)
        coef.initialize(from: c, count: n)
        ux = .allocate(capacity: n); uy = .allocate(capacity: n)
        dx = .allocate(capacity: n); dy = .allocate(capacity: n)
        for p in [ux, uy, dx, dy] { p.initialize(repeating: .zero, count: n) }
    }

    deinit {
        coef.deallocate()
        ux.deallocate(); uy.deallocate(); dx.deallocate(); dy.deallocate()
    }

    /// One input sample in, two output samples out (in time order) at twice the rate.
    @inline(__always) func up(_ input: SIMD2<Float>) -> (SIMD2<Float>, SIMD2<Float>) {
        var even = input, odd = input
        var i = 0
        while i < n {
            let t0 = (even - uy[i]) * coef[i] + ux[i]
            ux[i] = even; uy[i] = t0; even = t0
            let t1 = (odd - uy[i + 1]) * coef[i + 1] + ux[i + 1]
            ux[i + 1] = odd; uy[i + 1] = t1; odd = t1
            i += 2
        }
        return (even, odd)
    }

    /// Two input samples in (in time order), one output sample out at half the rate.
    @inline(__always) func down(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float> {
        var s0 = b, s1 = a
        var i = 0
        while i < n {
            let t0 = (s0 - dy[i]) * coef[i] + dx[i]
            dx[i] = s0; dy[i] = t0; s0 = t0
            let t1 = (s1 - dy[i + 1]) * coef[i + 1] + dx[i + 1]
            dx[i + 1] = s1; dy[i + 1] = t1; s1 = t1
            i += 2
        }
        return (s0 + s1) * 0.5
    }

    func reset() {
        // Spelled out: reset can run on the audio thread, where an array literal would allocate.
        ux.update(repeating: .zero, count: n); uy.update(repeating: .zero, count: n)
        dx.update(repeating: .zero, count: n); dy.update(repeating: .zero, count: n)
    }
}

/// Fractional-delay taps for estimating inter-sample (true) peaks: Kaiser-windowed sinc
/// interpolators at `phases - 1` evenly spaced positions between two samples.
enum TruePeakTaps {
    static func bessel0(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0, k = 1.0
        while term > 1e-12 * sum {
            term *= (x / (2 * k)) * (x / (2 * k))
            sum += term
            k += 1
        }
        return sum
    }

    /// Taps for phase k (1..<phases): convolving x with them gives about x(n - taps/2 + k/phases).
    static func make(taps: Int, phases: Int, beta: Double = 7) -> [[Float]] {
        let c = taps / 2
        return (1..<phases).map { k in
            let mu = Double(k) / Double(phases)
            let h = (0..<taps).map { j -> Double in
                let t = Double(c - j) - mu
                let s = t == 0 ? 1 : sin(.pi * t) / (.pi * t)
                let r = t / (Double(c) + 0.5)
                let w = abs(r) >= 1 ? 0 : bessel0(beta * (1 - r * r).squareRoot()) / bessel0(beta)
                return s * w
            }
            let sum = h.reduce(0, +)
            return h.map { Float($0 / sum) }
        }
    }
}
