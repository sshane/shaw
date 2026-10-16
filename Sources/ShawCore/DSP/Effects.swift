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

// MARK: - Reverb (Freeverb topology)

final class ReverbFX: EffectProcessor {
    static let params = [
        ParamDef("size", "Size", 0, 1, 0.7, .percent),
        ParamDef("damping", "Damping", 0, 1, 0.5, .percent),
        ParamDef("predelay", "Pre-Delay", 0, 200, 10, .ms),
        ParamDef("lowcut", "Low Cut", 20, 2000, 150, .hz, .log),
        ParamDef("width", "Width", 0, 1, 1, .percent),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.3, .percent),
    ]

    final class Comb {
        let line: UnsafeMutablePointer<Float>
        let size: Int
        var idx = 0
        var store: Float = 0
        init(_ n: Int) { size = n; line = .allocate(capacity: n); line.initialize(repeating: 0, count: n) }
        deinit { line.deallocate() }
        @inline(__always) func process(_ x: Float, fb: Float, damp: Float) -> Float {
            let out = line[idx]
            store = out * (1 - damp) + store * damp
            line[idx] = x + store * fb
            idx += 1; if idx >= size { idx = 0 }
            return out
        }
        func reset() { line.update(repeating: 0, count: size); store = 0 }
    }

    final class Allpass {
        let line: UnsafeMutablePointer<Float>
        let size: Int
        var idx = 0
        init(_ n: Int) { size = n; line = .allocate(capacity: n); line.initialize(repeating: 0, count: n) }
        deinit { line.deallocate() }
        @inline(__always) func process(_ x: Float) -> Float {
            let b = line[idx]
            line[idx] = x + b * 0.5
            idx += 1; if idx >= size { idx = 0 }
            return b - x
        }
        func reset() { line.update(repeating: 0, count: size) }
    }

    let combsL: [Comb], combsR: [Comb]
    let apL: [Allpass], apR: [Allpass]
    let pre: DelayLine
    var hpL = Biquad(), hpR = Biquad()
    var lastLowCut = -1.0
    let sr: Double

    init(sampleRate: Double) {
        sr = sampleRate
        let s = sampleRate / 44100
        let combT = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let apT = [556, 441, 341, 225]
        combsL = combT.map { Comb(Int(Double($0) * s)) }
        combsR = combT.map { Comb(Int(Double($0 + 23) * s)) }
        apL = apT.map { Allpass(Int(Double($0) * s)) }
        apR = apT.map { Allpass(Int(Double($0 + 23) * s)) }
        pre = DelayLine(maxSamples: Int(0.25 * sampleRate))
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let fb = 0.7 + f(p, 0) * 0.28
        let damp = f(p, 1) * 0.4
        let preSamples = Float(p[2] / 1000 * sr)
        if p[3] != lastLowCut {
            lastLowCut = p[3]
            hpL.set(.highpass, freq: p[3], q: 0.707, sampleRate: sr)
            hpR = hpL
        }
        let width = f(p, 4), mix = f(p, 5)
        let wet1 = mix * (width / 2 + 0.5), wet2 = mix * ((1 - width) / 2)
        let dry = 1 - mix * 0.5
        for i in 0..<frames {
            let inL = buf.l[i], inR = buf.r[i]
            pre.write((inL + inR) * 0.5)
            var x = preSamples < 1 ? (inL + inR) * 0.5 : pre.read(preSamples)
            x = hpL.process(x) * 0.03
            var oL: Float = 0, oR: Float = 0
            for c in combsL { oL += c.process(x, fb: fb, damp: damp) }
            for c in combsR { oR += c.process(x, fb: fb, damp: damp) }
            for a in apL { oL = a.process(oL) }
            for a in apR { oR = a.process(oR) }
            buf.l[i] = inL * dry + oL * wet1 + oR * wet2
            buf.r[i] = inR * dry + oR * wet1 + oL * wet2
        }
    }

    func reset() {
        combsL.forEach { $0.reset() }; combsR.forEach { $0.reset() }
        apL.forEach { $0.reset() }; apR.forEach { $0.reset() }
        pre.reset(); hpL.reset(); hpR.reset()
    }
}

// MARK: - Delay

final class DelayFX: EffectProcessor {
    static let params = [
        ParamDef.choice("time", "Time", SyncDivision.names, 6),
        ParamDef("feedback", "Feedback", 0, 0.95, 0.4, .percent),
        ParamDef.choice("pingpong", "Ping-Pong", ["Off", "On"], 1),
        ParamDef("lowcut", "Low Cut", 20, 2000, 150, .hz, .log),
        ParamDef("highcut", "High Cut", 500, 20000, 7000, .hz, .log),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.3, .percent),
    ]

    let dl: DelayLine, dr: DelayLine
    var time = Smoother(0)
    var hpL = Biquad(), hpR = Biquad(), lpL = Biquad(), lpR = Biquad()
    var lastCuts = (-1.0, -1.0)
    let sr: Double

    init(sampleRate: Double) {
        sr = sampleRate
        dl = DelayLine(maxSamples: Int(sampleRate * 5))
        dr = DelayLine(maxSamples: Int(sampleRate * 5))
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let div = SyncDivision.beats[Int(p[0])]
        let target = Float(min(div * 60 / ctx.bpm, 4.9) * sr)
        if time.value == 0 { time.snap(target) } else { time.set(target, frames: 2048) }
        if p[3] != lastCuts.0 || p[4] != lastCuts.1 {
            lastCuts = (p[3], p[4])
            hpL.set(.highpass, freq: p[3], q: 0.707, sampleRate: sr); hpR = hpL
            lpL.set(.lowpass, freq: p[4], q: 0.707, sampleRate: sr); lpR = lpL
        }
        let fb = f(p, 1), ping = p[2] > 0.5, mix = f(p, 5)
        for i in 0..<frames {
            let d = time.next()
            let inL = buf.l[i], inR = buf.r[i]
            var wl = dl.read(d), wr = dr.read(d)
            wl = lpL.process(hpL.process(wl))
            wr = lpR.process(hpR.process(wr))
            if ping {
                // Mono input enters the left line; each repeat crosses sides.
                dl.write((inL + inR) * 0.5 + wr * fb)
                dr.write(wl * fb)
            } else {
                dl.write(inL + wl * fb)
                dr.write(inR + wr * fb)
            }
            buf.l[i] = inL * (1 - mix * 0.5) + wl * mix
            buf.r[i] = inR * (1 - mix * 0.5) + wr * mix
        }
    }

    func reset() { dl.reset(); dr.reset(); hpL.reset(); hpR.reset(); lpL.reset(); lpR.reset() }
}

// MARK: - Chorus

final class ChorusFX: EffectProcessor {
    static let params = [
        ParamDef("rate", "Rate", 0.05, 8, 0.8, .hz, .log),
        ParamDef("depth", "Depth", 0, 1, 0.5, .percent),
        ParamDef("delay", "Delay", 1, 30, 12, .ms),
        ParamDef("feedback", "Feedback", 0, 0.9, 0, .percent),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.5, .percent),
    ]
    let dl: DelayLine, dr: DelayLine
    var phase: Double = 0
    let sr: Double
    var lastL: Float = 0, lastR: Float = 0

    init(sampleRate: Double) {
        sr = sampleRate
        dl = DelayLine(maxSamples: Int(sampleRate * 0.08))
        dr = DelayLine(maxSamples: Int(sampleRate * 0.08))
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let inc = p[0] / sr
        let base = Float(p[2] / 1000 * sr)
        let depth = Float(p[1]) * min(base * 0.9, Float(0.006 * sr))
        let fb = f(p, 3), mix = f(p, 4)
        for i in 0..<frames {
            phase += inc; if phase >= 1 { phase -= 1 }
            let s = Float(sin(2 * .pi * phase)), c = Float(cos(2 * .pi * phase))
            let inL = buf.l[i], inR = buf.r[i]
            dl.write(inL + lastL * fb)
            dr.write(inR + lastR * fb)
            lastL = dl.read(base + depth * s)
            lastR = dr.read(base + depth * c)
            buf.l[i] = inL * (1 - mix * 0.5) + lastL * mix
            buf.r[i] = inR * (1 - mix * 0.5) + lastR * mix
        }
    }

    func reset() { dl.reset(); dr.reset(); lastL = 0; lastR = 0 }
}

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
        for i in 0..<frames {
            let ph = (beat + Double(i) * bps) / period
            let x = ph - floor(ph)
            let r = min(1, x / rel)
            let target = Float(1 - depth * (1 - pow(r, 1 / curve)))
            // A ~1 ms slew keeps the duck from clicking at each beat.
            g.value += (target - g.value) * 0.05
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
    var env: Float = -96
    let sr: Double
    init(sampleRate: Double) { sr = sampleRate }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let th = f(p, 0), ratio = f(p, 1)
        let att = Float(exp(-1 / (p[2] / 1000 * sr))), rel = Float(exp(-1 / (p[3] / 1000 * sr)))
        let makeup = Float(dbToGain(p[4])), mix = f(p, 5)
        let knee: Float = 6
        for i in 0..<frames {
            let l = buf.l[i], r = buf.r[i]
            let lvl = max(abs(l), abs(r))
            let db = lvl > 1e-6 ? 20 * log10f(lvl) : -120
            env = db > env ? att * env + (1 - att) * db : rel * env + (1 - rel) * db
            let over = env - th
            var gr: Float = 0
            if over > knee / 2 { gr = over * (1 - 1 / ratio) }
            else if over > -knee / 2 { let k = over + knee / 2; gr = (1 - 1 / ratio) * k * k / (2 * knee) }
            let g = powf(10, -gr / 20) * makeup
            buf.l[i] = l * (1 - mix) + l * g * mix
            buf.r[i] = r * (1 - mix) + r * g * mix
        }
    }

    func reset() { env = -96 }
}

// MARK: - Limiter (lookahead peak limiter)

final class LimiterFX: EffectProcessor {
    static let params = [
        ParamDef("gain", "Gain", 0, 24, 0, .db),
        ParamDef("ceiling", "Ceiling", -12, 0, -0.3, .db),
        ParamDef("release", "Release", 10, 500, 80, .ms, .log),
    ]
    let look: Int
    let dl: DelayLine, dr: DelayLine
    var gain: Float = 1
    let sr: Double

    init(sampleRate: Double) {
        sr = sampleRate
        look = Int(sampleRate * 0.0015)
        dl = DelayLine(maxSamples: look + 4)
        dr = DelayLine(maxSamples: look + 4)
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let pre = Float(dbToGain(p[0])), ceil = Float(dbToGain(p[1]))
        let rel = Float(exp(-1 / (p[2] / 1000 * sr)))
        let att = Float(exp(-1 / Double(max(look, 1)) * 2.5))
        for i in 0..<frames {
            let l = buf.l[i] * pre, r = buf.r[i] * pre
            dl.write(l); dr.write(r)
            let pk = max(abs(l), abs(r))
            let target: Float = pk > ceil ? ceil / pk : 1
            gain = target < gain ? att * gain + (1 - att) * target : rel * gain + (1 - rel) * target
            var ol = dl.read(int: look + 1) * gain, or = dr.read(int: look + 1) * gain
            // Safety clip in case the envelope has not fully caught a transient.
            ol = max(-ceil, min(ceil, ol)); or = max(-ceil, min(ceil, or))
            buf.l[i] = ol; buf.r[i] = or
        }
    }

    func reset() { dl.reset(); dr.reset(); gain = 1 }
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
    var lpL = OnePole(), lpR = OnePole()
    var lastTone = -1.0
    let sr: Double
    init(sampleRate: Double) { sr = sampleRate }

    @inline(__always) func shape(_ x: Float, _ t: Int) -> Float {
        switch t {
        case 1: return max(-1, min(1, x))
        case 2: return x >= 0 ? 1 - expf(-x) : -(1 - expf(x)) * 0.8 // asymmetric = even harmonics
        case 3: return sinf(x * 0.5 * .pi) // wavefolder
        default: return tanhf(x)
        }
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        if p[2] != lastTone { lastTone = p[2]; lpL.setLowpass(p[2], sampleRate: sr); lpR.a = lpL.a }
        let drive = Float(dbToGain(p[0])), t = Int(p[1])
        // Rough loudness compensation so turning up drive is not just turning up volume.
        let comp = 1 / max(1, sqrtf(drive))
        let out = Float(dbToGain(p[3])) * comp, mix = f(p, 4)
        for i in 0..<frames {
            let inL = buf.l[i], inR = buf.r[i]
            let wl = lpL.lowpass(shape(inL * drive, t)) * out
            let wr = lpR.lowpass(shape(inR * drive, t)) * out
            buf.l[i] = inL * (1 - mix) + wl * mix
            buf.r[i] = inR * (1 - mix) + wr * mix
        }
    }

    func reset() { lpL.reset(); lpR.reset() }
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
