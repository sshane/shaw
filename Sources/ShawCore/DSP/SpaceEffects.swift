import Foundation

// Reverb, Delay, and Chorus. Everything here runs on the audio thread: buffers are
// allocated in `init`, state lives in raw pointers or SIMD values, and the hot loops
// copy what they need into locals so there is no allocation, locking, or ARC traffic.

// MARK: - Shared helpers

/// Third-order (4-point) Lagrange interpolation: the value a fraction `t` of the way
/// from `y0` to `y1`, with `ym1` and `y2` the neighbours on either side. Much flatter
/// than linear interpolation (about -0.5 dB at 10 kHz in the worst case, against -2 dB),
/// so modulated delays stay bright and don't flutter in level as the fraction moves.
@inline(__always) func lagrange4(_ ym1: Float, _ y0: Float, _ y1: Float, _ y2: Float, _ t: Float) -> Float {
    let c1 = y1 - ym1 * (1 / 3) - y0 * 0.5 - y2 * (1 / 6)
    let c2 = 0.5 * (ym1 + y1) - y0
    let c3 = (y2 - ym1) * (1 / 6) + 0.5 * (y0 - y1)
    return ((c3 * t + c2) * t + c1) * t + y0
}

/// Gentle saturation for feedback paths: exactly linear below `knee`, then bends smoothly
/// (matching slope and curvature) toward `ceiling`, so a loop can never run away.
@inline(__always) fileprivate func softLimit(_ x: Float, knee: Float, ceiling: Float) -> Float {
    let ax = abs(x)
    if ax <= knee { return x }
    let r = ceiling - knee
    let y = knee + r * tanhf((ax - knee) / r)
    return x < 0 ? -y : y
}

@inline(__always) fileprivate func nextPowerOfTwo(_ n: Int) -> Int {
    var p = 1
    while p < n { p <<= 1 }
    return p
}

/// Per-chunk one-pole glide toward a target. Used for control values that feed
/// coefficient calculations, so a knob move or keyframe never steps audibly.
struct ControlGlide {
    var value: Float
    var target: Float
    init(_ v: Float) { value = v; target = v }
    /// Advance by one chunk with smoothing factor `k`. Returns true while still moving.
    @inline(__always) mutating func step(_ k: Float) -> Bool {
        if value == target { return false }
        value += (target - value) * k
        if abs(target - value) <= 1e-5 * max(1, abs(target)) { value = target }
        return true
    }
    mutating func snap(_ v: Float) { value = v; target = v }
}

/// Tiny deterministic PRNG for designing delay tables (never used on the audio thread).
struct DesignRandom {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - Four-sample vectors

@inline(__always) func lagrange4(_ ym1: SIMD4<Float>, _ y0: SIMD4<Float>, _ y1: SIMD4<Float>, _ y2: SIMD4<Float>,
                                 _ t: SIMD4<Float>) -> SIMD4<Float> {
    let c1 = y1 - ym1 * (1 / 3) - y0 * 0.5 - y2 * (1 / 6)
    let c2 = 0.5 * (ym1 + y1) - y0
    let c3 = (y2 - ym1) * (1 / 6) + 0.5 * (y0 - y1)
    return ((c3 * t + c2) * t + c1) * t + y0
}

@inline(__always) fileprivate func load4(_ p: UnsafeMutablePointer<Float>) -> SIMD4<Float> {
    UnsafeRawPointer(p).loadUnaligned(as: SIMD4<Float>.self)
}

@inline(__always) fileprivate func store4(_ p: UnsafeMutablePointer<Float>, _ v: SIMD4<Float>) {
    UnsafeMutableRawPointer(p).storeBytes(of: v, as: SIMD4<Float>.self)
}

/// Sixteen channels of one 4-sample block, as named vectors so they live in registers.
/// (Through memory, every Hadamard butterfly level becomes a store-to-load round trip.)
fileprivate struct Lanes16 {
    var x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15: SIMD4<Float>

    @inline(__always) init(_ f: (Int) -> SIMD4<Float>) {
        x0 = f(0); x1 = f(1); x2 = f(2); x3 = f(3)
        x4 = f(4); x5 = f(5); x6 = f(6); x7 = f(7)
        x8 = f(8); x9 = f(9); x10 = f(10); x11 = f(11)
        x12 = f(12); x13 = f(13); x14 = f(14); x15 = f(15)
    }

    @inline(__always) func forEach(_ f: (Int, SIMD4<Float>) -> Void) {
        f(0, x0); f(1, x1); f(2, x2); f(3, x3)
        f(4, x4); f(5, x5); f(6, x6); f(7, x7)
        f(8, x8); f(9, x9); f(10, x10); f(11, x11)
        f(12, x12); f(13, x13); f(14, x14); f(15, x15)
    }

    /// Orthonormal 16-point Walsh-Hadamard transform (Sylvester order): energy-preserving,
    /// and every output hears every input at +-1/4.
    @inline(__always) mutating func hadamard() {
        (x0, x1) = (x0 + x1, x0 - x1)
        (x2, x3) = (x2 + x3, x2 - x3)
        (x4, x5) = (x4 + x5, x4 - x5)
        (x6, x7) = (x6 + x7, x6 - x7)
        (x8, x9) = (x8 + x9, x8 - x9)
        (x10, x11) = (x10 + x11, x10 - x11)
        (x12, x13) = (x12 + x13, x12 - x13)
        (x14, x15) = (x14 + x15, x14 - x15)
        (x0, x2) = (x0 + x2, x0 - x2)
        (x1, x3) = (x1 + x3, x1 - x3)
        (x4, x6) = (x4 + x6, x4 - x6)
        (x5, x7) = (x5 + x7, x5 - x7)
        (x8, x10) = (x8 + x10, x8 - x10)
        (x9, x11) = (x9 + x11, x9 - x11)
        (x12, x14) = (x12 + x14, x12 - x14)
        (x13, x15) = (x13 + x15, x13 - x15)
        (x0, x4) = (x0 + x4, x0 - x4)
        (x1, x5) = (x1 + x5, x1 - x5)
        (x2, x6) = (x2 + x6, x2 - x6)
        (x3, x7) = (x3 + x7, x3 - x7)
        (x8, x12) = (x8 + x12, x8 - x12)
        (x9, x13) = (x9 + x13, x9 - x13)
        (x10, x14) = (x10 + x14, x10 - x14)
        (x11, x15) = (x11 + x15, x11 - x15)
        (x0, x8) = (x0 + x8, x0 - x8)
        (x1, x9) = (x1 + x9, x1 - x9)
        (x2, x10) = (x2 + x10, x2 - x10)
        (x3, x11) = (x3 + x11, x3 - x11)
        (x4, x12) = (x4 + x12, x4 - x12)
        (x5, x13) = (x5 + x13, x5 - x13)
        (x6, x14) = (x6 + x14, x6 - x14)
        (x7, x15) = (x7 + x15, x7 - x15)
        let s: Float = 0.25
        x0 *= s; x1 *= s; x2 *= s; x3 *= s
        x4 *= s; x5 *= s; x6 *= s; x7 *= s
        x8 *= s; x9 *= s; x10 *= s; x11 *= s
        x12 *= s; x13 *= s; x14 *= s; x15 *= s
    }

    @inline(__always) static func + (a: Lanes16, b: Lanes16) -> Lanes16 {
        var r = a
        r.x0 += b.x0; r.x1 += b.x1; r.x2 += b.x2; r.x3 += b.x3
        r.x4 += b.x4; r.x5 += b.x5; r.x6 += b.x6; r.x7 += b.x7
        r.x8 += b.x8; r.x9 += b.x9; r.x10 += b.x10; r.x11 += b.x11
        r.x12 += b.x12; r.x13 += b.x13; r.x14 += b.x14; r.x15 += b.x15
        return r
    }
}

// MARK: - Reverb (diffused 16-line feedback delay network)

/// A 16-channel FDN reverb in the style of Jot and Geraint Luff ("Let's Write a Reverb"):
///
///   stereo in -> pre-delay -> low cut, bandwidth -> 4-stage Hadamard diffuser
///             -> 16 modulated delay lines with per-line damping, mixed by a Hadamard matrix
///
/// The diffuser turns each input sample into thousands of echoes within ~50 ms; its stages
/// also feed the output as the early sound, so the reverb blooms instead of slapping. The
/// feedback network keeps the echo density growing. Each line's damping filter is set from
/// its own length (Jot's method), so all lines lose the same dB per second at every
/// frequency: no line rings on after the others. Slow, independent modulation of every
/// line smears what modal ringing is left.
///
/// The feedback lines are all far longer than 4 samples, and each diffuser stage writes its
/// block before reading it back, so the network runs 4 samples at a time with each vector
/// holding consecutive samples of one line: delay reads and writes are single vector loads
/// and stores, and the mixing matrices are plain vector adds. The wet signal is 4 samples
/// (0.08 ms) late, which is inaudible next to any pre-delay.
final class ReverbFX: EffectProcessor {
    static let params = [
        ParamDef("size", "Size", 0, 1, 0.7, .percent),
        ParamDef("damping", "Damping", 0, 1, 0.5, .percent),
        ParamDef("predelay", "Pre-Delay", 0, 200, 10, .ms),
        ParamDef("lowcut", "Low Cut", 20, 2000, 150, .hz, .log),
        ParamDef("width", "Width", 0, 1, 1, .percent),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.3, .percent),
    ]

    // MARK: Design (the mapping from knobs to sound)

    /// Decay time (RT60, seconds, below the damping range) for Size 0...1: 0.3 s to 8 s.
    /// The curve keeps the common 0.7 to 0.9 range close to the old reverb's decay.
    static func rt60(size: Float) -> Float { 0.3 * powf(80.0 / 3.0, powf(max(0, min(1, size)), 1.5)) }
    /// How long the delay lines are, relative to full size (small rooms are tighter, not just shorter).
    static func lineScale(size: Float) -> Float { 0.35 + 0.65 * max(0, min(1, size)) }
    /// High-frequency (Nyquist) decay time as a fraction of RT60, for Damping 0...1.
    static func hfRatio(damping: Float) -> Float { 0.85 * powf(0.06 / 0.85, max(0, min(1, damping))) }
    /// Input bandwidth: 20 kHz with no damping, 14 kHz at the default, 10 kHz at full.
    static func bandwidth(damping: Float) -> Float { 20000 * powf(0.5, max(0, min(1, damping))) }

    static let lines = 16
    static let stages = 4
    /// Control updates (modulation, decay coefficients) happen every 8 blocks of 4 samples.
    static let chunk = 32
    /// Diffuser stage lengths, ms. Each channel's delay comes from its own slice of the range.
    static let stageMs: [Double] = [4.5, 8.5, 14, 22]
    /// How much of each diffuser stage's output is heard directly, as the early sound.
    static let earlyMix: [Float] = [0, 0.08, 0.22, 0.4]
    /// Level of the mid-line taps, relative to the line outputs.
    static let midMix: Float = 0.6
    /// Wet level, matched to the old Freeverb at the same Dry/Wet on pink noise. The old one
    /// summed its input to mono, so wide sources reached it 3 dB quieter than centered ones;
    /// this sits halfway, about 1.5 dB under the old level for centered and over for wide.
    static let wetGain: Float = 1.39
    /// The new network's level grows a little faster with Size than Freeverb's did; this
    /// tilt (about +1 dB at Size 0, -0.7 dB at Size 1) keeps the match even across the range.
    static func levelTrim(size: Float) -> Float { powf(10, -1.67 * (max(0, min(1, size)) - 0.58) / 20) }
    /// Corrects the small extra loss from interpolation and filters so measured RT60 hits the target.
    static let decayTrim: Float = 1.064

    let sr: Float
    // Feedback network: 16 lines of `fdnLen` samples (plus 8 guard samples mirroring the
    // first 8, so a 7-sample read window never wraps), padded apart so the lines don't
    // share cache sets.
    let fdn: UnsafeMutablePointer<Float>
    let fdnLen: Int, fdnStride: Int
    var fdnW = 0
    // Per line: length at full size, modulation, damping, and the read-delay ramp.
    let baseDelay: UnsafeMutablePointer<Float>
    let modPhase: UnsafeMutablePointer<Float>, modInc: UnsafeMutablePointer<Float>, modDepth: UnsafeMutablePointer<Float>
    /// Per line, the damping one-pole y = b x + a y': (a, b).
    let dampA: UnsafeMutablePointer<Float>, dampB: UnsafeMutablePointer<Float>
    let lpLast: UnsafeMutablePointer<Float>
    let dNow: UnsafeMutablePointer<Float>
    /// Read delay of each line for the 4 samples of the next block, and its change per block.
    let dRamp: UnsafeMutablePointer<SIMD4<Float>>, dRampStep: UnsafeMutablePointer<SIMD4<Float>>
    let tapL: UnsafeMutablePointer<Float>, tapR: UnsafeMutablePointer<Float>
    /// A second output tap partway along each line (fraction of its delay, and stereo weights):
    /// it fills in the gap between the early sound and the first trip round the loop.
    let midFrac: UnsafeMutablePointer<Float>, midL: UnsafeMutablePointer<Float>, midR: UnsafeMutablePointer<Float>
    // Diffuser: 4 stages x 16 lines (4 guard samples each), sharing one write index.
    let diff: UnsafeMutablePointer<Float>
    let diffLen: Int, diffStride: Int
    var diffW = 0
    /// Per stage and output channel: the source line's offset (a random permutation), its
    /// delay, its polarity, and the early-output weights.
    let stageSrc: UnsafeMutablePointer<Int>, stageDelay: UnsafeMutablePointer<Int>
    let stageSign: UnsafeMutablePointer<Float>
    let stageEarlyL: UnsafeMutablePointer<Float>, stageEarlyR: UnsafeMutablePointer<Float>
    let inSign: UnsafeMutablePointer<Float>
    /// Scratch for the interpolated line reads and mid-line taps (16 channels of 4 samples),
    /// plus two more 16x4 buffers for the scalar path.
    let us: UnsafeMutablePointer<SIMD4<Float>>, mids: UnsafeMutablePointer<SIMD4<Float>>
    let xs: UnsafeMutablePointer<Float>, ys: UnsafeMutablePointer<Float>
    /// SIMD kernels in optimized builds; plain scalar loops in debug builds, where Swift's
    /// SIMD types are far too slow. Both compute the same thing (a test compares them).
    #if DEBUG
    var vectorKernels = false
    #else
    var vectorKernels = true
    #endif
    // Input side (per sample) and the 4-sample block hand-off.
    let pre: UnsafeMutablePointer<Float>   // pre-delay, left then right
    let preLen: Int
    var preW = 0
    var hpL = SVF(), hpR = SVF(), bwL = SVF(), bwR = SVF()
    let blockIn: UnsafeMutablePointer<Float>, blockOut: UnsafeMutablePointer<Float>  // 4 left, then 4 right
    var pos = 0, blockCount = 0, controlCount = 0
    /// A -360 dB alternating signal fed into one line so a silent tail never decays into
    /// denormal numbers, which are very slow on Intel Macs.
    let denormal: Float = 1e-18
    /// Wet gain for the current (smoothed) size.
    var gain: Float = 1

    // Smoothed controls.
    var size = ControlGlide(0.7), damp = ControlGlide(0.5)
    var scale: Float = 0.805
    let scaleRate: Float
    var lowCut: Float = 150, bandHz: Float = 14000, preDelay: Float = 0, width: Float = 1, mix: Float = 0.3
    let kControl: Float, kSample: Float, kPre: Float
    var primed = false

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        let n = Self.lines, stages = Self.stages
        let k = sampleRate / 1000
        var rng = DesignRandom(0x5EED_CAFE)
        func floats(_ count: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }

        // Line lengths spread exponentially from 37 to 113 ms at full size, each nudged
        // by a few percent so no two share a common period.
        baseDelay = floats(n); modPhase = floats(n); modInc = floats(n); modDepth = floats(n)
        var maxDelay = 0.0
        for c in 0..<n {
            let ms = 37 * pow(113.0 / 37.0, Double(c) / Double(n - 1)) * (0.97 + 0.06 * rng.next())
            baseDelay[c] = Float(ms * k)
            maxDelay = max(maxDelay, ms * k)
            // Slow, independent drift: 0.2 to 0.9 Hz, 0.2 to 0.4 ms deep (under 4 cents of
            // pitch movement per pass, enough to smear the modes of the tail).
            modInc[c] = Float((0.2 + 0.7 * rng.next()) / sampleRate)
            modPhase[c] = Float(rng.next())
            modDepth[c] = Float((0.2 + 0.2 * rng.next()) * k)
        }
        fdnLen = nextPowerOfTwo(Int(maxDelay + 0.4 * k) + 16)
        fdnStride = fdnLen + 40
        fdn = floats(fdnStride * n)
        lpLast = floats(n)
        dampA = floats(n); dampB = floats(n)
        dNow = floats(n)
        dRamp = .allocate(capacity: n); dRamp.initialize(repeating: SIMD4(), count: n)
        dRampStep = .allocate(capacity: n); dRampStep.initialize(repeating: SIMD4(), count: n)
        tapL = floats(n); tapR = floats(n)
        midFrac = floats(n); midL = floats(n); midR = floats(n)
        // Size glides move the line lengths at most ~1.3 samples per 32, a gentle bend.
        scaleRate = Float(1.3 / maxDelay)

        diffLen = nextPowerOfTwo(Int(Self.stageMs.max()! * k) + 8)
        diffStride = diffLen + 36
        diff = floats(diffStride * n * stages)
        stageSrc = .allocate(capacity: n * stages); stageSrc.initialize(repeating: 0, count: n * stages)
        stageDelay = .allocate(capacity: n * stages); stageDelay.initialize(repeating: 0, count: n * stages)
        stageSign = floats(n * stages); stageEarlyL = floats(n * stages); stageEarlyR = floats(n * stages)
        inSign = floats(n)
        us = .allocate(capacity: n); us.initialize(repeating: SIMD4(), count: n)
        mids = .allocate(capacity: n); mids.initialize(repeating: SIMD4(), count: n)
        xs = floats(4 * n); ys = floats(4 * n)

        // Output patterns: rows of a 16-point Hadamard matrix (+-1/4), mutually orthogonal, so
        // left and right (early and late) are decorrelated but each hears every channel.
        func hadamardSign(_ row: Int, _ c: Int) -> Float { (row & c).nonzeroBitCount % 2 == 0 ? 0.25 : -0.25 }
        for s in 0..<stages {
            var slots = Array(0..<n), perm = Array(0..<n)
            for i in stride(from: n - 1, to: 0, by: -1) { slots.swapAt(i, Int(rng.next() * Double(i + 1))) }
            for i in stride(from: n - 1, to: 0, by: -1) { perm.swapAt(i, Int(rng.next() * Double(i + 1))) }
            for c in 0..<n {
                let ms = Self.stageMs[s] * (Double(slots[c]) + rng.next()) / Double(n)
                stageSrc[s * n + c] = (s * n + perm[c]) * diffStride
                stageDelay[s * n + c] = max(0, Int(ms * k))
                stageSign[s * n + c] = rng.next() < 0.5 ? -1 : 1
                stageEarlyL[s * n + c] = hadamardSign(5 + 2 * s, c) * Self.earlyMix[s]
                stageEarlyR[s * n + c] = hadamardSign(6 + 2 * s, c) * Self.earlyMix[s]
            }
        }
        // Input: left on even channels, right on odd, random polarities, unit energy.
        for c in 0..<n { inSign[c] = (rng.next() < 0.5 ? -1 : 1) / Float(8).squareRoot() }
        for c in 0..<n {
            tapL[c] = hadamardSign(3, c); tapR[c] = hadamardSign(4, c)
            midFrac[c] = Float(0.25 + 0.35 * rng.next())
            midL[c] = hadamardSign(13, c) * Self.midMix; midR[c] = hadamardSign(14, c) * Self.midMix
        }

        preLen = nextPowerOfTwo(Int(0.21 * sampleRate) + 4)
        pre = floats(2 * preLen)
        blockIn = floats(8); blockOut = floats(8)
        kControl = 1 - expf(-Float(Self.chunk) / (0.06 * Float(sampleRate)))
        kSample = 1 - expf(-1 / (0.03 * Float(sampleRate)))
        kPre = 1 - expf(-1 / (0.12 * Float(sampleRate)))
    }

    deinit {
        fdn.deallocate(); baseDelay.deallocate(); modPhase.deallocate(); modInc.deallocate(); modDepth.deallocate()
        dampA.deallocate(); dampB.deallocate(); lpLast.deallocate()
        dNow.deallocate(); dRamp.deallocate(); dRampStep.deallocate(); tapL.deallocate(); tapR.deallocate()
        diff.deallocate(); stageSrc.deallocate(); stageDelay.deallocate(); stageSign.deallocate()
        stageEarlyL.deallocate(); stageEarlyR.deallocate(); inSign.deallocate()
        midFrac.deallocate(); midL.deallocate(); midR.deallocate(); mids.deallocate()
        xs.deallocate(); ys.deallocate()
        us.deallocate(); pre.deallocate(); blockIn.deallocate(); blockOut.deallocate()
    }

    private func updateCoefficients() {
        let rt = Self.rt60(size: size.value) * Self.decayTrim
        gain = Self.wetGain * Self.levelTrim(size: size.value)
        let ratio = Self.hfRatio(damping: damp.value)
        // Jot's absorptive filter per line: gain g at DC and g^(1/ratio) at Nyquist, so
        // every line loses the same dB per second at both ends of the spectrum.
        let perSample = -3 * log2f(10) / (sr * rt)
        for c in 0..<Self.lines {
            let m = baseDelay[c] * scale
            let g = exp2f(perSample * m)
            let gn = exp2f(perSample * m / ratio)
            let a = (g - gn) / (g + gn)
            dampA[c] = a
            dampB[c] = g * (1 - a)
        }
    }

    /// Once per 32 samples: glide size and damping, and lay out the next stretch of each
    /// line's read delay (modulation plus any size change) as a linear ramp.
    private func updateControls() {
        let sizeMoved = size.step(kControl), dampMoved = damp.step(kControl)
        let target = Self.lineScale(size: size.value)
        let rescaled = scale != target
        if rescaled { scale += max(-scaleRate, min(scaleRate, target - scale)) }
        if sizeMoved || dampMoved || rescaled { updateCoefficients() }
        let n = Float(Self.chunk)
        for c in 0..<Self.lines {
            var ph = modPhase[c] + modInc[c] * n
            if ph >= 1 { ph -= 1 }
            modPhase[c] = ph
            let end = baseDelay[c] * scale + modDepth[c] * sinf(2 * .pi * ph)
            let step = (end - dNow[c]) / n
            dRamp[c] = SIMD4(repeating: dNow[c]) + SIMD4(0, 1, 2, 3) * step
            dRampStep[c] = SIMD4(repeating: 4 * step)
            dNow[c] = end
        }
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        size.target = Float(p[0]); damp.target = Float(p[1])
        let preT = (Float(p[2]) * sr / 1000).rounded()
        let lowT = Float(p[3]), widthT = Float(p[4]), mixT = Float(p[5])
        let bandT = min(Self.bandwidth(damping: damp.target), sr * 0.45)
        if !primed {
            primed = true
            size.snap(size.target); damp.snap(damp.target)
            scale = Self.lineScale(size: size.value)
            lowCut = lowT; bandHz = bandT; preDelay = preT; width = widthT; mix = mixT
            hpL.set(cutoff: lowCut, resonance: 0.3, sampleRate: sr); hpR.copyCoefficients(hpL)
            bwL.set(cutoff: bandHz, resonance: 0.3, sampleRate: sr); bwR.copyCoefficients(bwL)
            updateCoefficients()
            for c in 0..<Self.lines { dNow[c] = baseDelay[c] * scale + modDepth[c] * sinf(2 * .pi * modPhase[c]) }
        }

        var hpL = self.hpL, hpR = self.hpR, bwL = self.bwL, bwR = self.bwR
        var lowCut = self.lowCut, bandHz = self.bandHz, preDelay = self.preDelay, width = self.width, mix = self.mix
        var controlCount = self.controlCount, pos = self.pos, preW = self.preW
        let pre = self.pre, preLen = self.preLen, preMask = preLen - 1
        let blockIn = self.blockIn, blockOut = self.blockOut
        let kSample = self.kSample, kPre = self.kPre, kControl = self.kControl
        let sr = self.sr
        let l = buf.l, r = buf.r

        for j in 0..<frames {
            if controlCount == 0, lowCut != lowT || bandHz != bandT {
                // Filter cutoffs glide too, updated every 32 samples.
                lowCut += (lowT - lowCut) * kControl
                bandHz += (bandT - bandHz) * kControl
                if abs(lowT - lowCut) < 0.01 { lowCut = lowT }
                if abs(bandT - bandHz) < 0.5 { bandHz = bandT }
                hpL.set(cutoff: lowCut, resonance: 0.3, sampleRate: sr); hpR.copyCoefficients(hpL)
                bwL.set(cutoff: bandHz, resonance: 0.3, sampleRate: sr); bwR.copyCoefficients(bwL)
            }
            controlCount = (controlCount + 1) & (Self.chunk - 1)
            mix += (mixT - mix) * kSample
            width += (widthT - width) * kSample
            preDelay += (preT - preDelay) * kPre
            if abs(preT - preDelay) < 0.001 { preDelay = preT }

            // Pre-delay (whole samples at rest, linear interpolation only while gliding),
            // then low cut and bandwidth.
            let inL = l[j], inR = r[j]
            pre[preW] = inL; pre[preLen + preW] = inR
            var xl = inL, xr = inR
            if preDelay >= 1 {
                let di = Int(preDelay), t = preDelay - Float(di)
                let i0 = (preW - di) & preMask, i1 = (i0 - 1) & preMask
                xl = pre[i0] + (pre[i1] - pre[i0]) * t
                xr = pre[preLen + i0] + (pre[preLen + i1] - pre[preLen + i0]) * t
            }
            preW = (preW + 1) & preMask
            blockIn[pos] = bwL.process(hpL.process(xl).2).0
            blockIn[4 + pos] = bwR.process(hpR.process(xr).2).0

            let wetL = blockOut[pos], wetR = blockOut[4 + pos]
            let w1 = mix * (width * 0.5 + 0.5), w2 = mix * ((1 - width) * 0.5)
            let dry = 1 - mix * 0.5
            l[j] = inL * dry + wetL * w1 + wetR * w2
            r[j] = inR * dry + wetR * w1 + wetL * w2
            pos += 1
            if pos == 4 { renderBlock(); pos = 0 }
        }

        self.hpL = hpL; self.hpR = hpR; self.bwL = bwL; self.bwR = bwR
        self.lowCut = lowCut; self.bandHz = bandHz; self.preDelay = preDelay; self.width = width; self.mix = mix
        self.controlCount = controlCount; self.pos = pos; self.preW = preW
    }

    /// Run the diffuser and feedback network for the 4 samples in `blockIn`, leaving the wet
    /// output in `blockOut`.
    private func renderBlock() {
        if blockCount == 0 { updateControls() }
        blockCount = (blockCount + 1) & (Self.chunk / 4 - 1)
        if vectorKernels { renderBlockVector() } else { renderBlockScalar() }
    }

    private func renderBlockVector() {
        let inL = load4(blockIn), inR = load4(blockIn + 4)

        // Spread across 16 channels, then diffuse.
        let inSign = self.inSign
        var x = Lanes16 { c in (c & 1 == 0 ? inL : inR) * inSign[c] }
        var earlyL = SIMD4<Float>(), earlyR = SIMD4<Float>()
        diffuse(&x, &earlyL, &earlyR)
        diffW = (diffW + 4) & (diffLen - 1)

        // Feedback network: read every line, damp, tap the output, mix, and write back with
        // the diffused input.
        readLines()
        dampLines()
        var tailL = SIMD4<Float>(), tailR = SIMD4<Float>()
        mixLines(x, &tailL, &tailR)

        let g = gain
        store4(blockOut, (tailL + earlyL) * g)
        store4(blockOut + 4, (tailR + earlyR) * g)
    }

    // The block's kernels stay out of line on purpose. LLVM scalarizes Swift's SIMD4 math when
    // it is inlined into one big function, or when a vector result is later picked apart lane
    // by lane, so each vector pass gets its own function.

    /// The diffuser, stage by stage: write the stage's input, read each channel back at its own
    /// delay (permuted, polarity-flipped), mix with a Hadamard matrix, and tap the early sound.
    @inline(never) private func diffuse(_ x: inout Lanes16, _ earlyL: inout SIMD4<Float>, _ earlyR: inout SIMD4<Float>) {
        let n = Self.lines, diff = self.diff, diffW = self.diffW, diffMask = diffLen - 1
        let diffLen = self.diffLen, stride = self.diffStride
        let stageSrc = self.stageSrc, stageDelay = self.stageDelay, stageSign = self.stageSign
        let stageEarlyL = self.stageEarlyL, stageEarlyR = self.stageEarlyR
        var v = x, eL = earlyL, eR = earlyR
        for s in 0..<Self.stages {
            let row = diff + s * n * stride
            v.forEach { c, value in
                let line = row + c * stride
                store4(line + diffW, value)
                if diffW == 0 { store4(line + diffLen, value) }
            }
            let o = s * n
            v = Lanes16 { c in load4(diff + stageSrc[o + c] + ((diffW - stageDelay[o + c]) & diffMask)) * stageSign[o + c] }
            v.hadamard()
            v.forEach { c, value in eL += value * stageEarlyL[o + c]; eR += value * stageEarlyR[o + c] }
        }
        x = v; earlyL = eL; earlyR = eR
    }

    /// Interpolated reads of every feedback line along its delay ramp, into `us`. (Kept apart
    /// from the damping pass: if LLVM sees lanes of the result picked apart, it computes the
    /// whole interpolation one lane at a time.)
    @inline(never) private func readLines() {
        let us = self.us, fdn = self.fdn, fdnW = self.fdnW, fdnMask = fdnLen - 1, stride = fdnStride
        for c in 0..<Self.lines {
            let d = dRamp[c]
            dRamp[c] = d + dRampStep[c]
            let di = Int(d.x)
            let t = d - SIMD4(repeating: Float(di))
            let line = fdn + c * stride
            let start = line + ((fdnW - di - 2) & fdnMask)
            us[c] = lagrange4(load4(start + 3), load4(start + 2), load4(start + 1), load4(start), t)
            // The mid-line tap only feeds the output, so linear interpolation is plenty.
            let dm = d * midFrac[c]
            let dmi = Int(dm.x)
            let tm = dm - SIMD4(repeating: Float(dmi))
            let mstart = line + ((fdnW - dmi - 1) & fdnMask)
            let m0 = load4(mstart + 1)
            mids[c] = m0 + (load4(mstart) - m0) * tm
        }
    }

    /// Each line's damping one-pole, in place in `us`. A serial recursion, so it is plain
    /// scalar code, kept in its own function so the vector passes around it stay vectorized.
    @inline(never) private func dampLines() {
        let p = UnsafeMutableRawPointer(us).assumingMemoryBound(to: Float.self)
        for c in 0..<Self.lines {
            let a = dampA[c], b = dampB[c], q = p + 4 * c
            var z = lpLast[c]
            z = b * q[0] + a * z; q[0] = z
            z = b * q[1] + a * z; q[1] = z
            z = b * q[2] + a * z; q[2] = z
            z = b * q[3] + a * z; q[3] = z
            lpLast[c] = z
        }
    }

    /// Output taps, the feedback matrix, and write-back of the lines plus the diffused input.
    @inline(never) private func mixLines(_ x: Lanes16, _ tailL: inout SIMD4<Float>, _ tailR: inout SIMD4<Float>) {
        let us = self.us, mids = self.mids, tapL = self.tapL, tapR = self.tapR, midL = self.midL, midR = self.midR
        var y = Lanes16 { c in us[c] }
        var l = SIMD4<Float>(), r = SIMD4<Float>()
        y.forEach { c, v in l += v * tapL[c]; r += v * tapR[c] }
        for c in 0..<Self.lines { let m = mids[c]; l += m * midL[c]; r += m * midR[c] }
        tailL = l; tailR = r
        y.hadamard()
        var fb = y + x
        let dn = denormal
        fb.x0 += SIMD4(dn, -dn, dn, -dn)
        let fdn = self.fdn, fdnW = self.fdnW, fdnLen = self.fdnLen, stride = self.fdnStride
        fb.forEach { c, v in
            let line = fdn + c * stride
            store4(line + fdnW, v)
            if fdnW < 8 { store4(line + fdnLen + fdnW, v) }
        }
        self.fdnW = (fdnW + 4) & (fdnLen - 1)
    }

    // MARK: Scalar path (debug builds)

    /// The same network as the vector path, in plain scalar loops over the same memory.
    /// Unoptimized builds run Swift's SIMD types as generic calls, roughly 200 times slower
    /// than optimized code, which made debug test runs crawl; plain scalar code costs about
    /// what the old reverb did there. Release builds use the vector path, and a test checks
    /// that the two agree. (While loops, because unoptimized ranges are slow too.)
    private func renderBlockScalar() {
        let n = Self.lines, xs = self.xs, ys = self.ys, out = self.blockOut
        let us = UnsafeMutableRawPointer(self.us).assumingMemoryBound(to: Float.self)
        let ms = UnsafeMutableRawPointer(self.mids).assumingMemoryBound(to: Float.self)
        let ramp = UnsafeMutableRawPointer(dRamp).assumingMemoryBound(to: Float.self)
        let rampStep = UnsafeMutableRawPointer(dRampStep).assumingMemoryBound(to: Float.self)
        var c = 0, k = 0
        while k < 8 { out[k] = 0; k += 1 }

        // Spread across 16 channels, then diffuse; the early taps accumulate in `out`.
        c = 0
        while c < n {
            let src = blockIn + (c & 1 == 0 ? 0 : 4), sign = inSign[c]
            k = 0
            while k < 4 { xs[4 * c + k] = src[k] * sign; k += 1 }
            c += 1
        }
        let diffW = self.diffW, diffMask = diffLen - 1, dStride = diffStride
        var s = 0
        while s < Self.stages {
            let row = diff + s * n * dStride, o = s * n
            c = 0
            while c < n {
                let line = row + c * dStride
                k = 0
                while k < 4 {
                    line[diffW + k] = xs[4 * c + k]
                    if diffW == 0 { line[diffLen + k] = xs[4 * c + k] }
                    k += 1
                }
                c += 1
            }
            c = 0
            while c < n {
                let src = diff + stageSrc[o + c] + ((diffW - stageDelay[o + c]) & diffMask), sign = stageSign[o + c]
                k = 0
                while k < 4 { ys[4 * c + k] = src[k] * sign; k += 1 }
                c += 1
            }
            Self.hadamardScalar(ys)
            c = 0
            while c < n {
                let eL = stageEarlyL[o + c], eR = stageEarlyR[o + c]
                k = 0
                while k < 4 {
                    let v = ys[4 * c + k]
                    xs[4 * c + k] = v
                    out[k] += v * eL; out[4 + k] += v * eR
                    k += 1
                }
                c += 1
            }
            s += 1
        }
        self.diffW = (diffW + 4) & diffMask

        // Feedback lines: interpolated reads and mid-line taps.
        let fdn = self.fdn, fdnW = self.fdnW, fdnMask = fdnLen - 1, fStride = fdnStride
        let third: Float = 1 / 3, sixth: Float = 1 / 6, half: Float = 0.5
        c = 0
        while c < n {
            let line = fdn + c * fStride, frac = midFrac[c]
            let di = Int(ramp[4 * c]), dmi = Int(ramp[4 * c] * frac)
            let fdi = Float(di), fdmi = Float(dmi)
            let start = line + ((fdnW - di - 2) & fdnMask), mstart = line + ((fdnW - dmi - 1) & fdnMask)
            k = 0
            while k < 4 {
                let d = ramp[4 * c + k]
                ramp[4 * c + k] = d + rampStep[4 * c + k]
                // lagrange4, written out: calls are expensive in unoptimized builds.
                let ym1 = start[k + 3], y0 = start[k + 2], y1 = start[k + 1], y2 = start[k], t = d - fdi
                let c1 = y1 - ym1 * third - y0 * half - y2 * sixth
                let c2 = half * (ym1 + y1) - y0
                let c3 = (y2 - ym1) * sixth + half * (y0 - y1)
                us[4 * c + k] = ((c3 * t + c2) * t + c1) * t + y0
                let m0 = mstart[k + 1]
                ms[4 * c + k] = m0 + (mstart[k] - m0) * (d * frac - fdmi)
                k += 1
            }
            c += 1
        }
        dampLines()

        // Output taps, the feedback matrix, and write-back.
        c = 0
        while c < n {
            let tl = tapL[c], tr = tapR[c], ml = midL[c], mr = midR[c]
            k = 0
            while k < 4 {
                let v = us[4 * c + k], m = ms[4 * c + k]
                out[k] += v * tl + m * ml; out[4 + k] += v * tr + m * mr
                k += 1
            }
            c += 1
        }
        Self.hadamardScalar(us)
        let dn = denormal
        c = 0
        while c < n {
            let line = fdn + c * fStride
            k = 0
            while k < 4 {
                var v = us[4 * c + k] + xs[4 * c + k]
                if c == 0 { v += k & 1 == 0 ? dn : -dn }
                line[fdnW + k] = v
                if fdnW < 8 { line[fdnLen + fdnW + k] = v }
                k += 1
            }
            c += 1
        }
        self.fdnW = (fdnW + 4) & fdnMask
        let g = gain
        k = 0
        while k < 8 { out[k] *= g; k += 1 }
    }

    /// Orthonormal 16-point Hadamard over 16 channels of 4 samples (channel-major), in place:
    /// one unrolled transform on locals per sample, which unoptimized builds run far faster
    /// than index arithmetic in loops.
    private static func hadamardScalar(_ p: UnsafeMutablePointer<Float>) {
        var k = 0
        while k < 4 {
            let q = p + k
            var x0 = q[0]; var x1 = q[4]; var x2 = q[8]; var x3 = q[12]
            var x4 = q[16]; var x5 = q[20]; var x6 = q[24]; var x7 = q[28]
            var x8 = q[32]; var x9 = q[36]; var x10 = q[40]; var x11 = q[44]
            var x12 = q[48]; var x13 = q[52]; var x14 = q[56]; var x15 = q[60]
            (x0, x1) = (x0 + x1, x0 - x1)
            (x2, x3) = (x2 + x3, x2 - x3)
            (x4, x5) = (x4 + x5, x4 - x5)
            (x6, x7) = (x6 + x7, x6 - x7)
            (x8, x9) = (x8 + x9, x8 - x9)
            (x10, x11) = (x10 + x11, x10 - x11)
            (x12, x13) = (x12 + x13, x12 - x13)
            (x14, x15) = (x14 + x15, x14 - x15)
            (x0, x2) = (x0 + x2, x0 - x2)
            (x1, x3) = (x1 + x3, x1 - x3)
            (x4, x6) = (x4 + x6, x4 - x6)
            (x5, x7) = (x5 + x7, x5 - x7)
            (x8, x10) = (x8 + x10, x8 - x10)
            (x9, x11) = (x9 + x11, x9 - x11)
            (x12, x14) = (x12 + x14, x12 - x14)
            (x13, x15) = (x13 + x15, x13 - x15)
            (x0, x4) = (x0 + x4, x0 - x4)
            (x1, x5) = (x1 + x5, x1 - x5)
            (x2, x6) = (x2 + x6, x2 - x6)
            (x3, x7) = (x3 + x7, x3 - x7)
            (x8, x12) = (x8 + x12, x8 - x12)
            (x9, x13) = (x9 + x13, x9 - x13)
            (x10, x14) = (x10 + x14, x10 - x14)
            (x11, x15) = (x11 + x15, x11 - x15)
            (x0, x8) = (x0 + x8, x0 - x8)
            (x1, x9) = (x1 + x9, x1 - x9)
            (x2, x10) = (x2 + x10, x2 - x10)
            (x3, x11) = (x3 + x11, x3 - x11)
            (x4, x12) = (x4 + x12, x4 - x12)
            (x5, x13) = (x5 + x13, x5 - x13)
            (x6, x14) = (x6 + x14, x6 - x14)
            (x7, x15) = (x7 + x15, x7 - x15)
            q[0] = x0 * 0.25; q[4] = x1 * 0.25; q[8] = x2 * 0.25; q[12] = x3 * 0.25
            q[16] = x4 * 0.25; q[20] = x5 * 0.25; q[24] = x6 * 0.25; q[28] = x7 * 0.25
            q[32] = x8 * 0.25; q[36] = x9 * 0.25; q[40] = x10 * 0.25; q[44] = x11 * 0.25
            q[48] = x12 * 0.25; q[52] = x13 * 0.25; q[56] = x14 * 0.25; q[60] = x15 * 0.25
            k += 1
        }
    }

    func reset() {
        fdn.update(repeating: 0, count: fdnStride * Self.lines)
        diff.update(repeating: 0, count: diffStride * Self.lines * Self.stages)
        pre.update(repeating: 0, count: 2 * preLen)
        lpLast.update(repeating: 0, count: Self.lines)
        blockIn.update(repeating: 0, count: 8); blockOut.update(repeating: 0, count: 8)
        hpL.reset(); hpR.reset(); bwL.reset(); bwR.reset()
    }
}

// MARK: - Delay

/// Tempo-synced stereo echo. Repeats run through the Low Cut and High Cut on every
/// pass, so they thin out and darken like tape or analog delays, and the feedback path
/// saturates gently so even 95% feedback on a resonant note levels off instead of
/// climbing. Delay times are whole samples (no interpolation dulling the repeats), and
/// a change of time or tempo crossfades to the new time rather than jumping or chirping.
final class DelayFX: EffectProcessor {
    static let params = [
        ParamDef.choice("time", "Time", SyncDivision.names, 6),
        ParamDef("feedback", "Feedback", 0, 0.95, 0.4, .percent),
        ParamDef.choice("pingpong", "Ping-Pong", ["Off", "On"], 1),
        ParamDef("lowcut", "Low Cut", 20, 2000, 150, .hz, .log),
        ParamDef("highcut", "High Cut", 500, 20000, 7000, .hz, .log),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.3, .percent),
    ]

    static let chunk = 32
    let sr: Float
    let bufL: UnsafeMutablePointer<Float>, bufR: UnsafeMutablePointer<Float>
    let len: Int, mask: Int
    var w = 0
    /// Current delay in samples, the one being faded to (0 when not fading), and the
    /// newest target that arrived mid-fade.
    var current = 0, next = 0, queued = 0
    var fade: Float = 0
    let fadeStep: Float
    var hpL = SVF(), hpR = SVF(), lpL = SVF(), lpR = SVF()
    var lowCut = ControlGlide(150), highCut = ControlGlide(7000)
    var feedback = ControlGlide(0.4), mix = ControlGlide(0.3)
    var primed = false

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        len = nextPowerOfTwo(Int(sampleRate * 5) + 4)
        mask = len - 1
        bufL = .allocate(capacity: len); bufL.initialize(repeating: 0, count: len)
        bufR = .allocate(capacity: len); bufR.initialize(repeating: 0, count: len)
        fadeStep = Float(1 / (0.05 * sampleRate)) // 50 ms crossfade
    }

    deinit { bufL.deallocate(); bufR.deallocate() }

    /// Butterworth (Q 0.707) low cut and high cut for both sides.
    @inline(__always) private static func tune(_ hpL: inout SVF, _ hpR: inout SVF, _ lpL: inout SVF, _ lpR: inout SVF,
                                               low: Float, high: Float, sr: Float) {
        hpL.set(cutoff: low, resonance: 0.3, sampleRate: sr); hpR.copyCoefficients(hpL)
        lpL.set(cutoff: min(high, sr * 0.45), resonance: 0.3, sampleRate: sr); lpR.copyCoefficients(lpL)
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let div = SyncDivision.beats[max(0, min(SyncDivision.beats.count - 1, Int(p[0])))]
        let target = max(1, Int((min(div * 60 / ctx.bpm, 4.9) * Double(sr)).rounded()))
        lowCut.target = Float(p[3]); highCut.target = Float(p[4])
        feedback.target = Float(p[1]); mix.target = Float(p[5])
        let ping = p[2] > 0.5
        if !primed {
            primed = true
            current = target
            lowCut.snap(lowCut.target); highCut.snap(highCut.target)
            feedback.snap(feedback.target); mix.snap(mix.target)
            Self.tune(&hpL, &hpR, &lpL, &lpR, low: lowCut.value, high: highCut.value, sr: sr)
        } else if next == 0 {
            if target != current { next = target; fade = 0 }
        } else {
            queued = target == next ? 0 : target
        }

        let bufL = self.bufL, bufR = self.bufR, mask = self.mask, fadeStep = self.fadeStep
        var w = self.w, current = self.current, next = self.next, queued = self.queued, fade = self.fade
        var hpL = self.hpL, hpR = self.hpR, lpL = self.lpL, lpR = self.lpR
        var start = 0
        while start < frames {
            let n = min(Self.chunk, frames - start)
            let k = 1 - expf(-Float(n) / (0.03 * sr))
            let lowMoved = lowCut.step(k), highMoved = highCut.step(k)
            if lowMoved || highMoved {
                Self.tune(&hpL, &hpR, &lpL, &lpR, low: lowCut.value, high: highCut.value, sr: sr)
            }
            let fb0 = feedback.value, mix0 = mix.value
            _ = feedback.step(k); _ = mix.step(k)
            let inv = 1 / Float(n)
            let fbStep = (feedback.value - fb0) * inv, mixStep = (mix.value - mix0) * inv
            let l = buf.l + start, r = buf.r + start
            for j in 0..<n {
                let jf = Float(j)
                let fb = fb0 + fbStep * jf, m = mix0 + mixStep * jf
                var wl = bufL[(w - current) & mask], wr = bufR[(w - current) & mask]
                if next != 0 {
                    let g = fade * fade * (3 - 2 * fade)
                    wl += (bufL[(w - next) & mask] - wl) * g
                    wr += (bufR[(w - next) & mask] - wr) * g
                    fade += fadeStep
                    if fade >= 1 {
                        current = next; next = queued; queued = 0; fade = 0
                    }
                }
                wl = lpL.process(hpL.process(wl).2).0
                wr = lpR.process(hpR.process(wr).2).0
                let fl = softLimit(wl * fb, knee: 0.6, ceiling: 1.1)
                let fr = softLimit(wr * fb, knee: 0.6, ceiling: 1.1)
                let inL = l[j], inR = r[j]
                if ping {
                    // Mono input enters the left line; each repeat crosses sides.
                    bufL[w] = (inL + inR) * 0.5 + fr
                    bufR[w] = fl
                } else {
                    bufL[w] = inL + fl
                    bufR[w] = inR + fr
                }
                w = (w + 1) & mask
                l[j] = inL * (1 - m * 0.5) + wl * m
                r[j] = inR * (1 - m * 0.5) + wr * m
            }
            start += n
        }
        self.w = w; self.current = current; self.next = next; self.queued = queued; self.fade = fade
        self.hpL = hpL; self.hpR = hpR; self.lpL = lpL; self.lpR = lpR
    }

    func reset() {
        bufL.update(repeating: 0, count: len); bufR.update(repeating: 0, count: len)
        hpL.reset(); hpR.reset(); lpL.reset(); lpR.reset()
        if next != 0 { current = queued != 0 ? queued : next }
        next = 0; queued = 0; fade = 0
    }
}

// MARK: - Chorus

/// Four-voice stereo chorus. Each side reads its delay line with two taps whose LFOs are
/// a quarter-cycle apart, and the right side runs opposite to the left, so the voices
/// never all move together: the sum is a smooth shimmer instead of a seasick wobble, and
/// it still collapses cleanly to mono. Reads use cubic interpolation, and Delay and Depth
/// glide, so turning a knob or keyframing it never clicks. Short delays with feedback
/// still make a classic flanger, since feedback comes from each side's first voice.
final class ChorusFX: EffectProcessor {
    static let params = [
        ParamDef("rate", "Rate", 0.05, 8, 0.8, .hz, .log),
        ParamDef("depth", "Depth", 0, 1, 0.5, .percent),
        ParamDef("delay", "Delay", 1, 30, 12, .ms),
        ParamDef("feedback", "Feedback", 0, 0.9, 0, .percent),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.5, .percent),
    ]

    static let chunk = 32
    let sr: Float
    let bufL: UnsafeMutablePointer<Float>, bufR: UnsafeMutablePointer<Float>
    let len: Int, mask: Int
    var w = 0
    var phase: Double = 0
    var lastL: Float = 0, lastR: Float = 0
    var base = ControlGlide(576), depth = ControlGlide(0), feedback = ControlGlide(0), mix = ControlGlide(0.5)
    var primed = false

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        len = nextPowerOfTwo(Int(sampleRate * 0.08) + 8)
        mask = len - 1
        bufL = .allocate(capacity: len); bufL.initialize(repeating: 0, count: len)
        bufR = .allocate(capacity: len); bufR.initialize(repeating: 0, count: len)
    }

    deinit { bufL.deallocate(); bufR.deallocate() }

    @inline(__always) private static func read(_ b: UnsafeMutablePointer<Float>, _ d: Float, _ w: Int, _ mask: Int) -> Float {
        let di = Int(d)
        let t = d - Float(di)
        let p0 = (w - di) & mask
        return lagrange4(b[(p0 + 1) & mask], b[p0], b[(p0 - 1) & mask], b[(p0 - 2) & mask], t)
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let baseT = Float(p[2] / 1000) * sr
        base.target = baseT
        depth.target = Float(p[1]) * min(baseT * 0.9, 0.006 * sr)
        feedback.target = Float(p[3]); mix.target = Float(p[4])
        if !primed {
            primed = true
            base.snap(base.target); depth.snap(depth.target); feedback.snap(feedback.target); mix.snap(mix.target)
        }
        let inc = p[0] / Double(sr)
        let bufL = self.bufL, bufR = self.bufR, mask = self.mask
        var w = self.w, lastL = self.lastL, lastR = self.lastR
        var start = 0
        while start < frames {
            let n = min(Self.chunk, frames - start)
            // Delay and depth glide over ~80 ms: a knob move becomes a tiny, smooth pitch bend.
            let k = 1 - expf(-Float(n) / (0.08 * sr))
            let b0 = base.value, d0 = depth.value, fb0 = feedback.value, m0 = mix.value
            _ = base.step(k); _ = depth.step(k); _ = feedback.step(k); _ = mix.step(k)
            let inv = 1 / Float(n)
            let bStep = (base.value - b0) * inv, dStep = (depth.value - d0) * inv
            let fbStep = (feedback.value - fb0) * inv, mStep = (mix.value - m0) * inv
            // LFO sine and cosine at both ends of the chunk; linear in between is exact to ~1e-5.
            let a0 = 2 * Double.pi * phase
            phase += inc * Double(n); phase -= phase.rounded(.down)
            let a1 = 2 * Double.pi * phase
            let s0 = Float(sin(a0)), c0 = Float(cos(a0))
            let sStep = (Float(sin(a1)) - s0) * inv, cStep = (Float(cos(a1)) - c0) * inv
            let l = buf.l + start, r = buf.r + start
            for j in 0..<n {
                let jf = Float(j)
                let bd = b0 + bStep * jf, dp = d0 + dStep * jf
                let s = s0 + sStep * jf, c = c0 + cStep * jf
                let fb = fb0 + fbStep * jf, m = m0 + mStep * jf
                let inL = l[j], inR = r[j]
                bufL[w] = inL + softLimit(lastL * fb, knee: 0.8, ceiling: 1.5)
                bufR[w] = inR + softLimit(lastR * fb, knee: 0.8, ceiling: 1.5)
                let l1 = Self.read(bufL, max(1, bd + dp * s), w, mask)
                let l2 = Self.read(bufL, max(1, bd + dp * c), w, mask)
                let r1 = Self.read(bufR, max(1, bd - dp * s), w, mask)
                let r2 = Self.read(bufR, max(1, bd - dp * c), w, mask)
                w = (w + 1) & mask
                lastL = l1; lastR = r1
                // Two voices add coherently in the bass and as power above it; 0.55 keeps both
                // within about 1 dB of the old single-voice chorus's wet level.
                let wetL = (l1 + l2) * 0.55, wetR = (r1 + r2) * 0.55
                l[j] = inL * (1 - m * 0.5) + wetL * m
                r[j] = inR * (1 - m * 0.5) + wetR * m
            }
            start += n
        }
        self.w = w; self.lastL = lastL; self.lastR = lastR
    }

    func reset() {
        bufL.update(repeating: 0, count: len); bufR.update(repeating: 0, count: len)
        lastL = 0; lastR = 0
    }
}
