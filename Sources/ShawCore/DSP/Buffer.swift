import Accelerate
import Foundation

public let maxBlockFrames = 4096

/// Preallocated stereo scratch buffer. Allocated on the main thread, used on the audio thread.
public final class StereoBuffer {
    public let capacity: Int
    public let l: UnsafeMutablePointer<Float>
    public let r: UnsafeMutablePointer<Float>

    public init(capacity: Int = maxBlockFrames) {
        self.capacity = capacity
        l = .allocate(capacity: capacity)
        r = .allocate(capacity: capacity)
        l.initialize(repeating: 0, count: capacity)
        r.initialize(repeating: 0, count: capacity)
    }

    deinit {
        l.deallocate()
        r.deallocate()
    }

    @inline(__always) public func clear(_ n: Int) {
        vDSP_vclr(l, 1, vDSP_Length(n))
        vDSP_vclr(r, 1, vDSP_Length(n))
    }

    /// out += self * gain
    @inline(__always) public func mix(into outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>,
                                      _ n: Int, gainL: Float, gainR: Float) {
        var gl = gainL, gr = gainR
        vDSP_vsma(l, 1, &gl, outL, 1, outL, 1, vDSP_Length(n))
        vDSP_vsma(r, 1, &gr, outR, 1, outR, 1, vDSP_Length(n))
    }

    @inline(__always) public func mix(into out: StereoBuffer, _ n: Int, gainL: Float = 1, gainR: Float = 1) {
        mix(into: out.l, out.r, n, gainL: gainL, gainR: gainR)
    }

    @inline(__always) public func scale(_ n: Int, _ g: Float) {
        var g = g
        vDSP_vsmul(l, 1, &g, l, 1, vDSP_Length(n))
        vDSP_vsmul(r, 1, &g, r, 1, vDSP_Length(n))
    }

    public func peak(_ n: Int) -> Float {
        var a: Float = 0, b: Float = 0
        vDSP_maxmgv(l, 1, &a, vDSP_Length(n))
        vDSP_maxmgv(r, 1, &b, vDSP_Length(n))
        return max(a, b)
    }
}

public struct RenderContext {
    public var sampleRate: Double
    public var bpm: Double

    public init(sampleRate: Double, bpm: Double) {
        self.sampleRate = sampleRate
        self.bpm = bpm
    }

    @inline(__always) public var beatsPerSample: Double { bpm / 60 / sampleRate }
    @inline(__always) public var samplesPerBeat: Double { sampleRate * 60 / bpm }
}

/// Equal-power pan law. Returns (left, right) gains.
@inline(__always) public func panGains(_ pan: Double) -> (Float, Float) {
    let p = (min(1, max(-1, pan)) + 1) * 0.25 * .pi
    return (Float(cos(p) * 1.41421356), Float(sin(p) * 1.41421356))
}
