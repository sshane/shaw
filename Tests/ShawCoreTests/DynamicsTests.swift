import AVFoundation
import XCTest
@testable import ShawCore

/// Measurement helpers shared by the Limiter, Compressor, and Saturator tests.
enum Measure {
    static let sr = 48000.0

    /// Runs a stereo signal through an effect in blocks, like the engine does.
    static func run(_ fx: EffectProcessor, _ params: [Double], _ l: [Float], _ r: [Float]? = nil,
                    block: Int = 512) -> ([Float], [Float]) {
        let r = r ?? l
        let buf = StereoBuffer()
        let ctx = RenderContext(sampleRate: sr, bpm: 120)
        var outL = [Float](repeating: 0, count: l.count), outR = outL
        var done = 0
        while done < l.count {
            let n = min(block, l.count - done)
            for i in 0..<n { buf.l[i] = l[done + i]; buf.r[i] = r[done + i] }
            fx.process(buf, frames: n, params: params, ctx: ctx, beat: 0)
            for i in 0..<n { outL[done + i] = buf.l[i]; outR[done + i] = buf.r[i] }
            done += n
        }
        return (outL, outR)
    }

    static func sine(_ freq: Double, amp: Double, seconds: Double, phase: Double = 0) -> [Float] {
        (0..<Int(seconds * sr)).map { Float(amp * sin(2 * .pi * freq * Double($0) / sr + phase)) }
    }

    /// Amplitude of the component at `freq` over `x` (x should hold whole periods).
    static func amplitude(_ x: ArraySlice<Float>, _ freq: Double) -> Double {
        var re = 0.0, im = 0.0
        let w = 2 * Double.pi * freq / sr
        for (k, v) in x.enumerated() {
            re += Double(v) * cos(w * Double(k))
            im -= Double(v) * sin(w * Double(k))
        }
        return 2 * (re * re + im * im).squareRoot() / Double(x.count)
    }

    /// Total harmonic distortion in dB (harmonics 2 to 20 against the fundamental).
    static func thd(_ x: ArraySlice<Float>, _ f0: Double) -> Double {
        let a1 = amplitude(x, f0)
        var h = 0.0
        for k in 2...20 where Double(k) * f0 < sr / 2 { h += pow(amplitude(x, Double(k) * f0), 2) }
        return 10 * log10(max(h, 1e-30) / (a1 * a1))
    }

    static func rmsDB(_ x: ArraySlice<Float>) -> Double {
        let s = x.reduce(0.0) { $0 + Double($1) * Double($1) }
        return 10 * log10(max(s / Double(x.count), 1e-30))
    }

    static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    /// Reference true peak: 8x oversampling with a long (64-tap) Kaiser-windowed sinc, far more
    /// accurate than the limiter's own 16-tap estimate.
    static func truePeak(_ x: [Float]) -> Float {
        let half = 32, phases = 8
        let taps = TruePeakTaps.make(taps: half * 2, phases: phases, beta: 9)
        var pk = peak(x)
        if x.count <= 2 * half { return pk }
        for n in (2 * half - 1)..<x.count {
            for h in taps {
                var acc: Float = 0
                for j in 0..<(2 * half) { acc += h[j] * x[n - j] }
                pk = max(pk, abs(acc))
            }
        }
        return pk
    }

    static func db(_ g: Float) -> Double { 20 * log10(Double(max(g, 1e-12))) }

    /// Seeded noise so failures reproduce.
    struct Noise {
        var state: UInt64
        init(_ seed: UInt64) { state = seed }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state >> 11) & 0xFFFFF) / Float(0x7FFFF) - 1
        }
    }

    /// Kick, snare, and hats with sharp attacks, four beats at 128 bpm.
    static func drums(seconds: Double, seed: UInt64 = 7) -> [Float] {
        var noise = Noise(seed)
        let n = Int(seconds * sr)
        var out = [Float](repeating: 0, count: n)
        let beat = Int(sr * 60 / 128)
        var hpState: Float = 0
        for i in 0..<n {
            let tb = i % beat, t = Double(tb) / sr
            let b = (i / beat) % 4
            // Kick: a falling sine sweep with a 1 ms click.
            let ph = 2 * Double.pi * (50 * t + 150 * 0.03 * (1 - exp(-t / 0.03)))
            var v = Float(sin(ph) * exp(-t / 0.25))
            if t < 0.001 { v += noise.next() * 0.5 }
            // Snare on 2 and 4.
            if b % 2 == 1 { v += noise.next() * Float(exp(-t / 0.08)) * 0.8 + Float(sin(2 * .pi * 190 * t) * exp(-t / 0.05)) * 0.5 }
            // Hats on the eighths (high-passed noise).
            let te = Double(i % (beat / 2)) / sr
            let w = noise.next()
            hpState += (w - hpState) * 0.3
            v += (w - hpState) * Float(exp(-te / 0.02)) * 0.4
            out[i] = v * 0.7
        }
        return out
    }
}

// MARK: - Limiter

final class LimiterTests: XCTestCase {
    let sr = Measure.sr

    func params(gain: Double = 0, ceiling: Double = -0.3, release: Double = 80) -> [Double] {
        LimiterFX.params.resolve(["gain": gain, "ceiling": ceiling, "release": release])
    }

    /// Checks sample peak, true peak, and that the last-resort clip never had to act.
    func assertHolds(_ name: String, _ l: [Float], _ r: [Float]? = nil, gain: Double, ceiling: Double = -0.3,
                     release: Double = 80, file: StaticString = #filePath, line: UInt = #line) {
        let fx = LimiterFX(sampleRate: sr)
        let (ol, or) = Measure.run(fx, params(gain: gain, ceiling: ceiling, release: release), l, r)
        let ceil = Float(dbToGain(ceiling))
        let sp = max(Measure.peak(ol), Measure.peak(or))
        let tp = max(Measure.truePeak(ol), Measure.truePeak(or))
        let old = LegacyLimiterFX(sampleRate: sr)
        let (xl, xr) = Measure.run(old, params(gain: gain, ceiling: ceiling, release: release), l, r)
        let oldTP = max(Measure.truePeak(xl), Measure.truePeak(xr))
        let pre = Float(dbToGain(gain))
        let oldClipped = zip(xl, l).filter { abs($1 * pre) > ceil && abs($0) >= ceil * 0.9999 }.count
        print(String(format: "LIMITER %@: sample peak %.3f dB, true peak %.3f dB (old %.3f dB), ceiling %.1f, safety clips %d (old hard-clipped %d samples)",
                     name, Measure.db(sp), Measure.db(tp), Measure.db(oldTP), ceiling, fx.safetyClips, oldClipped))
        XCTAssertLessThanOrEqual(sp, ceil * 1.00001, "\(name): sample peak over the ceiling", file: file, line: line)
        XCTAssertLessThan(Measure.db(tp), ceiling + 0.3, "\(name): true peak over the ceiling", file: file, line: line)
        XCTAssertEqual(fx.safetyClips, 0, "\(name): the safety clip had to act", file: file, line: line)
        for v in ol + or { XCTAssert(v.isFinite, file: file, line: line) }
    }

    func testFullScaleBurstsStayUnderTheCeiling() {
        var noise = Measure.Noise(1)
        let n = Int(sr * 1.0)
        var l = [Float](repeating: 0, count: n), r = l
        for i in 0..<n {
            let on = (i / Int(sr * 0.05)) % 2 == 0
            // Alternate full-scale noise bursts and full-scale square bursts.
            let sq: Float = (i / 37) % 2 == 0 ? 1 : -1
            l[i] = on ? noise.next() : sq
            r[i] = on ? noise.next() : -sq
        }
        assertHolds("full-scale bursts +12 dB", l, r, gain: 12)
        assertHolds("full-scale bursts 0 dB, -1 ceiling", l, r, gain: 0, ceiling: -1)
    }

    func testLoudBassStaysUnderTheCeiling() {
        let x = Measure.sine(40, amp: 0.9, seconds: 1)
        assertHolds("40 Hz sine +12 dB", x, gain: 12)
        assertHolds("40 Hz sine +12 dB fast release", x, gain: 12, release: 10)
    }

    func testDrumTransientsStayUnderTheCeiling() {
        let d = Measure.drums(seconds: 1.2)
        assertHolds("drums +12 dB", d, gain: 12)
        assertHolds("drums +6 dB, -3 ceiling", d, gain: 6, ceiling: -3, release: 30)
    }

    /// A 12 kHz sine at 45 degrees samples at 0.707 of its real peak: only a true-peak limiter sees it.
    func testInterSamplePeaksAreCaught() {
        let x = Measure.sine(12000, amp: 1.2, seconds: 0.5, phase: .pi / 4)
        XCTAssertLessThan(Measure.peak(x), Float(dbToGain(-0.3)), "the samples alone are under the ceiling")
        assertHolds("12 kHz inter-sample peaks", x, gain: 0)
    }

    /// 6 dB of gain reduction on a steady 100 Hz sine: the gain should hold still (low THD).
    func testSteadyBassIsNotDistorted() {
        let ceil = dbToGain(-0.3)
        for (freq, release) in [(100.0, 80.0), (40.0, 80.0), (100.0, 60.0)] {
            let x = Measure.sine(freq, amp: 2 * ceil, seconds: 1.5)
            let p = params(release: release)
            let (new, _) = Measure.run(LimiterFX(sampleRate: sr), p, x)
            let (old, _) = Measure.run(LegacyLimiterFX(sampleRate: sr), p, x)
            let span = (new.count - 24000)..<new.count
            let thdNew = Measure.thd(new[span], freq), thdOld = Measure.thd(old[span], freq)
            let grNew = Measure.db(Float(Measure.amplitude(new[span], freq))) - Measure.db(Float(2 * ceil))
            print(String(format: "LIMITER THD %.0f Hz, 6 dB GR, release %.0f: new %.1f dB (%.4f%%), old %.1f dB (%.2f%%); new GR %.2f dB",
                         freq, release, thdNew, 100 * pow(10, thdNew / 20), thdOld, 100 * pow(10, thdOld / 20), grNew))
            XCTAssertLessThan(thdNew, -70, "\(freq) Hz should come through nearly undistorted")
            XCTAssertLessThan(thdNew, thdOld - 30, "much cleaner than before")
        }
        // Fast releases trade some of that for loudness, but still beat the old limiter.
        for release in [10.0, 30.0] {
            let x = Measure.sine(40, amp: 2 * ceil, seconds: 1.5)
            let p = params(release: release)
            let (new, _) = Measure.run(LimiterFX(sampleRate: sr), p, x)
            let (old, _) = Measure.run(LegacyLimiterFX(sampleRate: sr), p, x)
            let span = (new.count - 24000)..<new.count
            let thdNew = Measure.thd(new[span], 40), thdOld = Measure.thd(old[span], 40)
            print(String(format: "LIMITER THD 40 Hz, 6 dB GR, release %.0f: new %.1f dB (%.3f%%), old %.1f dB (%.2f%%)",
                         release, thdNew, 100 * pow(10, thdNew / 20), thdOld, 100 * pow(10, thdOld / 20)))
            XCTAssertLessThan(thdNew, thdOld - 6)
        }
    }

    /// Under the ceiling, the limiter is a pure delay.
    func testQuietSignalPassesUnchanged() {
        let fx = LimiterFX(sampleRate: sr)
        let x = Measure.drums(seconds: 0.5).map { $0 * 0.3 }
        XCTAssertLessThan(Measure.truePeak(x), Float(dbToGain(-0.3)))
        let (out, _) = Measure.run(fx, params(), x)
        let d = fx.latency
        XCTAssertLessThanOrEqual(Double(d) / sr, 0.005, "lookahead stays at 5 ms or less")
        var err: Float = 0
        for i in d..<x.count { err = max(err, abs(out[i] - x[i - d])) }
        XCTAssertLessThan(err, 1e-6)
    }

    func testGainKnobRaisesLevelLikeBefore() {
        let x = Measure.drums(seconds: 1.5)
        for gain in [3.0, 6.0] {
            let p = params(gain: gain)
            let (new, _) = Measure.run(LimiterFX(sampleRate: sr), p, x)
            let (old, _) = Measure.run(LegacyLimiterFX(sampleRate: sr), p, x)
            let rn = Measure.rmsDB(new[4800...]), ro = Measure.rmsDB(old[4800...])
            print(String(format: "LIMITER level, drums +%.0f dB: new %.2f dB RMS, old %.2f dB RMS", gain, rn, ro))
            // The old limiter was louder by hard-clipping the hits; a clean limiter gives a bit of that up.
            XCTAssertEqual(rn, ro, accuracy: 3)
        }
    }

    /// After a loud stretch the gain comes back to unity: a quiet tone afterwards is untouched.
    func testReleaseRecovers() {
        var x = Measure.drums(seconds: 0.5)
        x += Measure.sine(1000, amp: 0.1, seconds: 2.5)
        let fx = LimiterFX(sampleRate: sr)
        let (out, _) = Measure.run(fx, params(gain: 12), x)
        let d = fx.latency
        // From 1.5 s after the drums stop, the tone is back to full level (no long tail).
        let w = (x.count - 48000)..<x.count
        let expected = Measure.rmsDB(x[(w.lowerBound - d)..<(w.upperBound - d)]) + 12
        let got = Measure.rmsDB(out[w])
        print(String(format: "LIMITER release: tone after drums %.2f dB (expected %.2f)", got, expected))
        XCTAssertEqual(got, expected, accuracy: 0.1)
    }

    /// Export drops the master limiter's lookahead, so a kick on beat 1 starts the file.
    func testExportStartsOnTheBeat() throws {
        var p = Project()
        var drums = DrumPattern(steps: 4, stepsPerBeat: 4)
        drums.rows[0].steps[0] = 1
        let beat = Asset(name: "Beat", colorIndex: 1, content: .drums(drums))
        p.assets.append(beat)
        p.updateComposition(p.mainCompositionID) { c in
            var t = Track(name: "Drums", colorIndex: 1)
            t.clips = [Clip(assetID: beat.id, start: 0, length: 1)]
            c.tracks = [t]
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("kick.wav")
        try OfflineRenderer.export(project: p, composition: p.mainCompositionID, to: url, tailSeconds: 0.5)
        let file = try AVAudioFile(forReading: url)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: pcm)
        let x = Array(UnsafeBufferPointer(start: pcm.floatChannelData![0], count: Int(pcm.frameLength)))
        let (direct, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 1)
        let first = { (y: [Float]) in y.firstIndex { abs($0) > 1e-3 } ?? -1 }
        XCTAssertEqual(first(x), first(direct), "the export lines up with the song, not 4 ms late")
    }

    func testSilenceAndGarbageStayFinite() {
        let fx = LimiterFX(sampleRate: sr)
        var x = [Float](repeating: 0, count: 4800)
        x[100] = .nan; x[200] = .infinity; x[300] = -.infinity; x[400] = 1e30
        let (out, _) = Measure.run(fx, params(gain: 24), x)
        for v in out { XCTAssert(v.isFinite) }
        let (silent, _) = Measure.run(LimiterFX(sampleRate: sr), params(gain: 24), [Float](repeating: 0, count: 4800))
        XCTAssertEqual(Measure.peak(silent), 0)
    }
}

// MARK: - Compressor

final class CompressorTests: XCTestCase {
    let sr = Measure.sr

    func params(_ v: [String: Double]) -> [Double] { CompressorFX.params.resolve(v) }

    /// Output level of a steady 1 kHz tone at `inDB` RMS, measured after it settles.
    func steady(_ inDB: Double, _ v: [String: Double], fx: EffectProcessor? = nil) -> Double {
        let x = Measure.sine(1000, amp: dbToGain(inDB) * 2.0.squareRoot(), seconds: 1)
        let (out, _) = Measure.run(fx ?? CompressorFX(sampleRate: sr), params(v), x)
        return Measure.rmsDB(out[24000...])
    }

    func testGainReductionMatchesRatioAndThreshold() {
        let cases: [(inDB: Double, th: Double, ratio: Double, expected: Double)] = [
            (-6, -18, 4, -6 - 12 * 0.75),
            (-6, -30, 2, -6 - 24 * 0.5),
            (-6, -20, 20, -6 - 14 * 0.95),
            (-12, -18, 4, -12 - 6 * 0.75),
            (-30, -18, 4, -30),                     // under the threshold (and its knee)
            (-18, -18, 4, -18 - 0.75 * 9.0 / 12),   // right at the threshold: half the knee
        ]
        for c in cases {
            let out = steady(c.inDB, ["threshold": c.th, "ratio": c.ratio, "attack": 10, "release": 120])
            print(String(format: "COMPRESSOR tone %.0f dB, threshold %.0f, ratio %.0f: out %.2f dB (expected %.2f)",
                         c.inDB, c.th, c.ratio, out, c.expected))
            XCTAssertEqual(out, c.expected, accuracy: 0.25)
        }
    }

    func testMakeupAndParallelMixStayInPhase() {
        let v: [String: Double] = ["threshold": -18, "ratio": 4, "makeup": 6]
        XCTAssertEqual(steady(-6, v), -6 - 9 + 6, accuracy: 0.25)
        // 50% wet: a plain blend of the dry tone and the compressed tone, no comb filtering.
        let x = Measure.sine(1000, amp: dbToGain(-6) * 2.0.squareRoot(), seconds: 1)
        let (out, _) = Measure.run(CompressorFX(sampleRate: sr), params(["threshold": -18, "ratio": 4, "mix": 0.5]), x)
        let g = dbToGain(-9)
        let expected = -6 + 20 * log10(0.5 + 0.5 * g)
        XCTAssertEqual(Measure.rmsDB(out[24000...]), expected, accuracy: 0.25)
        // Same shape as the input: the ratio of output to input is constant.
        let k = Double(out[30000]) / Double(x[30000])
        var worst = 0.0
        for i in 30000..<30480 where abs(x[i]) > 0.1 { worst = max(worst, abs(Double(out[i]) / Double(x[i]) - k)) }
        XCTAssertLessThan(worst, 0.01)
    }

    /// Compressing a 40 Hz bass note: the old detector pulled the gain at audio rate.
    func testBassIsNotDistorted() {
        for (attack, release) in [(10.0, 120.0), (30.0, 150.0), (3.0, 60.0)] {
            let x = Measure.sine(40, amp: dbToGain(-6) * 2.0.squareRoot(), seconds: 2)
            let p = params(["threshold": -18, "ratio": 4, "attack": attack, "release": release])
            let (new, _) = Measure.run(CompressorFX(sampleRate: sr), p, x)
            let (old, _) = Measure.run(LegacyCompressorFX(sampleRate: sr), p, x)
            let span = (new.count - 48000)..<new.count
            let tn = Measure.thd(new[span], 40), to = Measure.thd(old[span], 40)
            print(String(format: "COMPRESSOR THD 40 Hz, attack %.0f release %.0f: new %.1f dB (%.3f%%), old %.1f dB (%.2f%%)",
                         attack, release, tn, 100 * pow(10, tn / 20), to, 100 * pow(10, to / 20)))
            XCTAssertLessThan(tn, -60)
            XCTAssertLessThan(tn, to - 20)
        }
    }

    /// From silence, a fast attack has to catch the very first hit.
    func testFastAttackCatchesTransientsFromSilence() {
        var x = [Float](repeating: 0, count: Int(sr * 0.5))
        let start = Int(sr * 0.25)
        for i in start..<x.count { x[i] = Float(sin(2 * .pi * 1000 * Double(i - start) / sr) * dbToGain(-6) * 2.0.squareRoot()) }
        let p = params(["threshold": -18, "ratio": 4, "attack": 1, "release": 100])
        let (new, _) = Measure.run(CompressorFX(sampleRate: sr), p, x)
        let (old, _) = Measure.run(LegacyCompressorFX(sampleRate: sr), p, x)
        // Level over 5 to 10 ms after the hit, against the settled level (9 dB down).
        let w = (start + 240)..<(start + 480)
        let inLevel = Measure.rmsDB(x[w])
        let grNew = inLevel - Measure.rmsDB(new[w]), grOld = inLevel - Measure.rmsDB(old[w])
        print(String(format: "COMPRESSOR attack 1 ms from silence, 5-10 ms in: new GR %.1f dB, old GR %.1f dB (target 9)", grNew, grOld))
        XCTAssertGreaterThan(grNew, 7.5)
    }

    func testCompressorLevelsOnDrumsStaySensible() {
        let d = Measure.drums(seconds: 2).map { $0 * 0.5 }
        for v: [String: Double] in [["threshold": -14, "ratio": 4, "attack": 10], ["threshold": -14, "ratio": 2, "attack": 30, "release": 150, "makeup": 1],
                                    ["threshold": -18, "ratio": 4, "attack": 5]] {
            let (new, _) = Measure.run(CompressorFX(sampleRate: sr), params(v), d)
            let (old, _) = Measure.run(LegacyCompressorFX(sampleRate: sr), params(v), d)
            let rn = Measure.rmsDB(new[4800...]), ro = Measure.rmsDB(old[4800...]), ri = Measure.rmsDB(d[4800...])
            print(String(format: "COMPRESSOR drums in %.2f dB RMS, %@: new %.2f dB, old %.2f dB", ri, v.description, rn, ro))
            XCTAssertEqual(rn, ro, accuracy: 3)
        }
    }

    func testStaysFinite() {
        var noise = Measure.Noise(3)
        var x = (0..<9600).map { _ in noise.next() * 4 }
        x[50] = .nan
        let (out, _) = Measure.run(CompressorFX(sampleRate: sr), params(["threshold": -60, "ratio": 20, "attack": 0.1, "release": 10, "makeup": 24]), x)
        for v in out[4800...] { XCTAssert(v.isFinite) }
    }
}

// MARK: - Saturator

final class SaturatorTests: XCTestCase {
    let sr = Measure.sr
    let types = ["Soft", "Hard", "Tube", "Fold"]

    func params(_ v: [String: Double]) -> [Double] { SaturatorFX.params.resolve(v) }

    /// Energy at the inharmonic 1 kHz bins against the fundamental, for a 5 kHz sine (dB).
    /// At 48 kHz every alias of a 5 kHz harmonic lands on a multiple of 1 kHz.
    func aliasDB(_ fx: EffectProcessor, _ p: [Double], amp: Double = 0.5) -> Double {
        let x = Measure.sine(5000, amp: amp, seconds: 0.3)
        let (out, _) = Measure.run(fx, p, x)
        let span = out[(out.count - 4800)...]
        let f1 = Measure.amplitude(span, 5000)
        var alias = 0.0
        for k in 1...23 where k % 5 != 0 { alias += pow(Measure.amplitude(span, Double(k) * 1000), 2) }
        return 10 * log10(max(alias, 1e-30) / (f1 * f1))
    }

    func testAliasingIsFarBelowBefore() {
        for (t, name) in types.enumerated() {
            for drive in [6.0, 18.0, 30.0] {
                let p = params(["drive": drive, "type": Double(t), "tone": 20000])
                let new = aliasDB(SaturatorFX(sampleRate: sr), p), old = aliasDB(LegacySaturatorFX(sampleRate: sr), p)
                print(String(format: "SATURATOR alias %@ drive %.0f: new %.1f dB, old %.1f dB (%.1f dB less)", name, drive, new, old, old - new))
                // Where the old curve barely bent the tone (old under -100 dB), both are clean already.
                if old > -100 { XCTAssertLessThan(new, old - 20, "\(name) at \(drive) dB drive") }
                if drive <= 6 { XCTAssertLessThan(new, -60, "\(name) at default drive is clean") }
            }
        }
    }

    func testTubeIsAsymmetricButHasNoDC() {
        let x = Measure.sine(100, amp: 0.5, seconds: 1.5)
        let p = params(["drive": 12, "type": 2])
        let (new, _) = Measure.run(SaturatorFX(sampleRate: sr), p, x)
        let (old, _) = Measure.run(LegacySaturatorFX(sampleRate: sr), p, x)
        let span = (new.count - 24000)..<new.count
        let mean = new[span].reduce(0.0) { $0 + Double($1) } / 24000
        let oldMean = old[span].reduce(0.0) { $0 + Double($1) } / 24000
        let rms = pow(10, Measure.rmsDB(new[span]) / 20)
        let second = Measure.amplitude(new[span], 200) / Measure.amplitude(new[span], 100)
        print(String(format: "SATURATOR tube DC: new %.5f (%.1f dB under RMS), old %.4f; 2nd harmonic %.1f dB", mean, 20 * log10(abs(mean) / rms + 1e-12), oldMean, 20 * log10(second)))
        XCTAssertLessThan(abs(mean), rms * 1e-3)
        XCTAssertGreaterThan(20 * log10(second), -40, "still has even harmonics")
    }

    func testLevelsMatchTheOldSaturator() {
        let x = Measure.sine(220, amp: 0.25, seconds: 0.5)
        for (t, name) in types.enumerated() {
            for v: [String: Double] in [["type": Double(t)], ["drive": 12, "type": Double(t), "mix": 0.6], ["drive": 24, "type": Double(t), "tone": 6000]] {
                let p = params(v)
                let (new, _) = Measure.run(SaturatorFX(sampleRate: sr), p, x)
                let (old, _) = Measure.run(LegacySaturatorFX(sampleRate: sr), p, x)
                let rn = Measure.rmsDB(new[12000...]), ro = Measure.rmsDB(old[12000...])
                print(String(format: "SATURATOR level %@ %@: new %.2f dB, old %.2f dB", name, v.description, rn, ro))
                XCTAssertEqual(rn, ro, accuracy: 1.0)
            }
        }
    }

    /// Dry and wet go through the same filters, so a 50% blend has no comb notches.
    func testParallelMixIsFlat() {
        let p = params(["drive": 0, "type": 0, "tone": 20000, "mix": 0.5])
        var gains: [Double] = []
        for freq in [100.0, 1000, 5000, 10000, 15000, 19000] {
            let x = Measure.sine(freq, amp: 0.01, seconds: 0.2)
            let (out, _) = Measure.run(SaturatorFX(sampleRate: sr), p, x)
            gains.append(Measure.rmsDB(out[4800...]) - Measure.rmsDB(x[4800...]))
        }
        print("SATURATOR 50% mix response (dB): \(gains.map { String(format: "%.3f", $0) })")
        for g in gains { XCTAssertEqual(g, 0, accuracy: 0.3) }
    }

    func testStaysFinite() {
        var noise = Measure.Noise(9)
        for t in 0..<4 {
            var x = (0..<9600).map { _ in noise.next() * 2 }
            x[77] = .nan
            let (out, _) = Measure.run(SaturatorFX(sampleRate: sr), params(["drive": 36, "type": Double(t), "output": 12]), x)
            for v in out[4800...] { XCTAssert(v.isFinite && abs(v) < 10, "\(types[t])") }
            let (silent, _) = Measure.run(SaturatorFX(sampleRate: sr), params(["drive": 36, "type": Double(t)]), [Float](repeating: 0, count: 4800))
            XCTAssertLessThan(Measure.peak(silent), 1e-6)
        }
    }
}

// MARK: - Building blocks

final class OversamplingTests: XCTestCase {
    func testHalfbandRoundTripIsFlatAndImagesAreRejected() {
        let hb = Halfband2x(coefficients: SaturatorFX.stage1)
        // Up then down: an allpass, so a tone keeps its level.
        for freq in [100.0, 5000, 15000, 20000] {
            let x = Measure.sine(freq, amp: 0.5, seconds: 0.1)
            var y = [Float]()
            for v in x { let (a, b) = hb.up(SIMD2(v, v)); y.append(hb.down(a, b).x) }
            XCTAssertEqual(Measure.rmsDB(y[2400...]), Measure.rmsDB(x[2400...]), accuracy: 0.001)
        }
        // Upsampling a 10 kHz tone: its image at 38 kHz (48 - 10, at the 96 kHz rate) is gone.
        let up = Halfband2x(coefficients: SaturatorFX.stage1)
        var y = [Float]()
        for v in Measure.sine(10000, amp: 0.5, seconds: 0.1) { let (a, b) = up.up(SIMD2(v, v)); y += [a.x, b.x] }
        let tail = y[(y.count - 9600)...]
        func amp(_ f: Double) -> Double {
            var re = 0.0, im = 0.0
            for (k, v) in tail.enumerated() { re += Double(v) * cos(2 * .pi * f * Double(k) / 96000); im += Double(v) * sin(2 * .pi * f * Double(k) / 96000) }
            return 2 * (re * re + im * im).squareRoot() / Double(tail.count)
        }
        XCTAssertLessThan(20 * log10(amp(38000) / amp(10000)), -90)
    }

    func testSlidingMinimum() {
        let m = SlidingMinimum(maxWindow: 10)
        var noise = Measure.Noise(5)
        var hist: [Float] = []
        for i in 0..<500 {
            let v = noise.next()
            hist.append(v)
            let w = 1 + (i / 50) % 10
            let got = m.push(v, window: w)
            // Values that left a shorter window don't come back, so check once it's steady.
            if i % 50 >= 10 { XCTAssertEqual(got, hist.suffix(w).min()!) }
        }
    }
}
