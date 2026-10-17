import Accelerate
import Foundation

/// Audio-thread half of an effect: owns DSP state only. Parameter values arrive
/// every block as a dense array in the descriptor's parameter order.
public protocol EffectProcessor: AnyObject {
    func process(_ buf: StereoBuffer, frames: Int, params: [Double], ctx: RenderContext, beat: Double)
    func reset()
}

public struct EffectDescriptor: Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let summary: String
    public let keywords: [String]
    public let params: [ParamDef]
    public let make: (Double) -> EffectProcessor

    public func makeEffect() -> Effect { Effect(kind: id, params: params.defaults()) }

    /// The two or three controls most people reach for; the rest live behind "More".
    public var basicParams: [ParamDef] {
        let ids = EffectRegistry.basic[id] ?? params.prefix(2).map(\.id)
        return ids.compactMap { pid in params.first { $0.id == pid } }
    }

    public var advancedParams: [ParamDef] {
        let basic = Set(basicParams.map(\.id))
        return params.filter { !basic.contains($0.id) }
    }
}

public enum EffectRegistry {
    public static let all: [EffectDescriptor] = [
        EffectDescriptor(id: "reverb", name: "Reverb", category: "Space",
                         summary: "Room and hall ambience",
                         keywords: ["verb", "room", "hall", "space", "ambience", "plate"],
                         params: ReverbFX.params, make: { ReverbFX(sampleRate: $0) }),
        EffectDescriptor(id: "delay", name: "Delay", category: "Space",
                         summary: "Tempo-synced echo with ping-pong",
                         keywords: ["echo", "ping pong", "tape"],
                         params: DelayFX.params, make: { DelayFX(sampleRate: $0) }),
        EffectDescriptor(id: "chorus", name: "Chorus", category: "Modulation",
                         summary: "Widening, flanging, and doubling",
                         keywords: ["flanger", "ensemble", "width", "double"],
                         params: ChorusFX.params, make: { ChorusFX(sampleRate: $0) }),
        EffectDescriptor(id: "phaser", name: "Phaser", category: "Modulation",
                         summary: "Sweeping all-pass notches",
                         keywords: ["phase", "sweep", "swirl"],
                         params: PhaserFX.params, make: { _ in PhaserFX() }),
        EffectDescriptor(id: "autopan", name: "Auto Pan", category: "Modulation",
                         summary: "Tempo-synced panning and tremolo",
                         keywords: ["tremolo", "pan", "lfo", "stereo"],
                         params: AutoPanFX.params, make: { _ in AutoPanFX() }),
        EffectDescriptor(id: "pump", name: "Sidechain Pump", category: "Dynamics",
                         summary: "Tempo-synced ducking, like a kick sidechain",
                         keywords: ["sidechain", "duck", "pump", "kickstart", "lfo tool", "volume shaper"],
                         params: PumpFX.params, make: { _ in PumpFX() }),
        EffectDescriptor(id: "compressor", name: "Compressor", category: "Dynamics",
                         summary: "Control dynamics and add punch",
                         keywords: ["comp", "glue", "dynamics", "squash"],
                         params: CompressorFX.params, make: { CompressorFX(sampleRate: $0) }),
        EffectDescriptor(id: "limiter", name: "Limiter", category: "Dynamics",
                         summary: "Brickwall loudness and peak control",
                         keywords: ["maximizer", "loudness", "master", "clip"],
                         params: LimiterFX.params, make: { LimiterFX(sampleRate: $0) }),
        EffectDescriptor(id: "eq", name: "EQ Three", category: "EQ & Filter",
                         summary: "Low shelf, mid bell, and high shelf",
                         keywords: ["equalizer", "eq", "bass", "treble", "tone"],
                         params: EQ3FX.params, make: { EQ3FX(sampleRate: $0) }),
        EffectDescriptor(id: "filter", name: "Auto Filter", category: "EQ & Filter",
                         summary: "Resonant filter with tempo-synced LFO",
                         keywords: ["lowpass", "highpass", "bandpass", "cutoff", "sweep", "wobble"],
                         params: FilterFX.params, make: { FilterFX(sampleRate: $0) }),
        EffectDescriptor(id: "saturator", name: "Saturator", category: "Distortion",
                         summary: "Warmth, drive, and wavefolding",
                         keywords: ["distortion", "drive", "overdrive", "tube", "warm", "fold", "clip"],
                         params: SaturatorFX.params, make: { SaturatorFX(sampleRate: $0) }),
        EffectDescriptor(id: "bitcrusher", name: "Bitcrusher", category: "Distortion",
                         summary: "Lo-fi bit and sample-rate reduction",
                         keywords: ["redux", "lofi", "lo-fi", "crush", "decimate"],
                         params: BitcrusherFX.params, make: { _ in BitcrusherFX() }),
        EffectDescriptor(id: "volume", name: "Volume", category: "Utility",
                         summary: "Turn it up or down. Keyframe it for fades.",
                         keywords: ["gain", "level", "fade", "loudness", "quiet"],
                         params: VolumeFX.params, make: { _ in VolumeFX() }),
        EffectDescriptor(id: "utility", name: "Utility", category: "Utility",
                         summary: "Gain, pan, stereo width, and mono",
                         keywords: ["gain", "volume", "pan", "width", "mono", "stereo"],
                         params: UtilityFX.params, make: { _ in UtilityFX() }),
    ]

    static let basic: [String: [String]] = [
        "reverb": ["mix", "size"],
        "delay": ["time", "feedback", "mix"],
        "chorus": ["depth", "mix"],
        "phaser": ["rate", "mix"],
        "autopan": ["rate", "amount"],
        "pump": ["rate", "depth"],
        "compressor": ["threshold", "ratio"],
        "limiter": ["gain"],
        "eq": ["lowgain", "midgain", "highgain"],
        "filter": ["type", "cutoff", "resonance"],
        "saturator": ["drive", "mix"],
        "bitcrusher": ["bits", "downsample"],
        "utility": ["gain", "pan", "width"],
        "volume": ["volume"],
    ]

    static let byID: [String: EffectDescriptor] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func descriptor(_ id: String) -> EffectDescriptor? { byID[id] }

    public static func search(_ query: String) -> [EffectDescriptor] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return all }
        return all.filter { d in
            d.name.lowercased().contains(q) || d.category.lowercased().contains(q)
                || d.keywords.contains { $0.contains(q) || q.contains($0) }
        }
    }
}

@inline(__always) private func f(_ p: [Double], _ i: Int) -> Float { Float(p[i]) }

// MARK: - Phaser

final class PhaserFX: EffectProcessor {
    static let params = [
        ParamDef("rate", "Rate", 0.02, 8, 0.4, .hz, .log),
        ParamDef("depth", "Depth", 0, 1, 0.7, .percent),
        ParamDef("center", "Center", 100, 4000, 800, .hz, .log),
        ParamDef("feedback", "Feedback", 0, 0.9, 0.5, .percent),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.5, .percent),
    ]
    var zl = [Float](repeating: 0, count: 6), zr = [Float](repeating: 0, count: 6)
    var phase = 0.0
    var fbL: Float = 0, fbR: Float = 0

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let sr = ctx.sampleRate
        let inc = p[0] / sr
        let fb = f(p, 3), mix = f(p, 4)
        var aL: Float = 0, aR: Float = 0
        for i in 0..<frames {
            if i & 15 == 0 {
                let mL = sin(2 * .pi * phase), mR = sin(2 * .pi * (phase + 0.25))
                let fL = p[2] * pow(4, mL * p[1]), fR = p[2] * pow(4, mR * p[1])
                let tL = tan(.pi * min(fL, sr * 0.45) / sr), tR = tan(.pi * min(fR, sr * 0.45) / sr)
                aL = Float((tL - 1) / (tL + 1)); aR = Float((tR - 1) / (tR + 1))
            }
            phase += inc; if phase >= 1 { phase -= 1 }
            let inL = buf.l[i], inR = buf.r[i]
            var xl = inL + fbL * fb, xr = inR + fbR * fb
            for s in 0..<6 {
                let yl = aL * xl + zl[s]; zl[s] = xl - aL * yl; xl = yl
                let yr = aR * xr + zr[s]; zr[s] = xr - aR * yr; xr = yr
            }
            fbL = xl; fbR = xr
            buf.l[i] = inL * (1 - mix * 0.5) + xl * mix
            buf.r[i] = inR * (1 - mix * 0.5) + xr * mix
        }
    }

    func reset() { zl = zl.map { _ in 0 }; zr = zr.map { _ in 0 }; fbL = 0; fbR = 0 }
}

// MARK: - LFO helpers

public enum LFORates {
    public static let names = ["1/16", "1/8", "1/4", "1/2", "1 bar", "2 bars", "4 bars", "8 bars"]
    public static let beats: [Double] = [0.25, 0.5, 1, 2, 4, 8, 16, 32]
}

// MARK: - Auto Pan / Tremolo

final class AutoPanFX: EffectProcessor {
    static let params = [
        ParamDef.choice("rate", "Rate", LFORates.names, 2),
        ParamDef("amount", "Amount", 0, 1, 0.6, .percent),
        ParamDef.choice("shape", "Shape", ["Sine", "Triangle", "Square"], 0),
        ParamDef.choice("mode", "Mode", ["Pan", "Tremolo"], 0),
    ]

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let period = LFORates.beats[Int(p[0])]
        let amt = f(p, 1), shape = Int(p[2]), trem = p[3] > 0.5
        let bps = ctx.beatsPerSample
        var smooth: Float = 0
        for i in 0..<frames {
            let ph = (beat + Double(i) * bps) / period
            let x = ph - floor(ph)
            var m: Float
            switch shape {
            case 1: m = Float(x < 0.5 ? 4 * x - 1 : 3 - 4 * x)
            case 2: m = x < 0.5 ? 1 : -1
            default: m = Float(sin(2 * .pi * x))
            }
            if shape == 2 { smooth += (m - smooth) * 0.01; m = smooth }
            if trem {
                let g = 1 - amt * (0.5 - 0.5 * m)
                buf.l[i] *= g; buf.r[i] *= g
            } else {
                let pan = (m * amt + 1) * 0.25 * .pi
                buf.l[i] *= cos(pan) * 1.414; buf.r[i] *= sin(pan) * 1.414
            }
        }
    }

    func reset() {}
}

// MARK: - Sidechain pump

final class PumpFX: EffectProcessor {
    static let params = [
        ParamDef.choice("rate", "Rate", LFORates.names, 2),
        ParamDef("depth", "Depth", 0, 1, 0.8, .percent),
        ParamDef("release", "Release", 0.05, 1, 0.55, .percent),
        ParamDef("curve", "Curve", 0.2, 4, 1.6),
    ]
    var g = Smoother(1)

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let period = LFORates.beats[Int(p[0])]
        let depth = p[1], rel = p[2], curve = p[3]
        let bps = ctx.beatsPerSample
        // The duck takes about 4 ms, like a sidechained compressor's attack. Faster than that
        // clicks on held chords and pads every beat.
        let slew = Float(1 - exp(-1 / (0.004 * ctx.sampleRate)))
        for i in 0..<frames {
            let ph = (beat + Double(i) * bps) / period
            let x = ph - floor(ph)
            let r = min(1, x / rel)
            let target = Float(1 - depth * (1 - pow(r, 1 / curve)))
            g.value += (target - g.value) * slew
            buf.l[i] *= g.value; buf.r[i] *= g.value
        }
    }

    func reset() { g.snap(1) }
}

// MARK: - Compressor

final class CompressorFX: EffectProcessor {
    static let params = [
        ParamDef("threshold", "Threshold", -60, 0, -18, .db),
        ParamDef("ratio", "Ratio", 1, 20, 4, .ratio, .log),
        ParamDef("attack", "Attack", 0.1, 100, 10, .ms, .log),
        ParamDef("release", "Release", 10, 1000, 120, .ms, .log),
        ParamDef("makeup", "Makeup", 0, 24, 0, .db),
        ParamDef("mix", "Dry/Wet", 0, 1, 1, .percent),
    ]
    // How it works (feed-forward, stereo-linked, gain smoothed in dB):
    // 1. Detector: the short-term RMS of both channels, or the peak 9 dB down, whichever is
    //    higher. Steady tones and full mixes read as their RMS; sharp hits register at once,
    //    so fast attacks can catch them.
    // 2. A short hold (a running maximum over up to 15 ms) keeps the reading flat between the
    //    peaks of a bass note, so the gain doesn't wobble at the note's frequency.
    // 3. Soft-knee gain computer (6 dB knee), then attack/release smoothing of the gain
    //    reduction itself.
    // Dry/Wet is a plain gain blend (no added delay), so parallel compression stays in phase.
    let sr: Double
    let hold: SlidingMinimum
    var ms: Float = 0
    var gr: Float = 0
    var wet = Smoother(1), dry = Smoother(0)
    var primed = false

    init(sampleRate: Double) {
        sr = sampleRate
        hold = SlidingMinimum(maxWindow: Int(0.015 * sampleRate) + 1)
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let th = f(p, 0), slope = 1 - 1 / max(1, f(p, 1))
        let attack = max(p[2], 0.01) / 1000, release = max(p[3], 1) / 1000
        let aA = Float(exp(-1 / (attack * sr))), aR = Float(exp(-1 / (release * sr)))
        // RMS window follows the attack between 1 and 10 ms: fast settings react fast.
        let rmsCoef = Float(1 - exp(-1 / (min(max(attack, 0.001), 0.01) * sr)))
        let holdFrames = Int(min(0.015, release * 0.25) * sr)
        let knee: Float = 6, halfKnee = knee / 2
        // Below this mean-square level the gain computer is at 0 dB, so skip the logs.
        let quiet = powf(10, (th - halfKnee) / 10)
        let mix = f(p, 5)
        let wetTarget = Float(dbToGain(p[4])) * mix, dryTarget = 1 - mix
        if primed {
            wet.set(wetTarget, frames: max(frames, 1)); dry.set(dryTarget, frames: max(frames, 1))
        } else {
            wet.snap(wetTarget); dry.snap(dryTarget); primed = true
        }
        for i in 0..<frames {
            let l = buf.l[i], r = buf.r[i]
            ms += ((l * l + r * r) * 0.5 - ms) * rmsCoef
            let pk = max(abs(l), abs(r))
            let det = max(ms, pk * pk * 0.125)
            let held = -hold.push(-det, window: holdFrames)
            var target: Float = 0
            if held > quiet {
                let over = 4.3429448 * logf(held) - th
                if over >= halfKnee {
                    target = over * slope
                } else if over > -halfKnee {
                    let k = over + halfKnee
                    target = slope * k * k / (2 * knee)
                }
            }
            gr = target > gr ? target + (gr - target) * aA : target + (gr - target) * aR
            if gr < 1e-6 { gr = 0 }
            let g: Float = gr > 0 ? expf(-gr * 0.11512925) : 1
            let gain = dry.next() + g * wet.next()
            buf.l[i] = l * gain
            buf.r[i] = r * gain
        }
        if !ms.isFinite { ms = 0 }
        if !gr.isFinite { gr = 0 }
    }

    func reset() { ms = 0; gr = 0; hold.reset(); primed = false }
}

// MARK: - Limiter (lookahead true-peak limiter)

final class LimiterFX: EffectProcessor {
    static let params = [
        ParamDef("gain", "Gain", 0, 24, 0, .db),
        ParamDef("ceiling", "Ceiling", -12, 0, -0.3, .db),
        ParamDef("release", "Release", 10, 500, 80, .ms, .log),
    ]
    // How it works (stereo-linked, true-peak aware, never clips):
    // 1. Peaks: each sample, plus three points between samples (a 4x windowed-sinc
    //    interpolator), so the ceiling holds for the analog signal, not only the samples.
    // 2. The gain each sample needs is ceiling / peak. A running minimum over the attack (4 ms)
    //    plus a short hold (up to 10 ms) finds the loudest peak coming up and holds the gain
    //    there, so a steady bass note gets a steady gain instead of one that wobbles at the
    //    note's frequency (that wobble is distortion).
    // 3. Release from two envelopes: a fast one set by Release, and a slow one (the average
    //    gain over 6x the Release time) that follows sustained gain reduction. The lower gain
    //    wins, so dense passages pump less while single hits still recover quickly.
    // 4. A smoothing filter (three stacked moving averages: an S-curve exactly as long as the
    //    attack) fades the gain down before each peak. Every value in its window is at or below
    //    the gain the delayed sample needs, so the output can't overshoot. The clip at the
    //    end only ever catches float rounding.
    static let tpTaps = 48, tpPhases = 4
    static let tpCoefficients = TruePeakTaps.make(taps: tpTaps, phases: tpPhases)
    static let chunk = 256

    let sr: Double
    /// Length of the gain fade before a peak, in samples (4 ms).
    let attack: Int
    /// How far the output lags the input, in samples (about 4.5 ms).
    let latency: Int
    let center = LimiterFX.tpTaps / 2
    let taps: UnsafeMutablePointer<Float>
    let histL: UnsafeMutablePointer<Float>, histR: UnsafeMutablePointer<Float>
    let interp: UnsafeMutablePointer<Float>
    let delayL: UnsafeMutablePointer<Float>, delayR: UnsafeMutablePointer<Float>
    let delaySize: Int
    var dw = 0
    let minimum: SlidingMinimum
    let box1: MovingAverage, box2: MovingAverage, box3: MovingAverage
    var prevPeak: Float = 0
    var fast: Float = 1, slow: Float = 1
    var pre = Smoother(1)
    var primed = false
    /// Output samples the last-resort clip had to pull in by more than 0.001 dB (for tests).
    var safetyClips = 0

    init(sampleRate: Double) {
        sr = sampleRate
        attack = max(8, Int((0.004 * sampleRate).rounded()))
        latency = center + attack - 1
        let t = LimiterFX.tpTaps, phases = LimiterFX.tpPhases - 1, chunk = LimiterFX.chunk
        taps = .allocate(capacity: phases * t)
        for (k, h) in LimiterFX.tpCoefficients.enumerated() {
            // vDSP_conv correlates, so store the taps reversed.
            for j in 0..<t { (taps + k * t + j).initialize(to: h[t - 1 - j]) }
        }
        histL = .allocate(capacity: t - 1 + chunk); histL.initialize(repeating: 0, count: t - 1 + chunk)
        histR = .allocate(capacity: t - 1 + chunk); histR.initialize(repeating: 0, count: t - 1 + chunk)
        interp = .allocate(capacity: 2 * phases * chunk); interp.initialize(repeating: 0, count: 2 * phases * chunk)
        delaySize = attack + 1
        delayL = .allocate(capacity: delaySize); delayL.initialize(repeating: 0, count: delaySize)
        delayR = .allocate(capacity: delaySize); delayR.initialize(repeating: 0, count: delaySize)
        minimum = SlidingMinimum(maxWindow: attack + Int(0.01 * sampleRate) + 1)
        let b = (attack + 2) / 3
        box1 = MovingAverage(length: b, initial: 1)
        box2 = MovingAverage(length: b, initial: 1)
        box3 = MovingAverage(length: attack + 2 - 2 * b, initial: 1)
    }

    deinit {
        taps.deallocate(); histL.deallocate(); histR.deallocate(); interp.deallocate()
        delayL.deallocate(); delayR.deallocate()
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let ceil = Float(dbToGain(p[1]))
        let release = max(p[2], 1) / 1000
        let aFast = Float(exp(-1 / (release * sr)))
        let aSlow = Float(exp(-1 / (min(2, max(0.15, release * 6)) * sr)))
        let window = attack + Int(min(0.01, release * 0.2) * sr)
        let gainTarget = Float(dbToGain(p[0]))
        if primed { pre.set(gainTarget, frames: max(frames, 1)) } else { pre.snap(gainTarget); primed = true }

        let t = LimiterFX.tpTaps, phases = LimiterFX.tpPhases - 1, chunk = LimiterFX.chunk
        let c = center
        var off = 0
        while off < frames {
            let n = min(chunk, frames - off)
            for i in 0..<n {
                let g = pre.next()
                var l = buf.l[off + i] * g, r = buf.r[off + i] * g
                // NaN or inf would poison the gain; silence it instead (this guards the speakers).
                if !(abs(l) < 1e9) { l = 0 }
                if !(abs(r) < 1e9) { r = 0 }
                histL[t - 1 + i] = l
                histR[t - 1 + i] = r
            }
            for k in 0..<phases {
                vDSP_conv(histL, 1, taps + k * t, 1, interp + (2 * k) * chunk, 1, vDSP_Length(n), vDSP_Length(t))
                vDSP_conv(histR, 1, taps + k * t, 1, interp + (2 * k + 1) * chunk, 1, vDSP_Length(n), vDSP_Length(t))
            }
            for i in 0..<n {
                // The interpolator is centered `c` samples back; everything below is for that sample.
                let xl = histL[t - 1 + i - c], xr = histR[t - 1 + i - c]
                var seg = max(abs(xl), abs(xr))
                for j in 0..<(2 * phases) { seg = max(seg, abs(interp[j * chunk + i])) }
                // Count the stretch on both sides of the sample.
                let pk = max(seg, prevPeak)
                prevPeak = seg
                let need: Float = pk > ceil ? ceil / pk : 1
                let held = minimum.push(need, window: window)
                // Both envelopes drop to `held` (fast) or toward it (slow) and recover in gain
                // terms, like an analog release. `fast` never exceeds `held`.
                fast = held <= fast ? held : held + (fast - held) * aFast
                slow = held + (slow - held) * aSlow
                let gain = box3.process(box2.process(box1.process(min(fast, slow))))
                delayL[dw] = xl
                delayR[dw] = xr
                var rd = dw - (attack - 1)
                if rd < 0 { rd += delaySize }
                dw += 1
                if dw == delaySize { dw = 0 }
                var ol = delayL[rd] * gain, or = delayR[rd] * gain
                if abs(ol) > ceil || abs(or) > ceil {
                    if max(abs(ol), abs(or)) > ceil * 1.0001 { safetyClips += 1 }
                    ol = max(-ceil, min(ceil, ol))
                    or = max(-ceil, min(ceil, or))
                }
                buf.l[off + i] = ol
                buf.r[off + i] = or
            }
            // Keep the newest t - 1 inputs as history for the next chunk.
            memmove(histL, histL + n, (t - 1) * MemoryLayout<Float>.stride)
            memmove(histR, histR + n, (t - 1) * MemoryLayout<Float>.stride)
            off += n
        }
    }

    func reset() {
        let t = LimiterFX.tpTaps, chunk = LimiterFX.chunk
        histL.update(repeating: 0, count: t - 1 + chunk)
        histR.update(repeating: 0, count: t - 1 + chunk)
        delayL.update(repeating: 0, count: delaySize)
        delayR.update(repeating: 0, count: delaySize)
        dw = 0
        minimum.reset()
        box1.reset(to: 1); box2.reset(to: 1); box3.reset(to: 1)
        prevPeak = 0; fast = 1; slow = 1
        primed = false
    }
}

// MARK: - EQ Three

final class EQ3FX: EffectProcessor {
    static let params = [
        ParamDef("lowgain", "Low", -24, 12, 0, .db),
        ParamDef("lowfreq", "Low Freq", 30, 1000, 200, .hz, .log),
        ParamDef("midgain", "Mid", -24, 12, 0, .db),
        ParamDef("midfreq", "Mid Freq", 150, 8000, 1000, .hz, .log),
        ParamDef("midq", "Mid Q", 0.3, 8, 1, .none, .log),
        ParamDef("highgain", "High", -24, 12, 0, .db),
        ParamDef("highfreq", "High Freq", 1000, 18000, 5000, .hz, .log),
    ]
    var bands = [Biquad](repeating: Biquad(), count: 6)
    var last: [Double] = []
    let sr: Double
    init(sampleRate: Double) { sr = sampleRate }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        if p != last {
            last = p
            var lo = Biquad(), mid = Biquad(), hi = Biquad()
            lo.set(.lowShelf, freq: p[1], q: 0.707, gainDb: p[0], sampleRate: sr)
            mid.set(.peak, freq: p[3], q: p[4], gainDb: p[2], sampleRate: sr)
            hi.set(.highShelf, freq: p[6], q: 0.707, gainDb: p[5], sampleRate: sr)
            for (i, b) in [lo, lo, mid, mid, hi, hi].enumerated() {
                bands[i].b0 = b.b0; bands[i].b1 = b.b1; bands[i].b2 = b.b2
                bands[i].a1 = b.a1; bands[i].a2 = b.a2
            }
        }
        for i in 0..<frames {
            buf.l[i] = bands[4].process(bands[2].process(bands[0].process(buf.l[i])))
            buf.r[i] = bands[5].process(bands[3].process(bands[1].process(buf.r[i])))
        }
    }

    func reset() { for i in bands.indices { bands[i].reset() } }
}

// MARK: - Auto Filter

final class FilterFX: EffectProcessor {
    static let params = [
        ParamDef.choice("type", "Type", ["Low-pass", "High-pass", "Band-pass", "Notch"], 0),
        ParamDef("cutoff", "Cutoff", 20, 20000, 2000, .hz, .log),
        ParamDef("resonance", "Resonance", 0, 1, 0.25, .percent),
        ParamDef("drive", "Drive", 0, 24, 0, .db),
        ParamDef("lfoamount", "LFO Amount", 0, 1, 0, .percent),
        ParamDef.choice("lforate", "LFO Rate", LFORates.names, 4),
        ParamDef("mix", "Dry/Wet", 0, 1, 1, .percent),
    ]
    var fl = SVF(), fr = SVF()
    var cut = Smoother(2000)
    var primed = false

    init(sampleRate: Double) {}

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let type = Int(p[0])
        let res = f(p, 2)
        let drive = Float(dbToGain(p[3]))
        let lfoAmt = p[4], period = LFORates.beats[Int(p[5])]
        let mix = f(p, 6)
        let sr = Float(ctx.sampleRate)
        let bps = ctx.beatsPerSample
        if primed { cut.set(f(p, 1), frames: 512) } else { cut.snap(f(p, 1)); primed = true }
        for i in 0..<frames {
            let c0 = cut.next()
            if i & 15 == 0 {
                var c = Double(c0)
                if lfoAmt > 0 {
                    let ph = (beat + Double(i) * bps) / period
                    c *= pow(2, sin(2 * .pi * (ph - floor(ph))) * lfoAmt * 4)
                }
                fl.set(cutoff: Float(c), resonance: res, sampleRate: sr)
                fr.g = fl.g; fr.k = fl.k; fr.a1 = fl.a1; fr.a2 = fl.a2; fr.a3 = fl.a3
            }
            let inL = buf.l[i], inR = buf.r[i]
            let xl = drive > 1.001 ? tanhf(inL * drive) : inL
            let xr = drive > 1.001 ? tanhf(inR * drive) : inR
            let (lL, bL, hL) = fl.process(xl)
            let (lR, bR, hR) = fr.process(xr)
            var ol: Float, or: Float
            switch type {
            case 1: ol = hL; or = hR
            case 2: ol = bL; or = bR
            case 3: ol = lL + hL; or = lR + hR
            default: ol = lL; or = lR
            }
            buf.l[i] = inL * (1 - mix) + ol * mix
            buf.r[i] = inR * (1 - mix) + or * mix
        }
    }

    func reset() { fl.reset(); fr.reset() }
}

// MARK: - Saturator

final class SaturatorFX: EffectProcessor {
    static let params = [
        ParamDef("drive", "Drive", 0, 36, 6, .db),
        ParamDef.choice("type", "Type", ["Soft", "Hard", "Tube", "Fold"], 0),
        ParamDef("tone", "Tone", 500, 20000, 14000, .hz, .log),
        ParamDef("output", "Output", -24, 12, 0, .db),
        ParamDef("mix", "Dry/Wet", 0, 1, 1, .percent),
    ]
    // How it works: everything runs at 4x the sample rate (two half-band stages), so the
    // harmonics the curve adds have room above the audible range and get filtered out instead
    // of folding back as inharmonic aliasing. Hard, Tube, and Fold also use first-order
    // antiderivative antialiasing (ADAA), which tames the sharp corners even 4x can't hold.
    // Soft (tanh) is smooth enough that 4x alone is clean. The wet signal is DC-blocked (Tube
    // is asymmetric) and goes through Tone, then Dry/Wet mixes at 4x, so dry and wet pass
    // through the same filters and stay in phase.
    static let stage1 = HalfbandDesign.coefficients(count: 8, transition: 0.05)
    static let stage2 = HalfbandDesign.coefficients(count: 4, transition: 0.275)

    let hb1: Halfband2x, hb2: Halfband2x
    var prev = SIMD2<Float>(0, 0)
    var dcIn = SIMD2<Float>(0, 0), dcOut = SIMD2<Float>(0, 0)
    var lp = SIMD2<Float>(0, 0)
    var toneB: Float = 1
    var lastTone = -1.0
    let dcR: Float
    var drive = Smoother(1), wet = Smoother(1), dry = Smoother(0)
    var primed = false
    let sr: Double

    init(sampleRate: Double) {
        sr = sampleRate
        hb1 = Halfband2x(coefficients: SaturatorFX.stage1)
        hb2 = Halfband2x(coefficients: SaturatorFX.stage2)
        dcR = Float(exp(-2 * Double.pi * 5 / (4 * sampleRate)))
    }

    // MARK: Curves. Each ADAA form is (F(x1) - F(x0)) / (x1 - x0), F the curve's antiderivative,
    // rearranged so it stays accurate when x1 and x0 are close.

    @inline(__always) static func hard(_ x1: Float, _ x0: Float) -> Float {
        let d = x1 - x0
        if abs(x1) <= 1 && abs(x0) <= 1 { return (x1 + x0) * 0.5 }
        if x1 >= 1 && x0 >= 1 { return 1 }
        if x1 <= -1 && x0 <= -1 { return -1 }
        if abs(d) < 1e-6 { return max(-1, min(1, (x1 + x0) * 0.5)) }
        func F(_ x: Double) -> Double { abs(x) <= 1 ? x * x * 0.5 : abs(x) - 0.5 }
        return Float((F(Double(x1)) - F(Double(x0))) / Double(d))
    }

    /// expm1(u) / u, which tends to 1 as u tends to 0.
    @inline(__always) static func phi(_ u: Float) -> Float {
        abs(u) < 1e-4 ? 1 + u * (0.5 + u * (1.0 / 6)) : expm1f(u) / u
    }

    /// Asymmetric: 1 - e^-x above zero, 0.8 (e^(x / 0.8) - 1) below. Same slope on both sides
    /// of zero (no kink), but the negative side flattens sooner, which adds even harmonics.
    @inline(__always) static func tube(_ x1: Float, _ x0: Float) -> Float {
        let d = x1 - x0
        // Factoring out the smaller exponential keeps both terms bounded (no overflow on big jumps).
        if x1 >= 0 && x0 >= 0 { return 1 - expf(-min(x0, x1)) * phi(-abs(d)) }
        if x1 <= 0 && x0 <= 0 { return -0.8 + 0.8 * expf(max(x0, x1) * 1.25) * phi(-abs(d) * 1.25) }
        if abs(d) < 1e-7 { return 0 }
        func F(_ x: Double) -> Double { x >= 0 ? x + expm1(-x) : -0.8 * x + 0.64 * expm1(x * 1.25) }
        return Float((F(Double(x1)) - F(Double(x0))) / Double(d))
    }

    /// Wavefolder sin(x pi / 2). Its ADAA works out to sin(mid) * sinc(half the step).
    @inline(__always) static func fold(_ x1: Float, _ x0: Float) -> Float {
        let h = (x1 - x0) * (Float.pi / 4)
        let sinc: Float = abs(h) < 1e-3 ? 1 - h * h * (1.0 / 6) : sinf(h) / h
        return sinf((x1 + x0) * (Float.pi / 4)) * sinc
    }

    @inline(__always) func shape(_ x: SIMD2<Float>, _ t: Int) -> SIMD2<Float> {
        let p = prev
        prev = x
        switch t {
        case 1: return SIMD2(SaturatorFX.hard(x.x, p.x), SaturatorFX.hard(x.y, p.y))
        case 2: return SIMD2(SaturatorFX.tube(x.x, p.x), SaturatorFX.tube(x.y, p.y))
        case 3: return SIMD2(SaturatorFX.fold(x.x, p.x), SaturatorFX.fold(x.y, p.y))
        default: return SIMD2(tanhf(x.x), tanhf(x.y))
        }
    }

    /// One sample at 4x: shape, DC block, Tone, then mix with the dry signal.
    @inline(__always) func oversampled(_ v: SIMD2<Float>, _ d: Float, _ wg: Float, _ dg: Float, _ t: Int) -> SIMD2<Float> {
        let w = shape(v * d, t)
        let hp = w - dcIn + dcOut * dcR
        dcIn = w
        dcOut = hp
        lp += (hp - lp) * toneB
        return v * dg + lp * wg
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        if p[2] != lastTone {
            lastTone = p[2]
            // Tone at the top of its range means fully open.
            toneB = p[2] >= 19999 ? 1 : Float(1 - exp(-2 * Double.pi * p[2] / (4 * sr)))
        }
        let t = Int(p[1])
        let driveTarget = Float(dbToGain(p[0]))
        // Rough loudness compensation so turning up drive is not just turning up volume.
        let comp = 1 / max(1, sqrtf(driveTarget))
        let mix = f(p, 4)
        let wetTarget = Float(dbToGain(p[3])) * comp * mix, dryTarget = 1 - mix
        if primed {
            let n = max(frames, 1)
            drive.set(driveTarget, frames: n); wet.set(wetTarget, frames: n); dry.set(dryTarget, frames: n)
        } else {
            drive.snap(driveTarget); wet.snap(wetTarget); dry.snap(dryTarget); primed = true
        }
        for i in 0..<frames {
            let d = drive.next(), wg = wet.next(), dg = dry.next()
            let (a, b) = hb1.up(SIMD2(buf.l[i], buf.r[i]))
            let (a0, a1) = hb2.up(a)
            let (b0, b1) = hb2.up(b)
            let m0 = oversampled(a0, d, wg, dg, t), m1 = oversampled(a1, d, wg, dg, t)
            let m2 = oversampled(b0, d, wg, dg, t), m3 = oversampled(b1, d, wg, dg, t)
            let y = hb1.down(hb2.down(m0, m1), hb2.down(m2, m3))
            buf.l[i] = y.x
            buf.r[i] = y.y
        }
        // A NaN in would stick in the filters forever; start clean instead.
        if !(lp.x.isFinite && lp.y.isFinite && prev.x.isFinite && prev.y.isFinite) { reset() }
    }

    func reset() {
        hb1.reset(); hb2.reset()
        prev = .zero; dcIn = .zero; dcOut = .zero; lp = .zero
        primed = false
    }
}

// MARK: - Bitcrusher

final class BitcrusherFX: EffectProcessor {
    static let params = [
        ParamDef("bits", "Bits", 2, 16, 8),
        ParamDef("downsample", "Downsample", 1, 40, 4, .none, .log),
        ParamDef("mix", "Dry/Wet", 0, 1, 1, .percent),
    ]
    var holdL: Float = 0, holdR: Float = 0, counter: Float = 0

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let steps = powf(2, f(p, 0) - 1), ds = f(p, 1), mix = f(p, 2)
        for i in 0..<frames {
            counter += 1
            if counter >= ds {
                counter -= ds
                holdL = (buf.l[i] * steps).rounded() / steps
                holdR = (buf.r[i] * steps).rounded() / steps
            }
            buf.l[i] = buf.l[i] * (1 - mix) + holdL * mix
            buf.r[i] = buf.r[i] * (1 - mix) + holdR * mix
        }
    }

    func reset() { holdL = 0; holdR = 0; counter = 0 }
}

// MARK: - Volume

final class VolumeFX: EffectProcessor {
    static let params = [ParamDef("volume", "Volume", -60, 12, 0, .db)]
    var g = Smoother(1)
    var primed = false

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        // -60 dB is the bottom of the range and means silence, so fades can start from nothing.
        let target: Float = p[0] <= -59.9 ? 0 : Float(dbToGain(p[0]))
        if primed { g.set(target, frames: max(64, frames)) } else { g.snap(target); primed = true }
        for i in 0..<frames {
            let v = g.next()
            buf.l[i] *= v
            buf.r[i] *= v
        }
    }

    func reset() { primed = false }
}

// MARK: - Utility

final class UtilityFX: EffectProcessor {
    static let params = [
        ParamDef("gain", "Gain", -36, 24, 0, .db),
        ParamDef("pan", "Pan", -1, 1, 0),
        ParamDef("width", "Width", 0, 2, 1, .percent),
        ParamDef.choice("mono", "Mono", ["Off", "On"], 0),
        ParamDef.choice("invert", "Phase", ["Normal", "Invert"], 0),
    ]
    var g = Smoother(1)
    var primed = false

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let (pl, pr) = panGains(p[1])
        let width: Float = p[3] > 0.5 ? 0 : f(p, 2)
        let inv: Float = p[4] > 0.5 ? -1 : 1
        let target = Float(dbToGain(p[0])) * inv
        if primed { g.set(target) } else { g.snap(target); primed = true }
        for i in 0..<frames {
            let gain = g.next()
            let m = (buf.l[i] + buf.r[i]) * 0.5, s = (buf.l[i] - buf.r[i]) * 0.5 * width
            buf.l[i] = (m + s) * gain * pl
            buf.r[i] = (m - s) * gain * pr
        }
    }

    func reset() {}
}
