import XCTest
@testable import ShawCore

/// Measured checks on how the drum kits sound, since a test can't listen.
final class DrumSoundTests: XCTestCase {
    let sr = 48000.0
    typealias A = AudioAnalysis

    static var cache: [String: [String: [Float]]] = [:]

    func samples(_ kit: String) -> [String: [Float]] {
        if let c = Self.cache[kit] { return c }
        let s = DrumKits.generate(kit: kit, sampleRate: sr).mapValues { Array(UnsafeBufferPointer(start: $0.l, count: $0.frames)) }
        Self.cache[kit] = s
        return s
    }

    /// Every voice starts and ends silently, has no DC offset, and never clips.
    func testEveryVoiceIsClean() {
        for kit in DrumKits.kits {
            for v in DrumKits.voices {
                let x = samples(kit.id)[v.id]!
                let pk = A.peak(x), name = "\(kit.id) \(v.id)"
                XCTAssertLessThan(pk, 0.95, "\(name) clips")
                XCTAssertGreaterThan(pk, 0.05, "\(name) is nearly silent")
                XCTAssertLessThan(abs(x[0]), pk * 0.05, "\(name) starts with a click")
                XCTAssertEqual(x.last!, 0, accuracy: 1e-6, "\(name) ends abruptly")
                XCTAssertLessThan(abs(A.mean(x)), Double(pk) * 0.002, "\(name) has DC offset")
            }
        }
    }

    /// Voices sit together by loudness like a mixed kit: snare and clap near the kick, hats well under it.
    /// A recorded kit gets more room: its hits are only limited a little, so the peakiest come out quieter.
    func testKitBalance() {
        for kit in DrumKits.kits {
            let s = samples(kit.id)
            let recorded = DrumKits.recordedKits[kit.id] != nil
            let kick = DrumKits.loudness(s["kick"]!, sr)
            XCTAssertEqual(kick, DrumKits.kickLoudness, accuracy: recorded ? 2.5 : 1.5, "\(kit.id) kick loudness")
            for id in ["snare", "clap"] {
                XCTAssertEqual(DrumKits.loudness(s[id]!, sr), kick, accuracy: recorded ? 7.5 : 4, "\(kit.id) \(id) against the kick")
            }
            for id in ["chat", "ohat", "crash"] {
                let l = DrumKits.loudness(s[id]!, sr)
                XCTAssertLessThan(l, kick - 5, "\(kit.id) \(id) too loud")
                XCTAssertGreaterThan(l, kick - 14, "\(kit.id) \(id) too quiet")
            }
        }
    }

    /// The synthesized kits. Their recipes are checked below; the Acoustic Kit is a recording of a
    /// real kit, so it only has to be clean and balanced.
    var synthesizedKits: [DrumKitInfo] { DrumKits.kits.filter { DrumKits.recordedKits[$0.id] == nil } }

    /// Kicks: weight under 100 Hz, a pitch that drops onto a tuned note, and (909 style) a click above 2 kHz.
    func testKicks() {
        for kit in synthesizedKits {
            let x = samples(kit.id)["kick"]!
            let spec = A.powerSpectrum(x, window: false)
            XCTAssertGreaterThan(A.bandFraction(spec, sr, 20, 100), 0.75, "\(kit.id) kick weight")
            let early = A.zeroCrossingHz(x, sr, Int(0.012 * sr), Int(0.03 * sr), lowpass: 400)
            let late = A.zeroCrossingHz(x, sr, Int(0.25 * sr), Int(0.45 * sr), lowpass: 400)
            XCTAssertGreaterThan(early, late * 1.4, "\(kit.id) kick pitch drop")
            XCTAssert((38...62).contains(late), "\(kit.id) kick tuned to \(late) Hz")
        }
        for kit in ["house", "techno"] {
            XCTAssertGreaterThan(highTransientDb(samples(kit)["kick"]!, 2000), -12, "\(kit) kick click")
        }
    }

    /// Snares: two tuned head modes for body plus a noise layer above 2 kHz for crack.
    func testSnares() {
        for kit in synthesizedKits {
            let x = samples(kit.id)["snare"]!
            let spec = A.powerSpectrum(x, window: false)
            let modes = A.peaks(spec, sr, count: 3, from: 120, to: 500).map(\.0)
            XCTAssert(modes.contains { (160...250).contains($0) }, "\(kit.id) snare first mode: \(modes)")
            XCTAssert(modes.contains { (280...450).contains($0) }, "\(kit.id) snare second mode: \(modes)")
            XCTAssertGreaterThan(A.bandFraction(spec, sr, 100, 500), 0.12, "\(kit.id) snare body")
            XCTAssertGreaterThan(A.bandFraction(spec, sr, 2000, 20000), kit.id == "lofi" ? 0.1 : 0.3, "\(kit.id) snare crack")
        }
    }

    /// Claps: several separate bursts in the first 35 ms (many hands), not one smooth blob.
    func testClapsFlam() {
        for kit in synthesizedKits {
            let x = samples(kit.id)["clap"]!
            let step = Int(0.001 * sr)
            let env = (0..<40).map { A.rms(x, $0 * step, ($0 + 1) * step) }
            let top = env.max()!
            var bursts = 0
            for k in 1..<39 where env[k] > env[k - 1] && env[k] >= env[k + 1] && env[k] > top * 0.3 { bursts += 1 }
            XCTAssertGreaterThanOrEqual(bursts, 3, "\(kit.id) clap bursts")
        }
    }

    /// The closed hat is short; the open hat rings for about half a second.
    func testHatLengths() {
        for kit in synthesizedKits {
            let s = samples(kit.id)
            let closed = A.decayTime(s["chat"]!, sr, db: -40), open = A.decayTime(s["ohat"]!, sr, db: -40)
            XCTAssert((0.05...0.25).contains(closed), "\(kit.id) closed hat lasts \(closed) s")
            XCTAssert((0.3...0.7).contains(open), "\(kit.id) open hat lasts \(open) s")
        }
    }

    /// Peak of the part above `f` Hz in the first 15 ms, relative to the whole sound's peak.
    func highTransientDb(_ x: [Float], _ f: Double) -> Double {
        var h1 = Biquad(), h2 = Biquad()
        h1.set(.highpass, freq: f, q: 0.707, sampleRate: sr)
        h2.set(.highpass, freq: f, q: 0.707, sampleRate: sr)
        let y = x.prefix(Int(0.015 * sr)).map { h2.process(h1.process($0)) }
        return A.db(Double(A.peak(Array(y))) / Double(A.peak(x)))
    }
}

/// Measured checks on the synth's sound quality.
final class SynthSoundTests: XCTestCase {
    let sr = 48000.0
    typealias A = AudioAnalysis

    /// Parameters are stored by position, so new ones only ever go at the end.
    func testParameterOrderIsStable() {
        let ids = ["osc1", "osc2", "semi2", "fine2", "mix", "sub", "noise", "unison", "spread", "cutoff", "resonance", "fenv",
                   "keytrack", "a", "d", "s", "r", "fa", "fd", "fs", "fr", "penv", "pdecay", "mode", "glide", "drive", "volume",
                   "osclevel", "lforate", "lfosync", "lfocut", "lfopitch", "lfoamp", "ftype", "fm", "lfoshape", "lfofm", "drift",
                   "semi1", "lvl1", "lvl2", "on2", "osc3", "semi3", "fine3", "lvl3", "on3", "osc4", "semi4", "fine4", "lvl4", "on4",
                   "fmenv", "fmdecay"]
        XCTAssertEqual(SynthParams.defs.map(\.id), ids)
        XCTAssertEqual(SynthParams.index["fmenv"], SynthParams.fmEnv)
        XCTAssertEqual(SynthParams.index["fmdecay"], SynthParams.fmDecay)
        XCTAssertEqual(SynthParams.defs[SynthParams.fmEnv].defaultValue, 0)
    }

    /// Sounds saved before the FM envelope existed don't have it, and render exactly as with it off.
    func testFMEnvelopeDefaultsOff() {
        var p = SynthPresets.params(for: "Digi Bell")
        p["drift"] = 0
        p.removeValue(forKey: "fmenv"); p.removeValue(forKey: "fmdecay")
        var q = p
        q["fmenv"] = 0; q["fmdecay"] = 3
        XCTAssertEqual(Synth.renderNote(p, note: 72, hold: 0.3).l, Synth.renderNote(q, note: 72, hold: 0.3).l)
    }

    /// Energy above the second harmonic relative to the fundamental, in a 40 ms window at `t`.
    func brightness(_ x: [Float], f0: Double, at t: Double) -> Double {
        let spec = A.powerSpectrum(x, start: Int(t * sr), length: 1920, size: 16384)
        let hz = A.binHz(spec, sr)
        func band(_ a: Double, _ b: Double) -> Double { spec.indices.filter { Double($0) * hz >= a && Double($0) * hz < b }.map { spec[$0] }.reduce(0, +) }
        return band(f0 * 2.5, 8000) / max(band(f0 * 0.5, f0 * 1.5), 1e-20)
    }

    /// An FM piano starts bright and settles mellow, and harder notes start brighter.
    func testFMEnvelopeBrightensTheAttack() {
        var p = SynthPresets.params(for: "Electric Piano")
        p["drift"] = 0; p["lfoamp"] = 0
        let f0 = 261.6
        let hard = Synth.renderNote(p, note: 60, velocity: 1, hold: 1.2).l
        let soft = Synth.renderNote(p, note: 60, velocity: 0.3, hold: 1.2).l
        XCTAssertGreaterThan(brightness(hard, f0: f0, at: 0.01), brightness(hard, f0: f0, at: 1.0) * 30)
        XCTAssertGreaterThan(brightness(hard, f0: f0, at: 0.01), brightness(soft, f0: f0, at: 0.01) * 2)
    }

    func clean(_ extra: [String: Double]) -> [String: Double] {
        var p = SynthPresets.scratch()
        for (k, v) in ["drift": 0, "cutoff": 20000, "fenv": 0, "keytrack": 0, "a": 0.001, "s": 1] as [String: Double] { p[k] = v }
        for (k, v) in extra { p[k] = v }
        return p
    }

    /// Band-limited oscillators: little energy between the harmonics, even at C7.
    func testOscillatorsDontAlias() {
        let f0 = 440 * pow(2, Double(96 - 69) / 12)
        for (wave, limit) in [(2, -44.0), (3, -44.0), (1, -50.0)] {
            let x = Synth.renderNote(clean(["osc1": Double(wave)]), note: 96, hold: 1).l
            XCTAssertLessThan(A.inharmonicDb(x, sr, f0: f0, start: 4800), limit, "wave \(wave) aliases")
        }
    }

    /// FM on a very high note keeps its sidebands under Nyquist instead of folding back.
    func testHighFMDoesNotAlias() {
        let p = clean(["osc1": 0, "on2": 1, "osc2": 0, "semi2": 12, "fine2": 0, "mix": 0, "fm": 0.2])
        let x = Synth.renderNote(p, note: 103, hold: 1).l
        XCTAssertLessThan(A.inharmonicDb(x, sr, f0: 440 * pow(2, Double(103 - 69) / 12), start: 4800), -30)
    }

    /// The resonance limiter changes nothing at normal levels and rounds off a screaming peak.
    func testResonanceLimit() {
        func run(_ cutoff: Float, _ res: Float, limited: Bool) -> [Float] {
            var f = SVF()
            f.set(cutoff: cutoff, resonance: res, sampleRate: Float(sr))
            var ph = 0.0
            return (0..<24000).map { _ in
                let x = Float(oscillator(2, ph, 130.8 / sr)) * 0.5
                ph += 130.8 / sr; if ph >= 1 { ph -= 1 }
                return limited ? f.processLimited(x).0 : f.process(x).0
            }
        }
        XCTAssertEqual(run(1000, 0.6, limited: true), run(1000, 0.6, limited: false))
        XCTAssertLessThan(A.peak(run(130.8, 1, limited: true)), A.peak(run(130.8, 1, limited: false)) * 0.7)
    }

    /// Seven-voice unison is as loud as one voice: the center is louder and the sides quieter, normalized.
    func testUnisonKeepsLevel() {
        func mono(_ p: [String: Double]) -> [Float] {
            let (l, r) = Synth.renderNote(p, note: 60, hold: 1)
            return zip(l, r).map { ($0 + $1) * 0.5 }
        }
        let one = mono(clean(["osc1": 2])), seven = mono(clean(["osc1": 2, "unison": 3, "spread": 0.5]))
        XCTAssertEqual(A.db(A.rms(seven, 4800)), A.db(A.rms(one, 4800)), accuracy: 1.5)
    }
}
