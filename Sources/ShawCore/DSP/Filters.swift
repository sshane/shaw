import Foundation

/// RBJ cookbook biquad, transposed direct form II.
public struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    public init() {}

    public enum Kind { case lowpass, highpass, bandpass, notch, peak, lowShelf, highShelf }

    public mutating func set(_ kind: Kind, freq: Double, q: Double, gainDb: Double = 0, sampleRate: Double) {
        let f = min(max(freq, 10), sampleRate * 0.49)
        let w0 = 2 * Double.pi * f / sampleRate
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * max(q, 0.05))
        let A = pow(10, gainDb / 40)
        var nb0 = 1.0, nb1 = 0.0, nb2 = 0.0, na0 = 1.0, na1 = 0.0, na2 = 0.0
        switch kind {
        case .lowpass:
            nb0 = (1 - cw) / 2; nb1 = 1 - cw; nb2 = (1 - cw) / 2
            na0 = 1 + alpha; na1 = -2 * cw; na2 = 1 - alpha
        case .highpass:
            nb0 = (1 + cw) / 2; nb1 = -(1 + cw); nb2 = (1 + cw) / 2
            na0 = 1 + alpha; na1 = -2 * cw; na2 = 1 - alpha
        case .bandpass:
            nb0 = alpha; nb1 = 0; nb2 = -alpha
            na0 = 1 + alpha; na1 = -2 * cw; na2 = 1 - alpha
        case .notch:
            nb0 = 1; nb1 = -2 * cw; nb2 = 1
            na0 = 1 + alpha; na1 = -2 * cw; na2 = 1 - alpha
        case .peak:
            nb0 = 1 + alpha * A; nb1 = -2 * cw; nb2 = 1 - alpha * A
            na0 = 1 + alpha / A; na1 = -2 * cw; na2 = 1 - alpha / A
        case .lowShelf:
            let s = 2 * sqrt(A) * alpha
            nb0 = A * ((A + 1) - (A - 1) * cw + s)
            nb1 = 2 * A * ((A - 1) - (A + 1) * cw)
            nb2 = A * ((A + 1) - (A - 1) * cw - s)
            na0 = (A + 1) + (A - 1) * cw + s
            na1 = -2 * ((A - 1) + (A + 1) * cw)
            na2 = (A + 1) + (A - 1) * cw - s
        case .highShelf:
            let s = 2 * sqrt(A) * alpha
            nb0 = A * ((A + 1) + (A - 1) * cw + s)
            nb1 = -2 * A * ((A - 1) + (A + 1) * cw)
            nb2 = A * ((A + 1) + (A - 1) * cw - s)
            na0 = (A + 1) - (A - 1) * cw + s
            na1 = 2 * ((A - 1) - (A + 1) * cw)
            na2 = (A + 1) - (A - 1) * cw - s
        }
        b0 = Float(nb0 / na0); b1 = Float(nb1 / na0); b2 = Float(nb2 / na0)
        a1 = Float(na1 / na0); a2 = Float(na2 / na0)
    }

    @inline(__always) public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    public mutating func reset() { z1 = 0; z2 = 0 }
}

/// Zero-delay-feedback state variable filter (Simper). Stable under fast modulation,
/// which makes it the right choice for synth filters and auto-filter sweeps.
public struct SVF {
    var ic1: Float = 0, ic2: Float = 0
    var g: Float = 0, k: Float = 1, a1: Float = 0, a2: Float = 0, a3: Float = 0

    public init() {}

    @inline(__always) public mutating func set(cutoff: Float, resonance: Float, sampleRate: Float) {
        let fc = min(max(cutoff, 15), sampleRate * 0.47)
        g = tanf(Float.pi * fc / sampleRate)
        // Q tops out near 20: screaming, but not a 50x spike when an LFO sweeps through.
        k = 2 - 1.95 * min(max(resonance, 0), 1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    @inline(__always) mutating func copyCoefficients(_ o: SVF) {
        g = o.g; k = o.k; a1 = o.a1; a2 = o.a2; a3 = o.a3
    }

    /// Returns (low, band, high).
    @inline(__always) public mutating func process(_ v0: Float) -> (Float, Float, Float) {
        let v3 = v0 - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, v1, v0 - k * v1 - v2)
    }

    public mutating func reset() { ic1 = 0; ic2 = 0 }
}

public struct OnePole {
    var a: Float = 0
    var z: Float = 0
    public init() {}

    public mutating func setLowpass(_ freq: Double, sampleRate: Double) {
        a = Float(exp(-2 * Double.pi * min(freq, sampleRate * 0.49) / sampleRate))
    }

    @inline(__always) public mutating func lowpass(_ x: Float) -> Float {
        z = x * (1 - a) + z * a
        return z
    }

    public mutating func reset() { z = 0 }
}

/// Linear parameter smoother to avoid zipper noise.
public struct Smoother {
    public var value: Float
    var target: Float
    var step: Float = 0
    var remaining = 0

    public init(_ v: Float = 0) { value = v; target = v }

    @inline(__always) public mutating func set(_ t: Float, frames: Int = 256) {
        if t == target { return }
        target = t
        remaining = frames
        step = (t - value) / Float(frames)
    }

    @inline(__always) public mutating func next() -> Float {
        if remaining > 0 {
            value += step
            remaining -= 1
            if remaining == 0 { value = target }
        }
        return value
    }

    public mutating func snap(_ t: Float) { value = t; target = t; remaining = 0 }
}

/// Circular delay line with fractional read.
public final class DelayLine {
    let buf: UnsafeMutablePointer<Float>
    let size: Int
    var w = 0

    public init(maxSamples: Int) {
        size = max(4, maxSamples + 2)
        buf = .allocate(capacity: size)
        buf.initialize(repeating: 0, count: size)
    }

    deinit { buf.deallocate() }

    @inline(__always) public func write(_ x: Float) {
        buf[w] = x
        w += 1
        if w >= size { w = 0 }
    }

    /// Read `delay` samples behind the most recent write.
    @inline(__always) public func read(_ delay: Float) -> Float {
        let d = min(max(delay, 1), Float(size - 2))
        var rp = Float(w) - d
        if rp < 0 { rp += Float(size) }
        let i0 = Int(rp)
        let frac = rp - Float(i0)
        let i1 = i0 + 1 >= size ? 0 : i0 + 1
        return buf[i0] + (buf[i1] - buf[i0]) * frac
    }

    @inline(__always) public func read(int d: Int) -> Float {
        var i = w - d
        if i < 0 { i += size }
        return buf[i]
    }

    public func reset() { buf.update(repeating: 0, count: size) }
}
