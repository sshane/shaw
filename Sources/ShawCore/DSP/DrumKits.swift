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
    //
    // Each voice follows a classic drum-machine recipe (808 and 909 kicks, tuned snare modes with a
    // snappy noise layer, multi-burst claps, six-square metallic hats). Then every voice is finished
    // the same way: high-passed so there's no DC or rumble, trimmed once it has faded out, faded to
    // exactly zero, and set to a loudness that sits it in the kit. Offline, so allocation is fine.

    struct Rng {
        var s: UInt32
        mutating func next() -> Float {
            s = s &* 1664525 &+ 1013904223
            return Float(Int32(bitPattern: s)) / Float(Int32.max)
        }
    }

    struct KickSpec {
        /// Main pitch drop: from `start` to `end` Hz with time constant `pitchTau`.
        var start: Double, end: Double, pitchTau: Double
        /// Extra Hz for the first millisecond or two: the bright knock of the beater.
        var chirp: Double
        /// Amplitude: full for `hold` seconds, then an exponential decay.
        var hold: Double, decay: Double, length: Double
        /// Beater noise level and its band.
        var click: Float, clickFreq: Double
        /// Saturation (1 is gentle), then a low-pass that keeps the added harmonics warm.
        var drive: Double, tone: Double
        /// How far the pitch keeps sinking over the tail, as a fraction (drill 808s slide down).
        var glide: Double = 0
    }

    struct SnareSpec {
        /// The two lowest drum-head modes, a small pitch drop, and how long they ring.
        var f1: Double, f2: Double, bend: Double, toneDecay: Double, toneLevel: Float
        /// The snare wires: noise with its own envelope, high-passed, with a presence band and a top cut.
        var noiseDecay: Double, noiseLevel: Float, noiseHP: Double, noiseBand: Double, noiseLP: Double
        var drive: Double, room: Float, length: Double
    }

    struct ClapSpec { var freq: Double, spacing: Double, tail: Double, room: Float }
    struct HatSpec { var closed: Double, open: Double, hp: Double, band: Double, lp: Double, metal: Float }
    struct TomSpec { var low: Double, high: Double, decay: Double, stick: Float }

    /// Loudness of each voice relative to the kick (K-weighted, loudest 100 ms), like a mixed kit:
    /// snare and clap just under the kick, toms a little lower, hats and cymbals well underneath.
    static let balance: [String: Double] = [
        "kick": 0, "snare": -1, "clap": -2, "chat": -8.5, "ohat": -8, "tomlo": -3, "tomhi": -3.5,
        "rim": -6.5, "perc": -7, "crash": -9.5,
    ]
    /// Loudness of the kick. Peaks are kept under -0.5 dBFS, so a deep 808 can come out a little quieter.
    static let kickLoudness = -8.5

    static func generate(kit: String, sampleRate sr: Double) -> [String: SampleData] {
        var kick: KickSpec, snare: SnareSpec, clap: ClapSpec, hat: HatSpec, tom: TomSpec
        var crashDecay = 0.42
        var mix: [String: Double] = [:]
        var post: ([Float]) -> [Float] = { $0 }
        switch kit {
        case "house":
            // 909: sine body with a fast drop from 240 Hz, a bright knock, and a little hold for punch.
            kick = KickSpec(start: 240, end: 53, pitchTau: 0.022, chirp: 1600, hold: 0.01, decay: 0.2, length: 0.6,
                            click: 0.4, clickFreq: 4500, drive: 2, tone: 9000)
            snare = SnareSpec(f1: 185, f2: 330, bend: 0.3, toneDecay: 0.06, toneLevel: 0.75, noiseDecay: 0.1, noiseLevel: 1,
                              noiseHP: 1000, noiseBand: 4500, noiseLP: 11000, drive: 1.8, room: 0, length: 0.45)
            clap = ClapSpec(freq: 1250, spacing: 0.01, tail: 0.12, room: 0.35)
            hat = HatSpec(closed: 0.035, open: 0.12, hp: 6500, band: 9000, lp: 16000, metal: 0.55)
            tom = TomSpec(low: 105, high: 158, decay: 0.16, stick: 0.4)
        case "boombap":
            // Sampled-from-vinyl feel: a round kick with a woody knock, a fat snare in a small room.
            kick = KickSpec(start: 160, end: 57, pitchTau: 0.03, chirp: 600, hold: 0.008, decay: 0.17, length: 0.5,
                            click: 0.45, clickFreq: 2200, drive: 2.6, tone: 5500)
            snare = SnareSpec(f1: 180, f2: 310, bend: 0.2, toneDecay: 0.08, toneLevel: 1, noiseDecay: 0.13, noiseLevel: 0.85,
                              noiseHP: 700, noiseBand: 2800, noiseLP: 8000, drive: 2.4, room: 0.35, length: 0.55)
            clap = ClapSpec(freq: 1100, spacing: 0.011, tail: 0.13, room: 0.45)
            hat = HatSpec(closed: 0.04, open: 0.12, hp: 5000, band: 7000, lp: 11000, metal: 0.4)
            tom = TomSpec(low: 92, high: 138, decay: 0.22, stick: 0.3)
            mix = ["snare": 0]
            post = { saturate(lowpass($0, 7500, sr), 1.3) }
        case "lofi":
            kick = KickSpec(start: 140, end: 52, pitchTau: 0.035, chirp: 300, hold: 0.006, decay: 0.18, length: 0.5,
                            click: 0.15, clickFreq: 1800, drive: 2, tone: 5000)
            snare = SnareSpec(f1: 210, f2: 360, bend: 0.2, toneDecay: 0.07, toneLevel: 0.9, noiseDecay: 0.11, noiseLevel: 1,
                              noiseHP: 600, noiseBand: 2500, noiseLP: 7000, drive: 2, room: 0.3, length: 0.45)
            clap = ClapSpec(freq: 1100, spacing: 0.011, tail: 0.12, room: 0.4)
            hat = HatSpec(closed: 0.035, open: 0.1, hp: 4500, band: 6500, lp: 10000, metal: 0.3)
            tom = TomSpec(low: 95, high: 142, decay: 0.2, stick: 0.2)
            post = { crush(lowpass($0, 4200, sr), bits: 9, hold: 3) }
        case "techno":
            // A hard 909: long hold, heavy drive, then a low-pass so the distortion is weight, not fizz.
            kick = KickSpec(start: 280, end: 47, pitchTau: 0.017, chirp: 2200, hold: 0.02, decay: 0.28, length: 0.75,
                            click: 0.5, clickFreq: 5000, drive: 4.5, tone: 4500)
            snare = SnareSpec(f1: 170, f2: 300, bend: 0.3, toneDecay: 0.05, toneLevel: 0.85, noiseDecay: 0.09, noiseLevel: 1,
                              noiseHP: 1500, noiseBand: 5000, noiseLP: 11000, drive: 3.5, room: 0.2, length: 0.4)
            clap = ClapSpec(freq: 1300, spacing: 0.0095, tail: 0.16, room: 0.5)
            hat = HatSpec(closed: 0.025, open: 0.1, hp: 8000, band: 10500, lp: 17000, metal: 0.75)
            tom = TomSpec(low: 90, high: 135, decay: 0.15, stick: 0.4)
            crashDecay = 0.3
            mix = ["clap": -1.5]
        case "electro":
            // 808, dry: a short tight kick with a click, a tonal snare, and the classic 1 kHz clap.
            kick = KickSpec(start: 190, end: 54, pitchTau: 0.013, chirp: 900, hold: 0.004, decay: 0.15, length: 0.5,
                            click: 0.25, clickFreq: 3000, drive: 1.3, tone: 12000)
            snare = SnareSpec(f1: 225, f2: 400, bend: 0.2, toneDecay: 0.045, toneLevel: 1, noiseDecay: 0.065, noiseLevel: 0.8,
                              noiseHP: 2500, noiseBand: 6500, noiseLP: 14000, drive: 1.3, room: 0, length: 0.35)
            clap = ClapSpec(freq: 1000, spacing: 0.0105, tail: 0.09, room: 0.2)
            hat = HatSpec(closed: 0.03, open: 0.1, hp: 7500, band: 10000, lp: 17000, metal: 0.8)
            tom = TomSpec(low: 110, high: 165, decay: 0.16, stick: 0.2)
        case "drill":
            // A deep 808 that keeps sliding down, driven for grit; sharp high snare and crisp hats.
            kick = KickSpec(start: 120, end: 41, pitchTau: 0.045, chirp: 400, hold: 0, decay: 0.75, length: 1.9,
                            click: 0.12, clickFreq: 3000, drive: 2.4, tone: 3500, glide: 0.06)
            snare = SnareSpec(f1: 235, f2: 420, bend: 0.25, toneDecay: 0.04, toneLevel: 0.75, noiseDecay: 0.065, noiseLevel: 1,
                              noiseHP: 2200, noiseBand: 6500, noiseLP: 15000, drive: 2, room: 0, length: 0.35)
            clap = ClapSpec(freq: 1600, spacing: 0.009, tail: 0.1, room: 0.25)
            hat = HatSpec(closed: 0.022, open: 0.1, hp: 8500, band: 11000, lp: 18000, metal: 0.7)
            tom = TomSpec(low: 100, high: 150, decay: 0.2, stick: 0.25)
            mix = ["chat": -7]
        default: // trap
            // 808: a long sine with a short drop from 150 Hz, gently driven, with a controlled tail.
            kick = KickSpec(start: 150, end: 46, pitchTau: 0.03, chirp: 500, hold: 0, decay: 0.55, length: 1.6,
                            click: 0.12, clickFreq: 3000, drive: 1.5, tone: 6000)
            snare = SnareSpec(f1: 205, f2: 360, bend: 0.25, toneDecay: 0.045, toneLevel: 0.8, noiseDecay: 0.07, noiseLevel: 1,
                              noiseHP: 1800, noiseBand: 6000, noiseLP: 14000, drive: 1.6, room: 0, length: 0.35)
            clap = ClapSpec(freq: 1500, spacing: 0.0095, tail: 0.1, room: 0.3)
            hat = HatSpec(closed: 0.028, open: 0.11, hp: 7500, band: 10000, lp: 17000, metal: 0.6)
            tom = TomSpec(low: 98, high: 147, decay: 0.2, stick: 0.25)
            mix = ["chat": -7, "snare": -0.5]
        }

        let raw: [(String, [Float], Double)] = [
            ("kick", synthKick(kick, sr), 18),
            ("snare", synthSnare(snare, sr), 60),
            ("clap", synthClap(clap, sr), 300),
            ("chat", synthHat(decay: hat.closed, hat, sr, seed: 7), 2000),
            ("ohat", synthHat(decay: hat.open, hat, sr, seed: 9), 2000),
            ("tomlo", synthTom(freq: tom.low, decay: tom.decay, stick: tom.stick, sr), 30),
            ("tomhi", synthTom(freq: tom.high, decay: tom.decay * 0.85, stick: tom.stick, sr), 40),
            ("rim", synthRim(sr), 200),
            ("perc", synthPerc(sr), 200),
            ("crash", synthCrash(decay: crashDecay, sr), 300),
        ]
        var out: [String: SampleData] = [:]
        for (id, x, hp) in raw {
            let target = kickLoudness + (mix[id] ?? balance[id] ?? 0)
            out[id] = SampleData(left: finish(post(x), loudness: target, highpass: hp, sr), sampleRate: sr)
        }
        return out
    }

    // MARK: Finishing

    /// High-pass, trim the inaudible end, fade to exactly zero, and set the loudness.
    static func finish(_ x: [Float], loudness target: Double, highpass: Double, _ sr: Double, peakCap: Float = 0.944) -> [Float] {
        var hp = Biquad()
        hp.set(.highpass, freq: highpass, q: 0.6, sampleRate: sr)
        var y = x.map { hp.process($0) }
        let pk = peak(y)
        guard pk > 0 else { return y }
        // Stop once it stays 70 dB down; nobody hears that, and it saves voices.
        let floor = pk * 3.2e-4
        var last = y.count - 1
        while last > 0 && abs(y[last]) < floor { last -= 1 }
        let n = min(y.count, last + 1 + Int(0.002 * sr))
        y.removeLast(y.count - n)
        // Raised-cosine fade over the last fifth (4 ms to 300 ms) ends in exactly zero, so long tails
        // that are still sounding (an 808) never click or thump when the sample ends.
        let fade = min(n, max(Int(0.004 * sr), min(Int(0.3 * sr), n / 5)))
        for k in 0..<fade {
            let g = 0.5 + 0.5 * cos(Double.pi * Double(k + 1) / Double(fade))
            y[n - fade + k] *= Float(g)
        }
        var g = Float(pow(10, (target - loudness(y, sr)) / 20))
        let p = peak(y)
        guard p * g > peakCap else { return y.map { $0 * g } }
        // Too peaky to reach its loudness (claps and rims are mostly transient): limit up to 4 dB off
        // the peaks, like a mastered one-shot, and only turn the whole sound down past that.
        g = min(g, peakCap * 1.585 / p)
        return limit(y.map { $0 * g }, ceiling: peakCap, sr)
    }

    /// Look-ahead peak limiter: the gain dips just before each peak (1.5 ms ramp) and recovers over
    /// about 30 ms, so the result never passes `ceiling` and the transients don't crackle.
    static func limit(_ x: [Float], ceiling: Float, _ sr: Double) -> [Float] {
        let n = x.count
        guard n > 0 else { return x }
        var gain = x.map { abs($0) > ceiling ? ceiling / abs($0) : 1 }
        let ramp = 1 / Float(max(1, Int(0.0015 * sr)))
        for i in stride(from: n - 2, through: 0, by: -1) { gain[i] = min(gain[i], gain[i + 1] + ramp) }
        let release = Float(1 - exp(-1 / (0.03 * sr)))
        var g: Float = gain[0]
        for i in 0..<n {
            g = min(gain[i], g + (1 - g) * release)
            gain[i] = g
        }
        return zip(x, gain).map { $0 * $1 }
    }

    static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    /// K-weighted loudness of the loudest 100 ms (like a momentary LUFS reading, but shorter,
    /// which suits one-shots). Used to balance voices by ear rather than by peak.
    static func loudness(_ x: [Float], _ sr: Double) -> Double {
        var shelf = Biquad(), hp = Biquad()
        shelf.set(.highShelf, freq: 1681, q: 0.707, gainDb: 4, sampleRate: sr)
        hp.set(.highpass, freq: 38, q: 0.5, sampleRate: sr)
        let w = max(1, Int(0.1 * sr))
        var acc = 0.0, best = 0.0
        var ring = [Double](repeating: 0, count: w)
        for i in 0..<(x.count + w) {
            let v = i < x.count ? Double(hp.process(shelf.process(x[i]))) : 0
            let e = v * v
            acc += e - ring[i % w]
            ring[i % w] = e
            best = max(best, acc)
        }
        return -0.691 + 10 * log10(max(best / Double(w), 1e-12))
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

    /// tanh saturation with the level kept the same at full scale.
    static func saturate(_ x: [Float], _ drive: Float) -> [Float] {
        let k = 1 / tanhf(drive)
        return x.map { tanhf($0 * drive) * k }
    }

    static func crush(_ x: [Float], bits: Float, hold: Int) -> [Float] {
        let steps = powf(2, bits - 1)
        var h: Float = 0
        return x.enumerated().map { i, v in
            if i % hold == 0 { h = (v * steps).rounded() / steps }
            return h
        }
    }

    /// A tiny room: four all-pass filters in series smear a sound into a short, dense, darker tail.
    static func diffuse(_ x: [Float], _ sr: Double, mix: Float, extra: Double = 0.2) -> [Float] {
        var wet = x + [Float](repeating: 0, count: Int(extra * sr))
        for (d, g) in [(0.0043, 0.65), (0.0067, 0.62), (0.0109, 0.6), (0.0157, 0.58)] as [(Double, Float)] {
            let len = max(1, Int(d * sr))
            var buf = [Float](repeating: 0, count: len)
            var w = 0
            for i in wet.indices {
                let vd = buf[w]
                let v = wet[i] + g * vd
                wet[i] = vd - g * v
                buf[w] = v
                w += 1
                if w == len { w = 0 }
            }
        }
        var lp = OnePole()
        lp.setLowpass(6000, sampleRate: sr)
        return wet.enumerated().map { i, v in (i < x.count ? x[i] : 0) + lp.lowpass(v) * mix }
    }

    // MARK: Voices

    /// Kick: a sine whose phase starts at zero (so the very first sample is silent and the transient
    /// is clean), swept down by an exponential pitch envelope, with a short high chirp for the knock,
    /// saturated for weight, then a burst of band-passed noise for the beater.
    static func synthKick(_ k: KickSpec, _ sr: Double) -> [Float] {
        let n = Int(k.length * sr)
        var phase = 0.0
        let drive = Float(k.drive), norm = 1 / tanhf(drive)
        var tone = Biquad()
        tone.set(.lowpass, freq: k.tone, q: 0.707, sampleRate: sr)
        var y = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let base = k.end * (1 - k.glide * (1 - exp(-t / 0.35)))
            let f = base + (k.start - k.end) * exp(-t / k.pitchTau) + k.chirp * exp(-t / 0.0012)
            let env = t < k.hold ? 1 : exp(-(t - k.hold) / k.decay)
            let body = Float(sin(2 * .pi * phase) * env)
            phase += f / sr
            if phase >= 1 { phase -= 1 }
            y[i] = tone.process(tanhf(body * drive) * norm)
        }
        var rng = Rng(s: 1)
        var bp = Biquad(), hp = Biquad()
        bp.set(.bandpass, freq: k.clickFreq, q: 0.9, sampleRate: sr)
        hp.set(.highpass, freq: k.clickFreq * 0.4, q: 0.7, sampleRate: sr)
        for i in 0..<min(n, Int(0.02 * sr)) {
            let t = Double(i) / sr
            let e = Float(min(1, t / 0.0002) * exp(-t / 0.0025))
            y[i] += bp.process(hp.process(rng.next())) * k.click * e * 2
        }
        return y
    }

    /// Snare: the drum head's two lowest modes (and a faint third) with a small pitch drop, plus the
    /// wires: noise with its own snappy envelope, high-passed, with a presence band. Body and crack.
    static func synthSnare(_ s: SnareSpec, _ sr: Double) -> [Float] {
        let n = Int(s.length * sr)
        var rng = Rng(s: 3)
        var hp1 = Biquad(), hp2 = Biquad(), band = Biquad(), lp = Biquad()
        hp1.set(.highpass, freq: s.noiseHP, q: 0.707, sampleRate: sr)
        hp2.set(.highpass, freq: s.noiseHP, q: 0.707, sampleRate: sr)
        band.set(.peak, freq: s.noiseBand, q: 0.8, gainDb: 6, sampleRate: sr)
        lp.set(.lowpass, freq: s.noiseLP, q: 0.707, sampleRate: sr)
        let drive = Float(s.drive), norm = 1 / tanhf(drive)
        var p1 = 0.0, p2 = 0.0, p3 = 0.0
        var y = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let bend = 1 + s.bend * exp(-t / 0.012)
            let tone = sin(2 * .pi * p1) * exp(-t / s.toneDecay)
                + 0.85 * sin(2 * .pi * p2) * exp(-t / (s.toneDecay * 0.8))
                + 0.2 * sin(2 * .pi * p3) * exp(-t / (s.toneDecay * 0.4))
            p1 += s.f1 * bend / sr
            p2 += s.f2 * bend / sr
            p3 += s.f2 * 1.52 * bend / sr
            let nEnv = min(1, t / 0.0004) * (0.7 * exp(-t / s.noiseDecay) + 0.45 * exp(-t / 0.005))
            let nz = lp.process(band.process(hp2.process(hp1.process(rng.next()))))
            let v = Float(tone) * s.toneLevel + nz * s.noiseLevel * Float(nEnv) * 1.6
            y[i] = tanhf(v * drive) * norm
        }
        return s.room > 0 ? diffuse(y, sr, mix: s.room) : y
    }

    /// Clap: four bursts of band-passed noise about 10 ms apart (each "hand" a little different in
    /// timing, pitch, and level), then a smooth decaying tail, all through a tiny diffuser so it sounds
    /// like a room full of hands rather than a buzz.
    static func synthClap(_ c: ClapSpec, _ sr: Double) -> [Float] {
        let n = Int((c.tail * 6.5 + 0.05) * sr)
        var y = [Float](repeating: 0, count: n)
        let offsets = [0, 1.0, 2.15, 3.05].map { $0 * c.spacing }
        let gains: [Float] = [0.75, 0.9, 0.8, 1]
        let shifts = [1.0, 0.9, 1.12, 0.96]
        for b in 0..<4 {
            var rng = Rng(s: UInt32(101 + b * 7))
            var bp = Biquad(), air = Biquad()
            bp.set(.bandpass, freq: c.freq * shifts[b], q: 1.3, sampleRate: sr)
            air.set(.highpass, freq: 3500, q: 0.7, sampleRate: sr)
            let start = Int(offsets[b] * sr)
            for j in 0..<Int(0.03 * sr) where start + j < n {
                let t = Double(j) / sr
                let e = Float(min(1, t / 0.0003) * exp(-t / 0.0032))
                let w = rng.next()
                y[start + j] += (bp.process(w) + air.process(w) * 0.12) * e * gains[b]
            }
        }
        var rng = Rng(s: 5)
        var bp = Biquad()
        bp.set(.bandpass, freq: c.freq, q: 1, sampleRate: sr)
        let t0 = offsets[3]
        for i in Int(t0 * sr)..<n {
            let t = Double(i) / sr - t0
            let e = Float(min(1, t / 0.002) * exp(-t / c.tail))
            y[i] += bp.process(rng.next()) * e * 0.5
        }
        return saturate(diffuse(y, sr, mix: c.room), 2.2)
    }

    /// Hats: six band-limited 808-style square waves (no aliasing fizz) plus noise, high-passed twice,
    /// with a presence band and a gentle top cut so they shimmer instead of hiss. `decay` is the time
    /// constant; the stick hit up front gives the closed hat its tick.
    static func synthHat(decay: Double, _ h: HatSpec, _ sr: Double, seed: UInt32) -> [Float] {
        let n = Int((decay * 7 + 0.01) * sr)
        var rng = Rng(s: seed)
        let freqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].map { $0 * 1.7 }
        var phases = [Double](repeating: 0, count: 6)
        var h1 = Biquad(), h2 = Biquad(), band = Biquad(), lp = Biquad()
        h1.set(.highpass, freq: h.hp, q: 0.7, sampleRate: sr)
        h2.set(.highpass, freq: h.hp, q: 0.7, sampleRate: sr)
        band.set(.peak, freq: h.band, q: 1, gainDb: 6, sampleRate: sr)
        lp.set(.lowpass, freq: h.lp, q: 0.707, sampleRate: sr)
        var y = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            var m: Double = 0
            for j in 0..<6 {
                let dt = freqs[j] / sr
                m += oscillator(3, phases[j], dt)
                phases[j] += dt
                if phases[j] >= 1 { phases[j] -= 1 }
            }
            let src = Float(m / 6) * h.metal + rng.next() * (1 - h.metal * 0.5)
            let env = Float(min(1, exp(-t / decay) + 0.35 * exp(-t / 0.005)) * min(1, t / 0.0003))
            y[i] = lp.process(band.process(h2.process(h1.process(src)))) * env
        }
        return y
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

    /// Tom: a tuned sine that drops from half an octave sharp, a faint second head mode that dies
    /// quickly, and a stick hit, lightly saturated.
    static func synthTom(freq: Double, decay: Double, stick: Float, _ sr: Double) -> [Float] {
        let n = Int(decay * 6 * sr)
        var rng = Rng(s: 11)
        var bp = Biquad()
        bp.set(.bandpass, freq: 2500, q: 0.8, sampleRate: sr)
        var p1 = 0.0, p2 = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sr
            let f = freq * (1 + 0.45 * exp(-t / 0.035))
            let body = sin(2 * .pi * p1) * exp(-t / decay) + 0.15 * sin(2 * .pi * p2) * exp(-t / (decay * 0.3))
            p1 += f / sr
            p2 += f * 1.58 / sr
            let hit = bp.process(rng.next()) * stick * Float(min(1, t / 0.0003) * exp(-t / 0.004)) * 2
            return tanhf((Float(body) + hit) * 1.4) / tanhf(1.4)
        }
    }

    /// Rim: three short tuned pings (around 470 Hz, 1.7 kHz, and 3.4 kHz) and a click, clipped a
    /// little, like the 808's rim shot.
    static func synthRim(_ sr: Double) -> [Float] {
        let n = Int(0.08 * sr)
        var rng = Rng(s: 17)
        var air = Biquad(), hp = Biquad()
        air.set(.highpass, freq: 3000, q: 0.7, sampleRate: sr)
        hp.set(.highpass, freq: 300, q: 0.7, sampleRate: sr)
        let k: Float = 2.2, norm = 1 / tanhf(2.2)
        return (0..<n).map { i in
            let t = Double(i) / sr
            let w = 2 * Double.pi * t
            let tone = 0.55 * sin(w * 470) * exp(-t / 0.009) + sin(w * 1680) * exp(-t / 0.0055) + 0.35 * sin(w * 3350) * exp(-t / 0.003)
            let click = air.process(rng.next()) * 0.6 * Float(min(1, t / 0.0002) * exp(-t / 0.0012))
            return hp.process(tanhf((Float(tone) + click) * k) * norm)
        }
    }

    /// Perc: the 808 cowbell, two band-limited squares at 540 and 800 Hz through a band-pass, with a
    /// sharp strike that settles into a shorter ring.
    static func synthPerc(_ sr: Double) -> [Float] {
        let n = Int(0.6 * sr)
        var bp = Biquad(), lp = Biquad()
        bp.set(.bandpass, freq: 900, q: 1.1, sampleRate: sr)
        lp.set(.lowpass, freq: 7000, q: 0.707, sampleRate: sr)
        var p1 = 0.0, p2 = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sr
            let s = oscillator(3, p1, 540 / sr) + oscillator(3, p2, 800 / sr)
            p1 += 540 / sr; if p1 >= 1 { p1 -= 1 }
            p2 += 800 / sr; if p2 >= 1 { p2 -= 1 }
            let env = min(1, t / 0.0004) * (0.62 * exp(-t / 0.085) + 0.38 * exp(-t / 0.012))
            return lp.process(bp.process(Float(s * env)))
        }
    }
}
