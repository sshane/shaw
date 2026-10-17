import Accelerate
import Foundation

/// Sampler controls. They live in `Instrument.params` like the synth's, but only mean
/// something when the instrument has a `sample`.
public enum SamplerParams {
    /// Samples up to this long (seconds) start out playing whole (One-Shot); longer ones follow the note.
    public static let oneShotLimit = 2.0

    public static let defs: [ParamDef] = [
        .choice("playmode", "Mode", ["Note Length", "One-Shot"], 1),
        ParamDef("root", "Root Note", 0, 127, 60, .note),
        ParamDef("start", "Start", 0, 1, 0, .percent),
        ParamDef("cutoff", "Cutoff", 20, 20000, 20000, .hz, .log),
        ParamDef("r", "Release", 0.005, 10, 0.08, .seconds, .log),
        ParamDef("volume", "Volume", -36, 12, 0, .db),
        ParamDef("fine", "Fine Tune", -50, 50, 0, .cents),
        ParamDef("a", "Attack", 0.0005, 10, 0.001, .seconds, .log),
        ParamDef("d", "Decay", 0.005, 10, 1, .seconds, .log),
        ParamDef("s", "Sustain", 0, 1, 1, .percent),
        ParamDef("resonance", "Resonance", 0, 1, 0, .percent),
        .choice("loop", "Loop", ["Off", "On"], 0),
        ParamDef("loopstart", "Loop Start", 0, 1, 0, .percent),
        ParamDef("loopend", "Loop End", 0, 1, 1, .percent),
    ]

    /// The controls shown before "More".
    public static let basic = ["playmode", "root", "start", "cutoff", "r", "volume"]

    // Indices into the resolved parameter array.
    static let playmode = 0, root = 1, start = 2, cutoff = 3, release = 4, volume = 5
    static let fine = 6, attack = 7, decay = 8, sustain = 9, resonance = 10, loop = 11, loopStart = 12, loopEnd = 13
}

/// A decoded sample plus half-rate copies of it (a mipmap). A note pitched far up reads from a
/// copy that's already filtered below the new Nyquist frequency, so it doesn't alias.
public final class MipSample {
    /// Level 0 is the file itself; each next level has half the sample rate.
    public let levels: [SampleData]
    public var base: SampleData { levels[0] }
    public var sampleRate: Double { levels[0].sampleRate }
    public var frames: Int { levels[0].frames }
    public var duration: Double { levels[0].duration }

    public init(_ base: SampleData, maxLevels: Int = 6) {
        var lv = [base]
        while lv.count <= maxLevels, lv[lv.count - 1].frames >= 64 {
            lv.append(MipSample.halve(lv[lv.count - 1]))
        }
        levels = lv
    }

    /// Kaiser-windowed sinc low-pass at 0.225 of the sample rate: flat to about 0.2, at least 80 dB down
    /// by 0.25 (the half-rate Nyquist), so nothing folds back when every other frame is dropped.
    static let taps: [Float] = {
        let n = 95, fc = 0.225, beta = 8.0
        let m = Double(n - 1)
        func i0(_ x: Double) -> Double {
            var sum = 1.0, term = 1.0
            for k in 1..<40 { let q = x / (2 * Double(k)); term *= q * q; sum += term }
            return sum
        }
        let h = (0..<n).map { i -> Double in
            let x = Double(i) - m / 2
            let sinc = x == 0 ? 2 * fc : sin(2 * .pi * fc * x) / (.pi * x)
            let w = i0(beta * sqrt(max(0, 1 - pow(2 * Double(i) / m - 1, 2)))) / i0(beta)
            return sinc * w
        }
        let sum = h.reduce(0, +)
        return h.map { Float($0 / sum) }
    }()

    static func halve(_ s: SampleData) -> SampleData {
        let h = taps, n = h.count, half = n / 2
        let outCount = (s.frames + 1) / 2
        func run(_ src: UnsafeMutablePointer<Float>) -> [Float] {
            // Zero padding on both sides keeps output frame i centered on input frame 2i.
            var padded = [Float](repeating: 0, count: s.frames + n + 1)
            padded.withUnsafeMutableBufferPointer { p in (p.baseAddress! + half).update(from: src, count: s.frames) }
            var out = [Float](repeating: 0, count: outCount)
            vDSP_desamp(padded, 2, h, &out, vDSP_Length(outCount), vDSP_Length(n))
            return out
        }
        let l = run(s.l)
        let r = s.channels > 1 ? run(s.r) : nil
        return SampleData(left: l, right: r, sampleRate: s.sampleRate / 2)
    }
}

/// 4-point, 3rd-order Hermite interpolation. Frames outside the sample read as silence.
@inline(__always) func hermite(_ d: UnsafeMutablePointer<Float>, _ n: Int, _ i: Int, _ t: Float) -> Float {
    let xm1: Float, x0: Float, x1: Float, x2: Float
    if i >= 1 && i + 2 < n {
        xm1 = d[i - 1]; x0 = d[i]; x1 = d[i + 1]; x2 = d[i + 2]
    } else {
        xm1 = i - 1 >= 0 && i - 1 < n ? d[i - 1] : 0
        x0 = i >= 0 && i < n ? d[i] : 0
        x1 = i + 1 >= 0 && i + 1 < n ? d[i + 1] : 0
        x2 = i + 2 >= 0 && i + 2 < n ? d[i + 2] : 0
    }
    let c1 = 0.5 * (x1 - xm1)
    let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
    let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
    return ((c3 * t + c2) * t + c1) * t + x0
}

struct SamplerVoice {
    /// Keeps the sample alive while the voice reads it (the library owns it, so this never frees on the audio thread).
    var sample: MipSample?
    var l: UnsafeMutablePointer<Float>?
    var r: UnsafeMutablePointer<Float>?
    var frames = 0
    /// Read position and speed, in frames of the chosen mip level.
    var pos = 0.0
    var step = 1.0
    var note = -1
    var held = false
    var oneShot = false
    var looping = false
    var loopStart = 0.0, loopEnd = 0.0, xfade = 0.0
    var gain: Float = 0
    var env = ADSR()
    /// Stolen or retriggered: fade out over a few milliseconds instead of cutting (which clicks).
    var fade: Float = 1
    var fading = false
    var order = 0

    var isActive: Bool { sample != nil }
}

/// Plays one sample across the keyboard, like Ableton's Simpler: each note is the sample pitched by
/// (note − root) semitones. 16 voices; past that the oldest note fades out to make room.
public final class Sampler {
    static let polyphony = 16
    static let maxBlock = 2048
    /// Spare slots let a stolen voice fade out while the new note starts.
    var voices = [SamplerVoice](repeating: SamplerVoice(), count: Sampler.polyphony + 8)
    var counter = 0
    let sr: Double
    let bufL: UnsafeMutablePointer<Float>
    let bufR: UnsafeMutablePointer<Float>
    var fL = SVF(), fR = SVF()
    var cutoffZ = 20000.0
    var gainZ: Float = 1
    var filterDirty = false
    /// Set while silent: the next note snaps cutoff and volume instead of gliding from old values.
    var fresh = true

    public init(sampleRate: Double) {
        sr = sampleRate
        bufL = .allocate(capacity: Sampler.maxBlock)
        bufR = .allocate(capacity: Sampler.maxBlock)
        bufL.initialize(repeating: 0, count: Sampler.maxBlock)
        bufR.initialize(repeating: 0, count: Sampler.maxBlock)
    }

    deinit {
        bufL.deallocate()
        bufR.deallocate()
    }

    public var isSilent: Bool { !voices.contains { $0.sample != nil } }

    /// Start a note. `offset` skips into the sample (seconds), for notes picked up mid-way after a seek.
    /// Audio thread safe: no allocation.
    public func noteOn(_ note: Int, velocity: Float, params p: [Double], sample: MipSample?, offset: Double = 0) {
        guard let sample, sample.frames > 1 else { return }
        counter += 1
        let oneShot = p[SamplerParams.playmode] > 0.5
        // The same key fades out what it was playing (Simpler's Retrigger), so repeated chops don't smear.
        for i in voices.indices where voices[i].isActive && voices[i].note == note && !voices[i].fading {
            voices[i].fading = true
            voices[i].held = false
        }
        // Past 16 voices, the oldest released note goes first, then the oldest held one.
        var sounding = 0, victim = -1, best = Int.max
        for i in voices.indices where voices[i].isActive && !voices[i].fading {
            sounding += 1
            let score = voices[i].order - (voices[i].held ? 0 : 1_000_000)
            if score < best { best = score; victim = i }
        }
        if sounding >= Sampler.polyphony, victim >= 0 {
            voices[victim].fading = true
            voices[victim].held = false
        }
        // A free slot, else the quietest fading one.
        var idx = -1
        for i in voices.indices where !voices[i].isActive { idx = i; break }
        if idx < 0 {
            var quietest: Float = .infinity
            for i in voices.indices where voices[i].fading && i != victim && voices[i].fade < quietest {
                quietest = voices[i].fade; idx = i
            }
        }
        if idx < 0 { idx = max(0, victim) }

        let semis = Double(note) - p[SamplerParams.root].rounded() + p[SamplerParams.fine] / 100
        let rate = pow(2, semis / 12) * sample.sampleRate / sr
        // Read from a half-rate copy once the note is pitched up far enough to alias.
        var level = 0
        if rate > 1.3 { level = min(sample.levels.count - 1, Int((log2(rate / 1.3)).rounded(.up))) }
        let scale = Double(1 << level)
        let data = sample.levels[level]
        let last0 = Double(sample.frames - 1)
        var v = SamplerVoice()
        v.sample = sample
        v.l = data.l
        v.r = data.r
        v.frames = data.frames
        v.step = rate / scale
        v.pos = p[SamplerParams.start] * last0 / scale + max(0, offset) * sr * v.step
        if !oneShot && p[SamplerParams.loop] > 0.5 {
            let a = p[SamplerParams.loopStart], b = p[SamplerParams.loopEnd]
            let ls = min(a, b) * last0, le = max(a, b) * last0
            if le - ls > 64 {
                v.looping = true
                v.loopStart = ls / scale
                v.loopEnd = le / scale
                // Crossfade into the loop start so the seam doesn't click.
                v.xfade = min(0.03 * sample.sampleRate, (le - ls) * 0.5) / scale
            }
        }
        v.note = note
        v.held = true
        v.oneShot = oneShot
        v.gain = velocity * velocity
        v.order = counter
        v.env.configure(a: p[SamplerParams.attack], d: p[SamplerParams.decay], s: p[SamplerParams.sustain],
                        r: p[SamplerParams.release], sr: sr)
        v.env.gate(on: true)
        voices[idx] = v
    }

    /// One-Shot notes ignore this and play to the end of the sample.
    public func noteOff(_ note: Int) {
        for i in voices.indices where voices[i].isActive && voices[i].note == note && voices[i].held {
            voices[i].held = false
            if !voices[i].oneShot { voices[i].env.gate(on: false) }
        }
    }

    public func allNotesOff() {
        for i in voices.indices where voices[i].isActive && voices[i].held {
            voices[i].held = false
            if !voices[i].oneShot { voices[i].env.gate(on: false) }
        }
    }

    /// Fade out everything, One-Shots included (a new browser preview replaces the old one).
    public func cutAll() {
        for i in voices.indices where voices[i].isActive {
            voices[i].fading = true
            voices[i].held = false
        }
    }

    public func reset() {
        for i in voices.indices { voices[i] = SamplerVoice() }
        fL.reset(); fR.reset()
        fresh = true
    }

    /// Adds output into the given pointers.
    public func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, frames: Int, params p: [Double]) {
        if frames > Sampler.maxBlock {
            var f = 0
            while f < frames {
                let n = min(Sampler.maxBlock, frames - f)
                render(outL + f, outR + f, frames: n, params: p)
                f += n
            }
            return
        }
        if isSilent {
            // Let the filter settle to zero so the next note starts clean.
            if filterDirty { fL.reset(); fR.reset(); filterDirty = false }
            fresh = true
            return
        }
        filterDirty = true
        vDSP_vclr(bufL, 1, vDSP_Length(frames))
        vDSP_vclr(bufR, 1, vDSP_Length(frames))
        let fadeStep = Float(1 / (0.005 * sr))
        let endFade = 48.0 // output frames of fade before the sample's last frame
        for vi in voices.indices where voices[vi].isActive {
            var v = voices[vi]
            // Follow knob moves on held notes.
            v.env.configure(a: p[SamplerParams.attack], d: p[SamplerParams.decay], s: p[SamplerParams.sustain],
                            r: p[SamplerParams.release], sr: sr)
            guard let dl = v.l, let dr = v.r else { voices[vi] = SamplerVoice(); continue }
            let mono = dl == dr
            let n = v.frames
            let lastPos = Double(n - 1)
            let loopLen = v.loopEnd - v.loopStart
            for i in 0..<frames {
                if !v.looping && v.pos >= lastPos { v.sample = nil; break }
                let ip = Int(v.pos.rounded(.down))
                let t = Float(v.pos - Double(ip))
                var xl = hermite(dl, n, ip, t)
                var xr = mono ? xl : hermite(dr, n, ip, t)
                if v.looping && v.xfade > 0 && v.pos >= v.loopEnd - v.xfade {
                    let w = Float((v.pos - (v.loopEnd - v.xfade)) / v.xfade)
                    let q = v.pos - loopLen
                    let iq = Int(q.rounded(.down))
                    let tq = Float(q - Double(iq))
                    let yl = hermite(dl, n, iq, tq)
                    let yr = mono ? yl : hermite(dr, n, iq, tq)
                    xl += (yl - xl) * w
                    xr += (yr - xr) * w
                }
                var g = v.env.next() * v.gain
                if v.env.stage == .idle { v.sample = nil; break }
                if v.fading {
                    v.fade -= fadeStep
                    if v.fade <= 0 { v.sample = nil; break }
                    g *= v.fade
                }
                if !v.looping {
                    let remain = (lastPos - v.pos) / v.step
                    if remain < endFade { g *= Float(remain / endFade) }
                }
                bufL[i] += xl * g
                bufR[i] += xr * g
                v.pos += v.step
                if v.looping && v.pos >= v.loopEnd { v.pos -= loopLen }
            }
            if v.sample == nil { v = SamplerVoice() }
            voices[vi] = v
        }
        // One filter for the whole instrument (cheaper than one per voice, and the same sound here).
        // Above 16 kHz it crossfades to the dry signal, so fully open really is untouched.
        let target = p[SamplerParams.cutoff]
        let res = Float(p[SamplerParams.resonance])
        let vol = Float(dbToGain(p[SamplerParams.volume]))
        let srF = Float(sr)
        if fresh {
            cutoffZ = target
            gainZ = vol
            fresh = false
        }
        var i = 0
        while i < frames {
            cutoffZ = exp(log(cutoffZ) + (log(target) - log(cutoffZ)) * 0.25)
            let c = Float(cutoffZ)
            fL.setSampler(cutoff: c, resonance: res, sampleRate: srF)
            fR.copyCoefficients(fL)
            let dry = min(1, max(0, (c - 16000) / 4000))
            let end = min(frames, i + 16)
            while i < end {
                let l = fL.process(bufL[i]).0, r = fR.process(bufR[i]).0
                gainZ += (vol - gainZ) * 0.002
                outL[i] += (l + (bufL[i] - l) * dry) * gainZ
                outR[i] += (r + (bufR[i] - r) * dry) * gainZ
                i += 1
            }
        }
    }
}

extension SVF {
    /// Low-pass that's Butterworth-flat at zero resonance and peaks as it rises.
    @inline(__always) mutating func setSampler(cutoff: Float, resonance: Float, sampleRate: Float) {
        let fc = min(max(cutoff, 15), sampleRate * 0.47)
        g = tanf(Float.pi * fc / sampleRate)
        k = 1.414 - 1.36 * min(max(resonance, 0), 1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }
}
