import Foundation

/// Immutable mono or stereo sample data, safe to share with the audio thread.
public final class SampleData {
    public let frames: Int
    public let channels: Int
    public let sampleRate: Double
    public let l: UnsafeMutablePointer<Float>
    public let r: UnsafeMutablePointer<Float>

    public init(left: [Float], right: [Float]? = nil, sampleRate: Double) {
        frames = left.count
        channels = right == nil ? 1 : 2
        self.sampleRate = sampleRate
        l = .allocate(capacity: max(1, frames))
        l.initialize(from: left, count: frames)
        if let right {
            r = .allocate(capacity: max(1, frames))
            r.initialize(from: right, count: min(frames, right.count))
        } else {
            r = l
        }
    }

    deinit {
        if r != l { r.deallocate() }
        l.deallocate()
    }

    public var duration: Double { Double(frames) / sampleRate }
}

public struct DrumVoiceInfo {
    public let id: String
    public let name: String
    /// Voices in the same choke group cut each other off (closed hat chokes open hat).
    public let choke: Int
}

public struct DrumKitInfo: Identifiable {
    public let id: String
    public let name: String
    public let summary: String
}

/// Synthesized drum kits. Nothing is downloaded, so there are no licensing questions.
public enum DrumKits {
    public static let defaultKit = "trap"

    public static let voices: [DrumVoiceInfo] = [
        DrumVoiceInfo(id: "kick", name: "Kick", choke: 0),
        DrumVoiceInfo(id: "snare", name: "Snare", choke: 0),
        DrumVoiceInfo(id: "clap", name: "Clap", choke: 0),
        DrumVoiceInfo(id: "chat", name: "Closed Hat", choke: 1),
        DrumVoiceInfo(id: "ohat", name: "Open Hat", choke: 1),
        DrumVoiceInfo(id: "tomlo", name: "Low Tom", choke: 0),
        DrumVoiceInfo(id: "tomhi", name: "High Tom", choke: 0),
        DrumVoiceInfo(id: "rim", name: "Rim", choke: 0),
        DrumVoiceInfo(id: "perc", name: "Perc", choke: 0),
        DrumVoiceInfo(id: "crash", name: "Crash", choke: 2),
    ]

    public static let kits: [DrumKitInfo] = [
        DrumKitInfo(id: "trap", name: "Trap 808", summary: "Long boomy 808 kick, crisp snare, and tight hats"),
        DrumKitInfo(id: "house", name: "House 909", summary: "Punchy four-on-the-floor kick and bright hats"),
        DrumKitInfo(id: "boombap", name: "Boom Bap", summary: "Dusty, round hip-hop drums"),
        DrumKitInfo(id: "lofi", name: "Lo-Fi", summary: "Crunchy, filtered, and bit-reduced"),
        DrumKitInfo(id: "techno", name: "Techno", summary: "Hard, distorted industrial kit"),
        DrumKitInfo(id: "electro", name: "Electro", summary: "Dry, snappy drum machine with a tight kick"),
        DrumKitInfo(id: "drill", name: "Drill", summary: "Deep sliding 808 kick, sharp snare, and crisp hats"),
    ]

    /// Lowest pitch of a kit in the piano roll: C1 is the kick, then one sound per semitone.
    public static let basePitch = 36

    public static func pitch(of voice: String) -> Int {
        basePitch + (voices.firstIndex { $0.id == voice } ?? 0)
    }

    public static func voice(atPitch pitch: Int) -> DrumVoiceInfo? {
        let i = pitch - basePitch
        return i >= 0 && i < voices.count ? voices[i] : nil
    }

    public static func voiceName(_ id: String) -> String { voices.first { $0.id == id }?.name ?? id }
    public static func kitName(_ id: String) -> String { kits.first { $0.id == id }?.name ?? id }
    public static func choke(_ id: String) -> Int { voices.first { $0.id == id }?.choke ?? 0 }

    // MARK: Cache

    private static var cache: [String: [String: SampleData]] = [:]
    private static let lock = NSLock()

    /// Sample for a kit voice, generated on first use at the given sample rate.
    public static func sample(kit: String, voice: String, sampleRate: Double) -> SampleData? {
        let key = "\(kit)@\(Int(sampleRate))"
        lock.lock()
        defer { lock.unlock() }
        if cache[key] == nil {
            cache[key] = generate(kit: kit, sampleRate: sampleRate)
        }
        return cache[key]?[voice]
    }

    /// Already-generated sample, or nil. Never generates, so it's safe on the audio thread
    /// (the lock is only contended while a kit is being generated).
    static func cachedSample(kit: String, voice: String, sampleRate: Double) -> SampleData? {
        let key = "\(kit)@\(Int(sampleRate))"
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return cache[key]?[voice]
    }

    public static func warm(sampleRate: Double) {
        for k in kits { _ = sample(kit: k.id, voice: "kick", sampleRate: sampleRate) }
    }

    // MARK: Synthesis

    struct Rng {
        var s: UInt32
        mutating func next() -> Float {
            s = s &* 1664525 &+ 1013904223
            return Float(Int32(bitPattern: s)) / Float(Int32.max)
        }
    }

    struct KickSpec { var start: Double, end: Double, pitchDecay: Double, ampDecay: Double, click: Float, drive: Float, length: Double }
    struct SnareSpec { var tone: Double, toneDecay: Double, noiseDecay: Double, noiseLevel: Float, hp: Double, length: Double }
    struct HatSpec { var closed: Double, open: Double, hp: Double, metal: Float }

    static func generate(kit: String, sampleRate sr: Double) -> [String: SampleData] {
        var kick: KickSpec, snare: SnareSpec, hat: HatSpec
        var clapTail = 0.12, tomDecay = 0.35, crashDecay = 0.42
        var post: ([Float]) -> [Float] = { $0 }
        switch kit {
        case "house":
            kick = KickSpec(start: 260, end: 50, pitchDecay: 0.03, ampDecay: 0.32, click: 0.5, drive: 1.6, length: 0.6)
            snare = SnareSpec(tone: 190, toneDecay: 0.06, noiseDecay: 0.18, noiseLevel: 0.8, hp: 1500, length: 0.4)
            hat = HatSpec(closed: 0.05, open: 0.2, hp: 7000, metal: 0.7)
            clapTail = 0.18
        case "boombap":
            kick = KickSpec(start: 180, end: 52, pitchDecay: 0.04, ampDecay: 0.28, click: 0.25, drive: 2.2, length: 0.55)
            snare = SnareSpec(tone: 210, toneDecay: 0.08, noiseDecay: 0.16, noiseLevel: 0.65, hp: 900, length: 0.4)
            hat = HatSpec(closed: 0.06, open: 0.16, hp: 5000, metal: 0.4)
            tomDecay = 0.3
            post = { lowpass($0, 7000, sr) }
        case "lofi":
            kick = KickSpec(start: 160, end: 48, pitchDecay: 0.05, ampDecay: 0.3, click: 0.1, drive: 2.5, length: 0.5)
            snare = SnareSpec(tone: 230, toneDecay: 0.07, noiseDecay: 0.14, noiseLevel: 0.55, hp: 700, length: 0.35)
            hat = HatSpec(closed: 0.05, open: 0.14, hp: 4500, metal: 0.3)
            post = { crush(lowpass($0, 4200, sr), bits: 9, hold: 3) }
        case "techno":
            kick = KickSpec(start: 300, end: 46, pitchDecay: 0.022, ampDecay: 0.45, click: 0.8, drive: 4.0, length: 0.7)
            snare = SnareSpec(tone: 170, toneDecay: 0.05, noiseDecay: 0.12, noiseLevel: 0.9, hp: 2000, length: 0.3)
            hat = HatSpec(closed: 0.035, open: 0.15, hp: 8000, metal: 0.75)
            clapTail = 0.25
            crashDecay = 0.3
        case "electro":
            kick = KickSpec(start: 210, end: 50, pitchDecay: 0.025, ampDecay: 0.42, click: 0.55, drive: 1.8, length: 0.6)
            snare = SnareSpec(tone: 220, toneDecay: 0.04, noiseDecay: 0.11, noiseLevel: 0.95, hp: 2500, length: 0.3)
            hat = HatSpec(closed: 0.04, open: 0.13, hp: 8000, metal: 0.8)
            clapTail = 0.14
        case "drill":
            kick = KickSpec(start: 120, end: 40, pitchDecay: 0.08, ampDecay: 1.4, click: 0.3, drive: 1.6, length: 1.9)
            snare = SnareSpec(tone: 230, toneDecay: 0.04, noiseDecay: 0.12, noiseLevel: 0.9, hp: 2600, length: 0.3)
            hat = HatSpec(closed: 0.03, open: 0.14, hp: 9000, metal: 0.7)
            clapTail = 0.16
        default: // trap
            kick = KickSpec(start: 150, end: 44, pitchDecay: 0.06, ampDecay: 1.1, click: 0.35, drive: 1.4, length: 1.6)
            snare = SnareSpec(tone: 200, toneDecay: 0.05, noiseDecay: 0.17, noiseLevel: 0.85, hp: 1800, length: 0.4)
            hat = HatSpec(closed: 0.035, open: 0.17, hp: 8500, metal: 0.6)
            clapTail = 0.2
        }

        // Peak-normalized, then balanced by ear-loudness: long voices (crash, open hat, toms) sound
        // much louder than a snare at the same peak, so they're turned down to sit together.
        let gains: [String: Float] = ["kick": 0.7, "crash": 0.35, "ohat": 0.5, "tomlo": 0.6, "tomhi": 0.6]
        var current = ""
        func make(_ x: [Float]) -> SampleData {
            let g = gains[current] ?? 1
            return SampleData(left: normalize(post(x)).map { $0 * g }, sampleRate: sr)
        }
        var out: [String: SampleData] = [:]
        current = "kick"; out["kick"] = make(synthKick(kick, sr))
        current = "snare"; out["snare"] = make(synthSnare(snare, sr))
        current = "clap"; out["clap"] = make(synthClap(tail: clapTail, sr))
        current = "chat"; out["chat"] = make(synthHat(decay: hat.closed, hp: hat.hp, metal: hat.metal, sr, seed: 7))
        current = "ohat"; out["ohat"] = make(synthHat(decay: hat.open, hp: hat.hp, metal: hat.metal, sr, seed: 9))
        current = "tomlo"; out["tomlo"] = make(synthTom(freq: 95, decay: tomDecay, sr))
        current = "tomhi"; out["tomhi"] = make(synthTom(freq: 165, decay: tomDecay * 0.85, sr))
        current = "rim"; out["rim"] = make(synthRim(sr))
        current = "perc"; out["perc"] = make(synthPerc(sr))
        current = "crash"; out["crash"] = make(synthCrash(decay: crashDecay, sr))
        return out
    }

    static func normalize(_ x: [Float], peak: Float = 0.89) -> [Float] {
        let m = x.reduce(0) { max($0, abs($1)) }
        guard m > 0 else { return x }
        let g = peak / m
        // Smooth fade over the last 30% so a tail that is still sounding (a driven kick) never
        // ends in a click or a thump. Tails that already died away don't change.
        let fadeStart = Int(Double(x.count) * 0.7)
        let fadeN = max(1, x.count - fadeStart)
        return x.enumerated().map { i, v in
            guard i >= fadeStart else { return v * g }
            let t = Float(i - fadeStart) / Float(fadeN)
            return v * g * (0.5 + 0.5 * cosf(.pi * t))
        }
    }

    static func lowpass(_ x: [Float], _ freq: Double, _ sr: Double) -> [Float] {
        var b = Biquad()
        b.set(.lowpass, freq: freq, q: 0.707, sampleRate: sr)
        return x.map { b.process($0) }
    }

    static func highpass(_ x: [Float], _ freq: Double, _ sr: Double) -> [Float] {
        var b = Biquad()
        b.set(.highpass, freq: freq, q: 0.707, sampleRate: sr)
        return x.map { b.process($0) }
    }

    static func crush(_ x: [Float], bits: Float, hold: Int) -> [Float] {
        let steps = powf(2, bits - 1)
        var h: Float = 0
        return x.enumerated().map { i, v in
            if i % hold == 0 { h = (v * steps).rounded() / steps }
            return h
        }
    }

    static func synthKick(_ k: KickSpec, _ sr: Double) -> [Float] {
        let n = Int(k.length * sr)
        var rng = Rng(s: 1)
        var phase = 0.0
        var click = Biquad()
        click.set(.highpass, freq: 1200, q: 0.7, sampleRate: sr)
        return (0..<n).map { i in
            let t = Double(i) / sr
            let f = k.end + (k.start - k.end) * exp(-t / k.pitchDecay)
            phase += f / sr
            let body = sin(2 * .pi * phase) * exp(-t / k.ampDecay)
            let atk = min(1, t / 0.0008)
            var v = Float(body * atk)
            if t < 0.012 { v += click.process(rng.next()) * k.click * Float(1 - t / 0.012) }
            return tanhf(v * k.drive) / tanhf(k.drive)
        }
    }

    static func synthSnare(_ s: SnareSpec, _ sr: Double) -> [Float] {
        let n = Int(max(s.length, s.noiseDecay * 6) * sr)
        var rng = Rng(s: 3)
        var hp = Biquad(), lp = Biquad()
        hp.set(.highpass, freq: s.hp, q: 0.7, sampleRate: sr)
        lp.set(.lowpass, freq: 11000, q: 0.7, sampleRate: sr)
        var p1 = 0.0, p2 = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sr
            let f = s.tone * (1 + 0.5 * exp(-t / 0.01))
            p1 += f / sr; p2 += f * 1.62 / sr
            let tone = (sin(2 * .pi * p1) + 0.5 * sin(2 * .pi * p2)) * exp(-t / s.toneDecay)
            let nz = lp.process(hp.process(rng.next())) * s.noiseLevel * Float(exp(-t / s.noiseDecay))
            return Float(tone) * 0.8 + nz * 1.4
        }
    }

    static func synthClap(tail: Double, _ sr: Double) -> [Float] {
        let n = Int((tail * 4 + 0.05) * sr)
        var rng = Rng(s: 5)
        var bp = Biquad()
        bp.set(.bandpass, freq: 1300, q: 1.2, sampleRate: sr)
        let bursts = [0.0, 0.011, 0.022, 0.031]
        return (0..<n).map { i in
            let t = Double(i) / sr
            var env = 0.0
            for b in bursts where t >= b { env = max(env, exp(-(t - b) / 0.006)) }
            if t >= bursts.last! { env = max(env, 0.7 * exp(-(t - bursts.last!) / tail)) }
            return bp.process(rng.next()) * Float(env) * 3
        }
    }

    /// Hats and cymbals: six band-limited 808-style square waves (no aliasing fizz) plus noise,
    /// band-passed and high-passed. `decay` is the time constant; the sample stops once it's
    /// about 60 dB down, so nothing rings on long after you stop hearing it.
    static func synthHat(decay: Double, hp: Double, metal: Float, _ sr: Double, seed: UInt32, wide: Bool = false) -> [Float] {
        let n = Int((decay * 7 + 0.01) * sr)
        var rng = Rng(s: seed)
        let freqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].map { $0 * (wide ? 1.3 : 1.7) }
        var phases = [Double](repeating: 0, count: 6)
        var h1 = Biquad(), h2 = Biquad(), bp = Biquad()
        h1.set(.highpass, freq: hp, q: 0.7, sampleRate: sr)
        h2.set(.highpass, freq: hp, q: 0.7, sampleRate: sr)
        bp.set(.peak, freq: wide ? 6500 : 10000, q: 0.8, gainDb: 5, sampleRate: sr)
        return (0..<n).map { i in
            let t = Double(i) / sr
            var m: Double = 0
            for j in 0..<6 {
                let dt = freqs[j] / sr
                m += oscillator(3, phases[j], dt)
                phases[j] += dt
                if phases[j] >= 1 { phases[j] -= 1 }
            }
            let src = Float(m / 6) * metal + rng.next() * (1 - metal * 0.5)
            // A bright stick hit up front, then the body decays.
            let body = exp(-t / decay)
            let hit = wide ? 0.6 * exp(-t / 0.03) : 0.3 * exp(-t / 0.006)
            let env = Float(min(1, body + hit) * min(1, t / 0.0004))
            return bp.process(h2.process(h1.process(src))) * env
        }
    }

    /// Crash cymbal: mostly bright noise, with ring-modulated square pairs for the dense metallic
    /// shimmer (pure square banks sound like a gong). The body dies faster than the sizzle on top.
    static func synthCrash(decay: Double, _ sr: Double) -> [Float] {
        let n = Int((decay * 6 + 0.02) * sr)
        var rng = Rng(s: 13)
        let freqs = [205.3, 369.6, 304.4, 522.7, 540.0, 800.0].map { $0 * 1.31 }
        var phases = [Double](repeating: 0, count: 6)
        var bodyBP = Biquad(), sizzleHP = Biquad(), sizzleHP2 = Biquad(), lowCut = Biquad()
        bodyBP.set(.bandpass, freq: 4200, q: 0.9, sampleRate: sr)
        sizzleHP.set(.highpass, freq: 7500, q: 0.7, sampleRate: sr)
        sizzleHP2.set(.highpass, freq: 7500, q: 0.7, sampleRate: sr)
        lowCut.set(.highpass, freq: 2500, q: 0.7, sampleRate: sr)
        return (0..<n).map { i in
            let t = Double(i) / sr
            func sq(_ j: Int) -> Double {
                let dt = freqs[j] / sr
                let v = oscillator(3, phases[j], dt)
                phases[j] += dt
                if phases[j] >= 1 { phases[j] -= 1 }
                return v
            }
            // Ring modulation: sum and difference tones make a dense, inharmonic spread.
            let metal = Float((sq(0) * sq(1) + sq(2) * sq(3) + sq(4) * sq(5)) / 3)
            let noise = rng.next()
            let src = noise * 0.75 + metal * 0.45
            let body = bodyBP.process(src) * Float(exp(-t / (decay * 0.45)))
            let sizzle = sizzleHP2.process(sizzleHP.process(src)) * Float(exp(-t / decay))
            let hit = Float(exp(-t / 0.012)) * noise * 0.6
            let attack = Float(min(1, t / 0.0006))
            return lowCut.process(body * 1.2 + sizzle + hit) * attack
        }
    }

    static func synthTom(freq: Double, decay: Double, _ sr: Double) -> [Float] {
        let n = Int(decay * 6 * sr)
        var phase = 0.0
        var rng = Rng(s: 11)
        return (0..<n).map { i in
            let t = Double(i) / sr
            let f = freq * (1 + 0.6 * exp(-t / 0.04))
            phase += f / sr
            let v = sin(2 * .pi * phase) * exp(-t / decay)
            return Float(v) + rng.next() * 0.05 * Float(exp(-t / 0.01))
        }
    }

    static func synthRim(_ sr: Double) -> [Float] {
        let n = Int(0.12 * sr)
        var rng = Rng(s: 17)
        var bp = Biquad()
        bp.set(.bandpass, freq: 2200, q: 3, sampleRate: sr)
        var phase = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sr
            let tri = Float(oscillator(1, phase, 1700 / sr) * exp(-t / 0.006))
            phase += 1700 / sr; if phase >= 1 { phase -= 1 }
            return tri * 0.6 + bp.process(rng.next()) * Float(exp(-t / 0.02)) * 2
        }
    }

    static func synthPerc(_ sr: Double) -> [Float] {
        // Cowbell-style: two detuned squares through a band-pass.
        let n = Int(0.5 * sr)
        var bp = Biquad()
        bp.set(.bandpass, freq: 800, q: 1.5, sampleRate: sr)
        var p1 = 0.0, p2 = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sr
            // Band-limited squares, so the bell doesn't fizz with aliasing.
            let s = oscillator(3, p1, 540 / sr) + oscillator(3, p2, 800 / sr)
            p1 += 540 / sr; if p1 >= 1 { p1 -= 1 }
            p2 += 800 / sr; if p2 >= 1 { p2 -= 1 }
            let env = t < 0.01 ? 1 : 0.6 * exp(-(t - 0.01) / 0.09) + 0.4 * exp(-t / 0.015)
            return bp.process(Float(s * env))
        }
    }
}
