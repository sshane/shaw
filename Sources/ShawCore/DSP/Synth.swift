import Foundation

public enum SynthParams {
    public static let waves = ["Sine", "Triangle", "Saw", "Square"]

    public static let defs: [ParamDef] = [
        .choice("osc1", "Osc 1", waves, 2),
        .choice("osc2", "Osc 2", waves, 2),
        ParamDef("semi2", "Osc 2 Pitch", -24, 24, 0, .semitones),
        ParamDef("fine2", "Osc 2 Fine", -50, 50, 7, .cents),
        ParamDef("mix", "Osc Mix", 0, 1, 0.5, .percent),
        ParamDef("sub", "Sub Osc", 0, 1, 0, .percent),
        ParamDef("noise", "Noise", 0, 1, 0, .percent),
        .choice("unison", "Unison", ["Off", "3 Voices", "5 Voices", "7 Voices"], 0),
        ParamDef("spread", "Unison Spread", 0, 1, 0.3, .percent),
        ParamDef("cutoff", "Cutoff", 20, 20000, 6000, .hz, .log),
        ParamDef("resonance", "Resonance", 0, 1, 0.15, .percent),
        ParamDef("fenv", "Filter Env", -1, 1, 0.3, .percent),
        ParamDef("keytrack", "Key Track", 0, 1, 0.3, .percent),
        ParamDef("a", "Attack", 0.001, 10, 0.004, .seconds, .log),
        ParamDef("d", "Decay", 0.005, 5, 0.3, .seconds, .log),
        ParamDef("s", "Sustain", 0, 1, 0.75, .percent),
        ParamDef("r", "Release", 0.005, 8, 0.25, .seconds, .log),
        ParamDef("fa", "Filter Attack", 0.001, 10, 0.004, .seconds, .log),
        ParamDef("fd", "Filter Decay", 0.005, 5, 0.35, .seconds, .log),
        ParamDef("fs", "Filter Sustain", 0, 1, 0.3, .percent),
        ParamDef("fr", "Filter Release", 0.005, 8, 0.3, .seconds, .log),
        ParamDef("penv", "Pitch Env", 0, 48, 0, .semitones),
        ParamDef("pdecay", "Pitch Decay", 0.005, 1, 0.06, .seconds, .log),
        .choice("mode", "Voice Mode", ["Poly", "Mono", "Legato"], 0),
        ParamDef("glide", "Glide", 0, 1, 0, .seconds),
        ParamDef("drive", "Drive", 0, 1, 0, .percent),
        ParamDef("volume", "Volume", -36, 6, -8, .db),
        ParamDef("osclevel", "Osc Level", 0, 1, 1, .percent),
    ]

    /// The handful of synth controls shown by default.
    public static let basic = ["cutoff", "resonance", "a", "r", "volume"]

    static let index: [String: Int] = Dictionary(uniqueKeysWithValues: defs.enumerated().map { ($1.id, $0) })

    // Indices into the resolved parameter array.
    static let osc1 = 0, osc2 = 1, semi2 = 2, fine2 = 3, mix = 4, sub = 5, noise = 6, unison = 7, spread = 8
    static let cutoff = 9, res = 10, fenv = 11, keytrack = 12, a = 13, d = 14, s = 15, r = 16
    static let fa = 17, fd = 18, fs = 19, fr = 20, penv = 21, pdecay = 22, mode = 23, glide = 24, drive = 25, volume = 26, oscLevel = 27
}

public enum SynthPresets {
    public static let names = ["Init", "Supersaw", "Pluck", "Pad", "Reese Bass", "Sub Bass", "808 Bass", "Acid", "Keys", "Lead", "Bell", "Noise Riser"]

    public static let categories: [String: String] = [
        "Init": "Synth", "Supersaw": "Lead", "Pluck": "Pluck", "Pad": "Pad", "Reese Bass": "Bass",
        "Sub Bass": "Bass", "808 Bass": "Bass", "Acid": "Bass", "Keys": "Keys", "Lead": "Lead", "Bell": "Keys", "Noise Riser": "FX",
    ]

    static let overrides: [String: [String: Double]] = [
        "Init": [:],
        "Supersaw": ["unison": 3, "spread": 0.45, "fine2": 12, "cutoff": 9000, "fenv": 0.1, "a": 0.01, "s": 0.85, "r": 0.4, "volume": -12],
        "Pluck": ["osc2": 3, "semi2": 12, "mix": 0.35, "cutoff": 900, "resonance": 0.25, "fenv": 0.7, "fd": 0.18, "fs": 0, "d": 0.4, "s": 0, "r": 0.3, "keytrack": 0.6, "volume": -8],
        "Pad": ["unison": 2, "spread": 0.5, "a": 0.9, "d": 1.5, "s": 0.8, "r": 2.2, "cutoff": 2500, "fenv": 0.25, "fa": 1.2, "fd": 2, "fs": 0.4, "volume": -14],
        "Reese Bass": ["osc1": 2, "osc2": 2, "fine2": 25, "unison": 1, "spread": 0.2, "cutoff": 700, "resonance": 0.2, "fenv": 0.1, "mode": 1, "glide": 0.04, "sub": 0.4, "drive": 0.3, "s": 1, "r": 0.15, "volume": -8],
        "Sub Bass": ["osc1": 0, "osc2": 0, "mix": 0, "sub": 0, "cutoff": 400, "fenv": 0, "mode": 1, "glide": 0.03, "s": 1, "r": 0.12, "drive": 0.15, "volume": -4],
        "808 Bass": ["osc1": 0, "osc2": 0, "mix": 0, "cutoff": 2000, "fenv": 0, "penv": 12, "pdecay": 0.04, "a": 0.002, "d": 2.2, "s": 0.0, "r": 0.4, "mode": 2, "glide": 0.06, "drive": 0.45, "volume": -4],
        "Acid": ["osc1": 2, "mix": 0, "cutoff": 400, "resonance": 0.85, "fenv": 0.75, "fd": 0.22, "fs": 0.05, "mode": 2, "glide": 0.06, "s": 0.9, "r": 0.08, "drive": 0.4, "keytrack": 0.5, "volume": -10],
        "Keys": ["osc1": 1, "osc2": 0, "semi2": 12, "mix": 0.3, "cutoff": 3000, "fenv": 0.3, "fd": 0.6, "d": 1.4, "s": 0.35, "r": 0.5, "volume": -8],
        "Lead": ["osc1": 3, "osc2": 2, "fine2": 9, "cutoff": 4500, "resonance": 0.3, "fenv": 0.2, "mode": 2, "glide": 0.05, "s": 0.9, "r": 0.2, "drive": 0.2, "volume": -10],
        // White noise whose filter opens over ~8 seconds: hold one long note for a build-up.
        "Noise Riser": ["osclevel": 0, "noise": 1, "cutoff": 220, "resonance": 0.35, "fenv": 0.78, "keytrack": 0,
                        "fa": 7.5, "fd": 2, "fs": 1, "fr": 0.8, "a": 6, "d": 1, "s": 1, "r": 0.6, "volume": -16],
        "Bell": ["osc1": 0, "osc2": 1, "semi2": 19, "fine2": 0, "mix": 0.45, "cutoff": 9000, "fenv": 0, "a": 0.001, "d": 2.5, "s": 0, "r": 2, "volume": -10],
    ]

    public static func params(for name: String) -> [String: Double] {
        var p = SynthParams.defs.defaults()
        for (k, v) in overrides[name] ?? [:] { p[k] = v }
        return p
    }
}

/// Linear-attack, exponential decay/release envelope.
struct ADSR {
    enum Stage { case idle, attack, decay, sustain, release }
    var stage = Stage.idle
    var level: Float = 0
    var aInc: Float = 0, dCoef: Float = 0, rCoef: Float = 0, sus: Float = 1

    mutating func configure(a: Double, d: Double, s: Double, r: Double, sr: Double) {
        aInc = Float(1 / max(1, a * sr))
        dCoef = Float(exp(-4.6 / max(1, d * sr)))
        rCoef = Float(exp(-4.6 / max(1, r * sr)))
        sus = Float(s)
    }

    mutating func gate(on: Bool, retrigger: Bool = true) {
        if on {
            if retrigger || stage == .idle || stage == .release { stage = .attack }
        } else if stage != .idle {
            stage = .release
        }
    }

    @inline(__always) mutating func next() -> Float {
        switch stage {
        case .idle: return 0
        case .attack:
            level += aInc
            if level >= 1 { level = 1; stage = .decay }
        case .decay:
            level = sus + (level - sus) * dCoef
            if abs(level - sus) < 0.0005 { level = sus; stage = .sustain }
        case .sustain:
            level = sus
        case .release:
            level *= rCoef
            if level < 0.00005 { level = 0; stage = .idle }
        }
        return level
    }
}

@inline(__always) func polyBlep(_ t: Double, _ dt: Double) -> Double {
    if t < dt { let x = t / dt; return x + x - x * x - 1 }
    if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
    return 0
}

@inline(__always) func oscillator(_ wave: Int, _ phase: Double, _ dt: Double) -> Double {
    switch wave {
    case 0: return sin(2 * .pi * phase)
    case 1: return phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase
    case 2: return 2 * phase - 1 - polyBlep(phase, dt)
    default:
        var v = phase < 0.5 ? 1.0 : -1.0
        v += polyBlep(phase, dt)
        var t2 = phase + 0.5; if t2 >= 1 { t2 -= 1 }
        v -= polyBlep(t2, dt)
        return v
    }
}

struct SynthVoice {
    var note = -1
    var velocity: Float = 0
    var order = 0
    var freq = 440.0, targetFreq = 440.0
    var phSub = 0.0
    var amp = ADSR(), fenv = ADSR()
    var pitchEnv: Float = 0
    var fL = SVF(), fR = SVF()
    var held = false
    var fade: Float = 1 // used for quick voice-steal fades
    var fading = false

    var isActive: Bool { amp.stage != .idle }
}

/// Polyphonic subtractive synth. Owned by one pattern instance (or the preview channel).
public final class Synth {
    var voices = [SynthVoice](repeating: SynthVoice(), count: 16)
    var counter = 0
    var noiseSeed: UInt32 = 22222
    var lastNote = -1
    var heldStack: [Int] = []
    let sr: Double
    /// Oscillator phases live outside the voice structs so copying a voice never allocates.
    let ph1: UnsafeMutablePointer<Double>
    let ph2: UnsafeMutablePointer<Double>
    static let maxUnison = 7

    public init(sampleRate: Double) {
        sr = sampleRate
        heldStack.reserveCapacity(64)
        let n = voices.count * Synth.maxUnison
        ph1 = .allocate(capacity: n)
        ph2 = .allocate(capacity: n)
        for i in 0..<n {
            ph1[i] = Double.random(in: 0..<1)
            ph2[i] = Double.random(in: 0..<1)
        }
    }

    deinit {
        ph1.deallocate()
        ph2.deallocate()
    }

    static func freq(_ note: Int) -> Double { 440 * pow(2, Double(note - 69) / 12) }

    public func noteOn(_ note: Int, velocity: Float, params p: [Double]) {
        let mode = Int(p[SynthParams.mode])
        counter += 1
        heldStack.removeAll { $0 == note }
        heldStack.append(note)
        if mode > 0 {
            // Mono / legato: one voice, glide from the previous pitch.
            let legato = mode == 2 && voices[0].held && voices[0].isActive
            var v = voices[0]
            let wasActive = v.isActive
            v.note = note
            v.velocity = velocity
            v.targetFreq = Synth.freq(note)
            if !wasActive || p[SynthParams.glide] <= 0 { v.freq = v.targetFreq }
            v.held = true
            v.order = counter
            configure(&v, p)
            if !legato {
                v.amp.gate(on: true, retrigger: true)
                v.fenv.gate(on: true, retrigger: true)
                v.pitchEnv = 1
            }
            voices[0] = v
            for i in 1..<voices.count where voices[i].isActive { voices[i].amp.gate(on: false) }
            lastNote = note
            return
        }
        // Poly: prefer a free voice, else steal the oldest (released voices first).
        var idx = voices.firstIndex { !$0.isActive } ?? -1
        if idx < 0 {
            var best = 0, bestScore = Int.max
            for (i, v) in voices.enumerated() {
                let score = v.order - (v.held ? 0 : 1_000_000)
                if score < bestScore { bestScore = score; best = i }
            }
            idx = best
        }
        var v = voices[idx]
        v.note = note
        v.velocity = velocity
        v.freq = Synth.freq(note)
        v.targetFreq = v.freq
        v.order = counter
        v.held = true
        v.pitchEnv = 1
        configure(&v, p)
        v.amp.gate(on: true)
        v.fenv.gate(on: true)
        voices[idx] = v
        lastNote = note
    }

    public func noteOff(_ note: Int, params p: [Double]) {
        heldStack.removeAll { $0 == note }
        let mode = Int(p[SynthParams.mode])
        if mode > 0 {
            if voices[0].note == note {
                if let prev = heldStack.last {
                    // Return to the note still held underneath (classic mono behaviour).
                    voices[0].note = prev
                    voices[0].targetFreq = Synth.freq(prev)
                    if p[SynthParams.glide] <= 0 { voices[0].freq = voices[0].targetFreq }
                } else {
                    voices[0].held = false
                    voices[0].amp.gate(on: false)
                    voices[0].fenv.gate(on: false)
                }
            }
            return
        }
        for i in voices.indices where voices[i].note == note && voices[i].held {
            voices[i].held = false
            voices[i].amp.gate(on: false)
            voices[i].fenv.gate(on: false)
        }
    }

    public func allNotesOff() {
        heldStack.removeAll(keepingCapacity: true)
        for i in voices.indices where voices[i].isActive {
            voices[i].held = false
            voices[i].amp.gate(on: false)
            voices[i].fenv.gate(on: false)
        }
    }

    public func reset() {
        heldStack.removeAll(keepingCapacity: true)
        for i in voices.indices {
            voices[i].amp = ADSR()
            voices[i].fenv = ADSR()
            voices[i].held = false
            voices[i].fL.reset(); voices[i].fR.reset()
        }
    }

    public var isSilent: Bool { !voices.contains { $0.isActive } }

    private func configure(_ v: inout SynthVoice, _ p: [Double]) {
        v.amp.configure(a: p[SynthParams.a], d: p[SynthParams.d], s: p[SynthParams.s], r: p[SynthParams.r], sr: sr)
        v.fenv.configure(a: p[SynthParams.fa], d: p[SynthParams.fd], s: p[SynthParams.fs], r: p[SynthParams.fr], sr: sr)
    }

    @inline(__always) private func noise() -> Double {
        noiseSeed = noiseSeed &* 1664525 &+ 1013904223
        return Double(Int32(bitPattern: noiseSeed)) / Double(Int32.max)
    }

    /// Adds output into the given pointers.
    public func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, frames: Int, params p: [Double]) {
        if isSilent { return }
        let w1 = Int(p[SynthParams.osc1]), w2 = Int(p[SynthParams.osc2])
        let ratio2 = pow(2, (p[SynthParams.semi2] + p[SynthParams.fine2] / 100) / 12)
        let mix = p[SynthParams.mix], sub = p[SynthParams.sub], nz = p[SynthParams.noise]
        let uniCount = [1, 3, 5, 7][Int(p[SynthParams.unison])]
        let spread = p[SynthParams.spread]
        let cutoff = p[SynthParams.cutoff], res = Float(p[SynthParams.res])
        let fenvAmt = p[SynthParams.fenv], keytrack = p[SynthParams.keytrack]
        let penv = p[SynthParams.penv]
        let pdec = Float(exp(-4.6 / max(1, p[SynthParams.pdecay] * sr)))
        let glideCoef = p[SynthParams.glide] > 0 ? exp(-4.6 / (p[SynthParams.glide] * sr)) : 0
        let drive = p[SynthParams.drive]
        let driveGain = Float(1 + drive * 8), driveComp = 1 / Float(1 + drive * 2.5)
        let vol = Float(dbToGain(p[SynthParams.volume]))
        let srF = Float(sr)
        let uniNorm = 1 / sqrt(Double(uniCount)) * p[SynthParams.oscLevel]
        // Unison detune is constant for the block; precompute instead of calling pow() per sample.
        var detunes = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        var ratios = (1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
        withUnsafeMutableBytes(of: &detunes) { d in
            withUnsafeMutableBytes(of: &ratios) { r in
                let dp = d.bindMemory(to: Double.self), rp = r.bindMemory(to: Double.self)
                for u in 0..<uniCount {
                    dp[u] = uniCount == 1 ? 0 : (Double(u) / Double(uniCount - 1) * 2 - 1)
                    rp[u] = pow(2, dp[u] * spread * 0.6 / 12)
                }
            }
        }
        let detunesArr = detunes, ratiosArr = ratios

        for vi in voices.indices where voices[vi].isActive {
            var v = voices[vi]
            // Refresh envelope rates every block so knob moves affect held notes.
            v.amp.configure(a: p[SynthParams.a], d: p[SynthParams.d], s: p[SynthParams.s], r: p[SynthParams.r], sr: sr)
            v.fenv.configure(a: p[SynthParams.fa], d: p[SynthParams.fd], s: p[SynthParams.fs], r: p[SynthParams.fr], sr: sr)
            let velGain = 0.3 + 0.7 * v.velocity
            let base = vi * Synth.maxUnison
            let detunes = TupleIndex(detunesArr), detuneRatios = TupleIndex(ratiosArr)
            for i in 0..<frames {
                if glideCoef > 0 { v.freq = v.targetFreq + (v.freq - v.targetFreq) * glideCoef } else { v.freq = v.targetFreq }
                var f0 = v.freq
                if penv > 0 {
                    f0 *= pow(2, Double(v.pitchEnv) * penv / 12)
                    v.pitchEnv *= pdec
                }
                var sl = 0.0, sr2 = 0.0
                for u in 0..<uniCount {
                    let det = detunes[u]
                    let fu = f0 * detuneRatios[u]
                    let dt1 = fu / sr, dt2 = fu * ratio2 / sr
                    let k = base + u
                    let o = oscillator(w1, ph1[k], dt1) * (1 - mix) + oscillator(w2, ph2[k], dt2) * mix
                    ph1[k] += dt1; if ph1[k] >= 1 { ph1[k] -= 1 }
                    ph2[k] += dt2; if ph2[k] >= 1 { ph2[k] -= 1 }
                    let pan = uniCount == 1 ? 0.5 : 0.5 + det * 0.45
                    sl += o * (1 - pan) * 2
                    sr2 += o * pan * 2
                }
                sl *= uniNorm; sr2 *= uniNorm
                if sub > 0 {
                    let s = sin(2 * .pi * v.phSub) * sub * p[SynthParams.oscLevel]
                    v.phSub += f0 * 0.5 / sr; if v.phSub >= 1 { v.phSub -= 1 }
                    sl += s; sr2 += s
                }
                if nz > 0 { let n = noise() * nz * 0.5; sl += n; sr2 += n }

                let fe = Double(v.fenv.next())
                if i & 7 == 0 {
                    let kt = pow(f0 / 261.6, keytrack)
                    let c = min(cutoff * kt * pow(2, fenvAmt * fe * 7), sr * 0.45)
                    v.fL.set(cutoff: Float(c), resonance: res, sampleRate: srF)
                    v.fR.g = v.fL.g; v.fR.k = v.fL.k; v.fR.a1 = v.fL.a1; v.fR.a2 = v.fL.a2; v.fR.a3 = v.fL.a3
                }
                var l = v.fL.process(Float(sl)).0
                var r = v.fR.process(Float(sr2)).0
                if drive > 0 { l = tanhf(l * driveGain) * driveComp * 1.5; r = tanhf(r * driveGain) * driveComp * 1.5 }
                let a = v.amp.next() * velGain * vol
                outL[i] += l * a
                outR[i] += r * a
                if v.amp.stage == .idle { break }
            }
            voices[vi] = v
        }
    }
}

/// Allocation-free indexable view over a 7-element tuple.
struct TupleIndex {
    let t: (Double, Double, Double, Double, Double, Double, Double)
    init(_ t: (Double, Double, Double, Double, Double, Double, Double)) { self.t = t }
    @inline(__always) subscript(i: Int) -> Double {
        switch i {
        case 0: return t.0
        case 1: return t.1
        case 2: return t.2
        case 3: return t.3
        case 4: return t.4
        case 5: return t.5
        default: return t.6
        }
    }
}
