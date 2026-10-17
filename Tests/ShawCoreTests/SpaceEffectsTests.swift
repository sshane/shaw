import Accelerate
import XCTest
@testable import ShawCore

/// Measurements for Reverb, Delay, and Chorus. We can't listen, so these check the things
/// that make a reverb sound cheap: ringing modes, slow echo build-up, correlated outputs,
/// DC, level jumps against the old version, and CPU.
final class SpaceEffectsTests: XCTestCase {
    let sr = 48000.0

    // MARK: Helpers

    func run(_ proc: EffectProcessor, _ params: [Double], _ l: [Float], _ r: [Float], bpm: Double = 120,
             block: Int = 512) -> ([Float], [Float]) {
        let buf = StereoBuffer()
        let ctx = RenderContext(sampleRate: sr, bpm: bpm)
        var outL = [Float](repeating: 0, count: l.count), outR = outL
        var done = 0
        while done < l.count {
            let n = min(block, l.count - done)
            for i in 0..<n { buf.l[i] = l[done + i]; buf.r[i] = r[done + i] }
            proc.process(buf, frames: n, params: params, ctx: ctx, beat: 0)
            for i in 0..<n { outL[done + i] = buf.l[i]; outR[done + i] = buf.r[i] }
            done += n
        }
        return (outL, outR)
    }

    /// Wet-only response (Dry/Wet at 100% leaves half the dry signal in; take it out).
    func wet(_ proc: EffectProcessor, _ params: [Double], _ l: [Float], _ r: [Float]) -> ([Float], [Float]) {
        var (ol, or) = run(proc, params, l, r)
        for i in 0..<l.count { ol[i] -= 0.5 * l[i]; or[i] -= 0.5 * r[i] }
        return (ol, or)
    }

    func impulse(_ seconds: Double) -> [Float] {
        var x = [Float](repeating: 0, count: Int(seconds * sr))
        x[0] = 1
        return x
    }

    func reverbIR(_ settings: [String: Double], seconds: Double, legacy: Bool = false) -> ([Float], [Float]) {
        var s = settings
        s["mix"] = 1
        if s["predelay"] == nil { s["predelay"] = 0 }
        let proc: EffectProcessor = legacy ? LegacyFreeverb(sampleRate: sr) : ReverbFX(sampleRate: sr)
        let x = impulse(seconds)
        return wet(proc, ReverbFX.params.resolve(s), x, x.map { _ in 0 })
    }

    /// Schroeder backward integration, slope fitted from -5 dB down to `floor` (-35 dB is T30,
    /// -25 dB is T20, which needs a shorter response), extrapolated to 60 dB.
    func rt60(_ x: [Float], floor: Double = -35) -> Double {
        var e = [Double](repeating: 0, count: x.count)
        var acc = 0.0
        for i in stride(from: x.count - 1, through: 0, by: -1) { acc += Double(x[i]) * Double(x[i]); e[i] = acc }
        let total = e[0]
        var pts: [(Double, Double)] = []
        for i in stride(from: 0, to: x.count, by: 48) {
            let db = 10 * log10(max(e[i], 1e-30) / total)
            if db <= -5 && db >= floor { pts.append((Double(i) / sr, db)) }
        }
        guard pts.count > 4 else { return 0 }
        let mx = pts.map(\.0).reduce(0, +) / Double(pts.count), my = pts.map(\.1).reduce(0, +) / Double(pts.count)
        var num = 0.0, den = 0.0
        for (t, d) in pts { num += (t - mx) * (d - my); den += (t - mx) * (t - mx) }
        return -60 / (num / den)
    }

    /// Normalised echo density (Abel and Huang): 1.0 means the response is as dense as noise.
    func echoDensity(_ x: [Float], at center: Int, window: Int = 960) -> Double {
        let s = max(0, center - window / 2), e = min(x.count, s + window)
        var sq = 0.0
        for i in s..<e { sq += Double(x[i]) * Double(x[i]) }
        let sigma = (sq / Double(e - s)).squareRoot()
        var over = 0
        for i in s..<e where Double(abs(x[i])) > sigma { over += 1 }
        return Double(over) / Double(e - s) / 0.3173
    }

    func correlation(_ a: [Float], _ b: [Float], from: Int, to: Int) -> Double {
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in from..<min(to, a.count) {
            ab += Double(a[i]) * Double(b[i]); aa += Double(a[i]) * Double(a[i]); bb += Double(b[i]) * Double(b[i])
        }
        return ab / max((aa * bb).squareRoot(), 1e-30)
    }

    func rms(_ x: [Float], from: Int = 0, to: Int? = nil) -> Double {
        let e = min(to ?? x.count, x.count)
        var acc = 0.0
        for i in from..<e { acc += Double(x[i]) * Double(x[i]) }
        return (acc / Double(max(1, e - from))).squareRoot()
    }

    func powerSpectrum(_ x: ArraySlice<Float>, n: Int) -> [Double] {
        let log2n = vDSP_Length(log2(Double(n)))
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var frame = [Float](repeating: 0, count: n)
        for (i, v) in x.prefix(n).enumerated() { frame[i] = v * window[i] }
        var re = [Float](repeating: 0, count: n / 2), im = re
        var out = [Double](repeating: 0, count: n / 2)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in
                    fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                for k in 1..<n / 2 { out[k] = Double(rp[k] * rp[k] + ip[k] * ip[k]) }
            }
        }
        return out
    }

    /// Ringing check. Welch-average the tail's spectrum (each frame normalised so the decay
    /// envelope drops out), then compare every bin with its neighbourhood (1/3 octave, and
    /// at least 17 bins so low bands aren't statistically noisy). Random peaks average away;
    /// modes that keep ringing frame after frame do not. Returns the worst peak in dB and its
    /// frequency, between 200 Hz and 8 kHz.
    func tailPeakiness(_ x: [Float], from: Int, to: Int, n: Int = 4096) -> (db: Double, hz: Double) {
        var avg = [Double](repeating: 0, count: n / 2)
        var frames = 0
        var s = from
        while s + n <= min(to, x.count) {
            let p = powerSpectrum(x[s..<(s + n)], n: n)
            let total = p.reduce(0, +)
            for k in 0..<n / 2 { avg[k] += p[k] / total }
            frames += 1
            s += n / 2
        }
        var worst = -100.0, worstHz = 0.0
        let binHz = sr / Double(n)
        for k in Int(200 / binHz)...Int(8000 / binHz) {
            let half = max(8, Int(Double(k) * (pow(2, 1 / 6.0) - 1)))
            let lo = max(1, k - half), hi = min(n / 2 - 1, k + half)
            var m = 0.0
            for j in lo...hi { m += avg[j] }
            m /= Double(hi - lo + 1)
            let db = 10 * log10(avg[k] / m)
            if db > worst { worst = db; worstHz = Double(k) * binHz }
        }
        return (worst, worstHz)
    }

    /// The same statistic for exponentially decaying Gaussian noise: what "perfectly diffuse" scores.
    func noisePeakiness(length: Int, from: Int, to: Int) -> Double {
        var rng = DesignRandom(12345)
        var x = [Float](repeating: 0, count: length)
        for i in 0..<length {
            let u1 = max(rng.next(), 1e-12), u2 = rng.next()
            x[i] = Float((-2 * log(u1)).squareRoot() * cos(2 * .pi * u2) * exp(-Double(i) / sr * 2))
        }
        return tailPeakiness(x, from: from, to: to).db
    }

    // MARK: Reverb

    func testReverbDecayTracksSize() {
        for (size, expected) in [(0.0, 0.3), (0.3, 0.51), (0.5, 0.96), (0.7, 2.05), (0.9, 4.95), (1.0, 8.0)] {
            // T20 on a response long enough to fall ~50 dB: plenty to integrate past -25 dB.
            let (l, _) = reverbIR(["size": size, "damping": 0, "lowcut": 20], seconds: max(1, expected * 0.85))
            let measured = rt60(l, floor: -25)
            XCTAssertEqual(Double(ReverbFX.rt60(size: Float(size))), expected, accuracy: expected * 0.02)
            XCTAssertEqual(measured, expected, accuracy: expected * 0.2, "size \(size): RT60 \(measured) s")
            XCTAssert(l.allSatisfy(\.isFinite))
        }
    }

    func testDampingShortensTheHighs() {
        let (bright, _) = reverbIR(["size": 0.7, "damping": 0], seconds: 3)
        let (dark, _) = reverbIR(["size": 0.7, "damping": 1], seconds: 3)
        // Energy above ~5 kHz in the late tail, relative to the whole tail.
        func highShare(_ x: [Float]) -> Double {
            let p = powerSpectrum(x[Int(0.5 * sr)..<Int(0.5 * sr) + 32768], n: 32768)
            let k = Int(5000 / (sr / 32768))
            return p[k...].reduce(0, +) / p.reduce(0, +)
        }
        XCTAssertLessThan(highShare(dark), highShare(bright) * 0.1)
    }

    func testReverbTailIsDenseQuickly() {
        let (l, r) = reverbIR(["size": 0.7], seconds: 2)
        for ms in stride(from: 80, through: 1000, by: 20) {
            let c = Int(Double(ms) / 1000 * sr)
            XCTAssertGreaterThan(echoDensity(l, at: c), 0.85, "left sparse at \(ms) ms")
            XCTAssertGreaterThan(echoDensity(r, at: c), 0.85, "right sparse at \(ms) ms")
        }
    }

    func testReverbStereoIsDecorrelatedAndMonoSafe() {
        let (l, r) = reverbIR(["size": 0.7], seconds: 2)
        let rho = correlation(l, r, from: Int(0.05 * sr), to: Int(2 * sr))
        XCTAssertLessThan(abs(rho), 0.15, "L/R correlation \(rho)")
        // Mono sum keeps its energy (no cancellation): |L+R|^2 close to |L|^2 + |R|^2.
        let mono = zip(l, r).map { $0 + $1 }
        let ratio = pow(rms(mono), 2) / (pow(rms(l), 2) + pow(rms(r), 2))
        XCTAssertEqual(ratio, 1, accuracy: 0.3)
        // Width 0 is mono.
        let (ml, mr) = reverbIR(["size": 0.7, "width": 0], seconds: 0.5)
        XCTAssertGreaterThan(correlation(ml, mr, from: 0, to: ml.count), 0.999)
    }

    func testReverbHasNoDC() {
        // Sum of the impulse response is its DC gain.
        let (l, r) = reverbIR(["size": 0.9, "lowcut": 20], seconds: 4)
        XCTAssertLessThan(abs(l.reduce(0, +)), 0.02)
        XCTAssertLessThan(abs(r.reduce(0, +)), 0.02)
        // A DC offset on the input never reaches the output.
        let proc = ReverbFX(sampleRate: sr)
        let dc = [Float](repeating: 0.5, count: Int(3 * sr))
        let (ol, _) = wet(proc, ReverbFX.params.resolve(["mix": 1, "size": 0.9]), dc, dc)
        let tail = ol[Int(2 * sr)...]
        XCTAssertLessThan(abs(tail.reduce(0, +) / Float(tail.count)), 1e-4)
    }

    func testReverbTailDoesNotRing() {
        // A long, fairly bright tail: the hardest case for metallic ringing.
        let from = Int(0.15 * sr), to = Int(2.6 * sr)
        let noise = noisePeakiness(length: to, from: from, to: to)
        for (size, damping) in [(0.85, 0.3), (0.6, 0.0)] {
            let (l, r) = reverbIR(["size": size, "damping": damping], seconds: 2.6)
            let newL = tailPeakiness(l, from: from, to: to), newR = tailPeakiness(r, from: from, to: to)
            let (old, _) = reverbIR(["size": size, "damping": damping], seconds: 2.6, legacy: true)
            let legacy = tailPeakiness(old, from: from, to: to)
            print("RINGING size \(size) damping \(damping): worst tail peak L \(newL.db) dB at \(newL.hz) Hz, "
                  + "R \(newR.db) dB, old Freeverb \(legacy.db) dB at \(legacy.hz) Hz, ideal noise \(noise) dB")
            // A diffuse tail scores within a dB or so of ideal noise; Freeverb's combs score ~5 dB.
            XCTAssertLessThan(max(newL.db, newR.db), noise + 1.75)
            XCTAssertLessThan(max(newL.db, newR.db), legacy.db - 1.5)
        }
    }

    /// Pink noise (Paul Kellet's filter): equal energy per octave, like a mix, so a level
    /// comparison isn't dominated by the top octave the way white noise is.
    func pinkNoise(_ n: Int, seed: UInt64 = 7) -> [Float] {
        var rng = DesignRandom(seed)
        var b = [Float](repeating: 0, count: 7)
        return (0..<n).map { _ in
            let w = Float(rng.next() * 2 - 1)
            b[0] = 0.99886 * b[0] + w * 0.0555179; b[1] = 0.99332 * b[1] + w * 0.0750759
            b[2] = 0.96900 * b[2] + w * 0.1538520; b[3] = 0.86650 * b[3] + w * 0.3104856
            b[4] = 0.55000 * b[4] + w * 0.5329522; b[5] = -0.7616 * b[5] - w * 0.0168980
            let pink = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
            b[6] = w * 0.115926
            return pink * 0.1
        }
    }

    func testReverbLevelMatchesOldVersion() {
        // Pink noise (centered, and wide with independent sides) and short bursts, at several
        // sizes. The old reverb summed to mono, which made wide sources 3 dB quieter than
        // centered ones; the new one is true stereo, so the level is set halfway between.
        let n = Int(2 * sr)
        let noise = pinkNoise(n), other = pinkNoise(n, seed: 99)
        let burst = noise.enumerated().map { i, v in i % Int(sr / 2) < 2400 ? v : 0 }
        for size in [0.0, 0.3, 0.7, 0.9, 1.0] {
            for (name, l, r) in [("centered", noise, noise), ("bursts", burst, burst), ("wide", noise, other)] {
                let p = ReverbFX.params.resolve(["size": size, "mix": 1])
                let (nl, nr) = wet(ReverbFX(sampleRate: sr), p, l, r)
                let (ol, or) = wet(LegacyFreeverb(sampleRate: sr), p, l, r)
                let db = 20 * log10((rms(nl, from: n / 3) + rms(nr, from: n / 3)) / (rms(ol, from: n / 3) + rms(or, from: n / 3)))
                print("LEVEL: size \(size) \(name): new vs old \(db) dB")
                XCTAssertEqual(db, 0, accuracy: 3, "size \(size) \(name)")
            }
        }
    }

    func testReverbParameterMovesAreSmooth() {
        // Sweep every control across its range while a sine plays; the output must stay
        // free of steps (no sample-to-sample jump much bigger than the signal's own slope).
        let proc = ReverbFX(sampleRate: sr)
        let buf = StereoBuffer()
        let ctx = RenderContext(sampleRate: sr, bpm: 120)
        var prev: Float = 0, worst: Float = 0
        var t = 0
        for block in 0..<400 {
            let x = Double(block) / 400
            let p = ReverbFX.params.resolve(["size": x, "damping": 1 - x, "predelay": 200 * x, "lowcut": 20 * pow(100, x),
                                             "width": x, "mix": 0.2 + 0.8 * x])
            for i in 0..<128 { buf.l[i] = sinf(Float(t + i) * 0.01) * 0.5; buf.r[i] = buf.l[i] }
            proc.process(buf, frames: 128, params: p, ctx: ctx, beat: 0)
            for i in 0..<128 {
                XCTAssert(buf.l[i].isFinite)
                if block > 4 { worst = max(worst, abs(buf.l[i] - prev)) }
                prev = buf.l[i]
            }
            t += 128
        }
        // A 0.5-amplitude sine at 0.01 rad/sample moves at most 0.005 per sample.
        XCTAssertLessThan(worst, 0.02, "largest step \(worst)")
    }

    func testReverbVectorAndScalarPathsAgree() {
        // Release builds run SIMD kernels, debug builds plain scalar loops. Same network, same
        // memory: the outputs must match to rounding, through parameter moves and modulation.
        let vector = ReverbFX(sampleRate: sr), scalar = ReverbFX(sampleRate: sr)
        vector.vectorKernels = true
        scalar.vectorKernels = false
        let noise = pinkNoise(Int(0.6 * sr)), other = pinkNoise(Int(0.6 * sr), seed: 3)
        let bv = StereoBuffer(), bs = StereoBuffer()
        let ctx = RenderContext(sampleRate: sr, bpm: 120)
        var worst: Float = 0, peak: Float = 0
        var done = 0, block = 0
        while done < noise.count {
            let n = min(block % 3 == 0 ? 333 : 512, noise.count - done) // odd sizes cross the 4-sample blocks
            let x = Double(block) / 60
            let p = ReverbFX.params.resolve(["size": 0.3 + 0.6 * x, "damping": x, "predelay": 30 * x, "mix": 0.8])
            for i in 0..<n {
                bv.l[i] = noise[done + i]; bv.r[i] = other[done + i]
                bs.l[i] = noise[done + i]; bs.r[i] = other[done + i]
            }
            vector.process(bv, frames: n, params: p, ctx: ctx, beat: 0)
            scalar.process(bs, frames: n, params: p, ctx: ctx, beat: 0)
            for i in 0..<n {
                worst = max(worst, abs(bv.l[i] - bs.l[i]), abs(bv.r[i] - bs.r[i]))
                peak = max(peak, abs(bv.l[i]))
            }
            done += n; block += 1
        }
        XCTAssertLessThan(worst, peak * 1e-4, "largest difference \(worst) (peak \(peak))")
    }

    func testReverbIsConsistentAcrossSampleRates() {
        // Delay tables scale with the sample rate, so the decay shouldn't move.
        for rate in [44100.0, 96000.0] {
            let proc = ReverbFX(sampleRate: rate)
            var x = [Float](repeating: 0, count: Int(3 * rate)); x[0] = 1
            let buf = StereoBuffer(), ctx = RenderContext(sampleRate: rate, bpm: 120)
            let p = ReverbFX.params.resolve(["size": 0.7, "damping": 0, "lowcut": 20, "mix": 1, "predelay": 0])
            var out = [Float](repeating: 0, count: x.count)
            var done = 0
            while done < x.count {
                let n = min(512, x.count - done)
                for i in 0..<n { buf.l[i] = x[done + i]; buf.r[i] = 0 }
                proc.process(buf, frames: n, params: p, ctx: ctx, beat: 0)
                for i in 0..<n { out[done + i] = buf.l[i] - 0.5 * x[done + i] }
                done += n
            }
            XCTAssert(out.allSatisfy(\.isFinite))
            // rt60() assumes 48 kHz; rescale its answer.
            let measured = rt60(out) * 48000 / rate
            XCTAssertEqual(measured, 2.05, accuracy: 0.2, "RT60 at \(rate) Hz: \(measured)")
        }
    }

    // MARK: Delay

    func delayRun(_ settings: [String: Double], _ l: [Float], _ r: [Float], bpm: Double = 120) -> ([Float], [Float]) {
        run(DelayFX(sampleRate: sr), DelayFX.params.resolve(settings), l, r, bpm: bpm)
    }

    func testDelayEchoesLandOnTheBeat() {
        // 1/8 dotted at 120 bpm = 0.375 s = 18000 samples, exactly.
        let x = impulse(1.2)
        let (l, r) = delayRun(["time": 6, "feedback": 0.5, "pingpong": 0, "mix": 1, "lowcut": 20, "highcut": 20000], x, x)
        var peak = 0
        var best: Float = 0
        for i in 100..<Int(0.6 * sr) where abs(l[i]) > best { best = abs(l[i]); peak = i }
        XCTAssertEqual(peak, 18000, accuracy: 3)
        XCTAssertEqual(correlation(l, r, from: 0, to: l.count), 1, accuracy: 1e-6)
    }

    func testDelayRepeatsDarkenAndFade() {
        // Each repeat goes through the filters again, so later repeats are duller and quieter.
        let x = impulse(2)
        let (l, _) = delayRun(["time": 5, "feedback": 0.8, "pingpong": 0, "mix": 1, "highcut": 3000, "lowcut": 100], x, x)
        let period = Int(0.25 * sr)
        var energy: [Double] = [], brightness: [Double] = []
        for k in 1...6 {
            let seg = Array(l[(k * period - 400)..<(k * period + 1600)])
            energy.append(rms(seg))
            // First differences emphasise the top end: their share is a brightness measure.
            let diff = zip(seg.dropFirst(), seg).map { $0 - $1 }
            brightness.append(rms(diff) / max(rms(seg), 1e-12))
        }
        for k in 1..<energy.count {
            XCTAssertLessThan(energy[k], energy[k - 1])
            XCTAssertLessThan(brightness[k], brightness[k - 1] * 1.001)
        }
        XCTAssertLessThan(brightness[5], brightness[0] * 0.8)
    }

    func testDelayFeedbackNeverRunsAway() {
        // A tone whose period divides the delay time, at maximum feedback with the filters
        // wide open: a linear loop would climb towards 20x. Saturation levels it off.
        let period = Int(0.25 * sr) / 120 // 120 cycles per 1/8 note: 480 Hz
        let n = Int(8 * sr)
        let x = (0..<n).map { i in Float(sin(2 * Double.pi * Double(i) / Double(period))) * 0.5 }
        for ping in [0.0, 1.0] {
            let (l, r) = delayRun(["time": 5, "feedback": 0.95, "pingpong": ping, "mix": 1, "lowcut": 20, "highcut": 20000], x, x)
            let peak = max(l.map(abs).max()!, r.map(abs).max()!)
            XCTAssert(l.allSatisfy(\.isFinite) && r.allSatisfy(\.isFinite))
            XCTAssertLessThan(peak, 2.0, "ping-pong \(ping): peak \(peak)")
        }
    }

    func testDelayChangesAreClickFree() {
        // Change the time (and every knob, and the tempo) mid-stream under a steady tone: no jumps.
        let proc = DelayFX(sampleRate: sr)
        let buf = StereoBuffer()
        var prev: Float = 0, worst: Float = 0
        var t = 0
        for block in 0..<300 {
            let x = Double(block) / 300
            let p = DelayFX.params.resolve(["time": block < 150 ? 5 : 8, "feedback": 0.3 + 0.6 * x, "mix": 0.2 + 0.8 * x,
                                            "lowcut": 20 * pow(50, x), "highcut": 20000 * pow(0.1, x), "pingpong": 0])
            let ctx = RenderContext(sampleRate: sr, bpm: block < 220 ? 120 : 128)
            for i in 0..<128 { buf.l[i] = sinf(Float(t + i) * 0.01) * 0.5; buf.r[i] = buf.l[i] }
            proc.process(buf, frames: 128, params: p, ctx: ctx, beat: 0)
            for i in 0..<128 {
                if block > 2 { worst = max(worst, abs(buf.l[i] - prev)) }
                prev = buf.l[i]
            }
            t += 128
        }
        XCTAssertLessThan(worst, 0.03, "largest step \(worst)")
    }

    // MARK: Chorus

    func chorusRun(_ settings: [String: Double], _ l: [Float], _ r: [Float]) -> ([Float], [Float]) {
        run(ChorusFX(sampleRate: sr), ChorusFX.params.resolve(settings), l, r)
    }

    func testChorusIsWideButMonoSafe() {
        let n = Int(2 * sr)
        let x = pinkNoise(n)
        let (l, r) = chorusRun(["mix": 1, "depth": 0.6], x, x)
        // Wet only: remove the half of dry that Dry/Wet 100% keeps.
        let wl = zip(l, x).map { $0 - 0.5 * $1 }, wr = zip(r, x).map { $0 - 0.5 * $1 }
        let rho = correlation(wl, wr, from: n / 4, to: n)
        XCTAssertLessThan(rho, 0.9, "sides should differ (correlation \(rho))")
        // Summed to mono, the wet keeps its level: no deep cancellation.
        let mono = zip(wl, wr).map { ($0 + $1) * 0.5 }
        XCTAssertGreaterThan(rms(mono, from: n / 4) / rms(wl, from: n / 4), 0.6)
    }

    func testModulatedReadsStayBright() {
        // A moving delay read sweeps through every fraction. At 10 kHz, the cubic interpolator
        // the reverb and chorus use stays within ~0.5 dB at any fraction; linear interpolation
        // (the old chorus) sags by 2 dB at the halfway point, so its level flutters with the LFO.
        let n = 4096
        let x = (0..<n).map { i in Float(sin(2 * Double.pi * 10000 * Double(i) / sr)) }
        var worstCubic = 0.0, worstLinear = 0.0
        for step in 0...8 {
            let t = Float(step) / 8
            var cubic = 0.0, linear = 0.0
            for i in 2..<(n - 2) {
                let c = lagrange4(x[i + 1], x[i], x[i - 1], x[i - 2], t), l = x[i] + (x[i - 1] - x[i]) * t
                cubic += Double(c * c); linear += Double(l * l)
            }
            let ref = Double(n - 4) * 0.5
            worstCubic = max(worstCubic, abs(10 * log10(cubic / ref)))
            worstLinear = max(worstLinear, abs(10 * log10(linear / ref)))
        }
        XCTAssertLessThan(worstCubic, 0.6, "cubic: \(worstCubic) dB")
        XCTAssertGreaterThan(worstLinear, 1.5, "linear: \(worstLinear) dB")
        // And the chorus, fully wet, keeps a 10 kHz tone's level.
        let m = Int(sr)
        let tone = (0..<m).map { i in Float(sin(2 * Double.pi * 10000 * Double(i) / sr)) * 0.5 }
        let (l, _) = chorusRun(["mix": 1, "depth": 1, "rate": 3, "delay": 8], tone, [Float](repeating: 0, count: m))
        let wet = zip(l, tone).map { $0 - 0.5 * $1 }
        XCTAssertGreaterThan(rms(wet, from: m / 4) / rms(tone, from: m / 4), 0.4)
    }

    func testChorusChangesAreClickFree() {
        let proc = ChorusFX(sampleRate: sr)
        let buf = StereoBuffer()
        let ctx = RenderContext(sampleRate: sr, bpm: 120)
        var prev: Float = 0, worst: Float = 0
        var t = 0
        for block in 0..<300 {
            // Jump Delay from 1 ms to 30 ms and back, with Depth, Feedback, Mix, and Rate.
            let up = (block / 50) % 2 == 1
            let p = ChorusFX.params.resolve(["delay": up ? 30 : 1, "depth": up ? 1 : 0.2, "feedback": up ? 0.6 : 0,
                                             "mix": up ? 0.9 : 0.3, "rate": up ? 6 : 0.5])
            for i in 0..<128 { buf.l[i] = sinf(Float(t + i) * 0.01) * 0.5; buf.r[i] = buf.l[i] }
            proc.process(buf, frames: 128, params: p, ctx: ctx, beat: 0)
            for i in 0..<128 {
                XCTAssert(buf.l[i].isFinite)
                if block > 2 { worst = max(worst, abs(buf.l[i] - prev)) }
                prev = buf.l[i]
            }
            t += 128
        }
        XCTAssertLessThan(worst, 0.03, "largest step \(worst)")
    }

    func testChorusFeedbackStaysBounded() {
        let n = Int(4 * sr)
        let x = (0..<n).map { i in Float(sin(2 * Double.pi * 1000 * Double(i) / sr)) * 0.8 }
        let (l, r) = chorusRun(["delay": 1, "feedback": 0.9, "depth": 0.1, "mix": 1], x, x)
        XCTAssert(l.allSatisfy(\.isFinite) && r.allSatisfy(\.isFinite))
        XCTAssertLessThan(max(l.map(abs).max()!, r.map(abs).max()!), 4)
    }

    // MARK: CPU

    func cpuPercent(_ proc: EffectProcessor, _ params: [Double]) -> Double {
        let buf = StereoBuffer()
        let ctx = RenderContext(sampleRate: sr, bpm: 120)
        let noise = pinkNoise(512)
        #if DEBUG
        let seconds = 1.0 // unoptimized code: just exercise it
        #else
        let seconds = 20.0
        #endif
        let blocks = Int(seconds * sr / 512)
        let start = Date()
        for _ in 0..<blocks {
            for i in 0..<512 { buf.l[i] = noise[i]; buf.r[i] = noise[i] }
            proc.process(buf, frames: 512, params: params, ctx: ctx, beat: 0)
        }
        return Date().timeIntervalSince(start) / seconds * 100
    }

    func testCPU() {
        let reverb = cpuPercent(ReverbFX(sampleRate: sr), ReverbFX.params.resolve(["size": 0.8]))
        let delay = cpuPercent(DelayFX(sampleRate: sr), DelayFX.params.resolve([:]))
        let chorus = cpuPercent(ChorusFX(sampleRate: sr), ChorusFX.params.resolve([:]))
        print(String(format: "CPU: reverb %.3f%%, delay %.3f%%, chorus %.3f%% of one core at 48 kHz", reverb, delay, chorus))
        #if !DEBUG
        XCTAssertLessThan(reverb, 1.0)
        XCTAssertLessThan(delay, 0.25)
        XCTAssertLessThan(chorus, 0.25)
        #endif
    }

    // MARK: Report (prints the numbers used to tune the design)

    func testReverbReport() throws {
        #if DEBUG
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
        try XCTSkipIf(debugBuild, "Prints tuning numbers; run with -c release to see them quickly.")
        for size in [0.0, 0.25, 0.5, 0.7, 0.85, 1.0] {
            let rt = Double(ReverbFX.rt60(size: Float(size)))
            let (l, r) = reverbIR(["size": size, "damping": 0, "lowcut": 20], seconds: max(1.5, rt * 1.3))
            let (dl, _) = reverbIR(["size": size], seconds: max(1.5, rt * 1.3))
            print(String(format: "REPORT size %.2f: target RT60 %.2f s, measured %.2f s (damping 50%%: %.2f s), L/R corr %.3f",
                         size, rt, rt60(l), rt60(dl), correlation(l, r, from: Int(0.05 * sr), to: l.count)))
        }
        let (l, _) = reverbIR(["size": 0.7], seconds: 2)
        var dens: [String] = []
        for ms in [5, 10, 20, 30, 40, 60, 80, 100, 150, 200, 300, 500] {
            dens.append(String(format: "%d:%.2f", ms, echoDensity(l, at: Int(Double(ms) / 1000 * sr))))
        }
        print("REPORT echo density (ms:NED) " + dens.joined(separator: " "))
        var env: [String] = []
        for ms in stride(from: 0, to: 160, by: 5) {
            let s = Int(Double(ms) / 1000 * sr)
            env.append(String(format: "%d:%.1f", ms, 20 * log10(max(rms(l, from: s, to: s + 240), 1e-9))))
        }
        print("REPORT envelope (ms:dB) " + env.joined(separator: " "))
        let (old, _) = reverbIR(["size": 0.7], seconds: 2, legacy: true)
        var bands: [String] = []
        let pn = powerSpectrum(l[0..<65536], n: 65536), po = powerSpectrum(old[0..<65536], n: 65536)
        let binHz = sr / 65536
        var f = 63.0
        while f < 20000 {
            let lo = Int(f / sqrt(2) / binHz), hi = Int(f * sqrt(2) / binHz)
            let en = pn[lo..<hi].reduce(0, +), eo = po[lo..<hi].reduce(0, +)
            bands.append(String(format: "%.0f:%+.1f", f, 10 * log10(en / eo)))
            f *= 2
        }
        print("REPORT octave balance new vs old (Hz:dB) " + bands.joined(separator: " "))
    }
}

/// The previous reverb (Freeverb), kept only so tests can compare level and ringing.
final class LegacyFreeverb: EffectProcessor {
    final class Comb {
        var line: [Float]; var idx = 0; var store: Float = 0
        init(_ n: Int) { line = [Float](repeating: 0, count: n) }
        func process(_ x: Float, fb: Float, damp: Float) -> Float {
            let out = line[idx]
            store = out * (1 - damp) + store * damp
            line[idx] = x + store * fb
            idx += 1; if idx >= line.count { idx = 0 }
            return out
        }
    }
    final class Allpass {
        var line: [Float]; var idx = 0
        init(_ n: Int) { line = [Float](repeating: 0, count: n) }
        func process(_ x: Float) -> Float {
            let b = line[idx]
            line[idx] = x + b * 0.5
            idx += 1; if idx >= line.count { idx = 0 }
            return b - x
        }
    }
    let combsL: [Comb], combsR: [Comb], apL: [Allpass], apR: [Allpass]
    let pre: DelayLine
    var hp = Biquad()
    var lastLowCut = -1.0
    let sr: Double

    init(sampleRate: Double) {
        sr = sampleRate
        let s = sampleRate / 44100
        let combT = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617], apT = [556, 441, 341, 225]
        combsL = combT.map { Comb(Int(Double($0) * s)) }; combsR = combT.map { Comb(Int(Double($0 + 23) * s)) }
        apL = apT.map { Allpass(Int(Double($0) * s)) }; apR = apT.map { Allpass(Int(Double($0 + 23) * s)) }
        pre = DelayLine(maxSamples: Int(0.25 * sampleRate))
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let fb = 0.7 + Float(p[0]) * 0.28, damp = Float(p[1]) * 0.4
        let preSamples = Float(p[2] / 1000 * sr)
        if p[3] != lastLowCut { lastLowCut = p[3]; hp.set(.highpass, freq: p[3], q: 0.707, sampleRate: sr) }
        let width = Float(p[4]), mix = Float(p[5])
        let wet1 = mix * (width / 2 + 0.5), wet2 = mix * ((1 - width) / 2), dry = 1 - mix * 0.5
        for i in 0..<frames {
            let inL = buf.l[i], inR = buf.r[i]
            pre.write((inL + inR) * 0.5)
            var x = preSamples < 1 ? (inL + inR) * 0.5 : pre.read(preSamples)
            x = hp.process(x) * 0.03
            var oL: Float = 0, oR: Float = 0
            for c in combsL { oL += c.process(x, fb: fb, damp: damp) }
            for c in combsR { oR += c.process(x, fb: fb, damp: damp) }
            for a in apL { oL = a.process(oL) }
            for a in apR { oR = a.process(oR) }
            buf.l[i] = inL * dry + oL * wet1 + oR * wet2
            buf.r[i] = inR * dry + oR * wet1 + oL * wet2
        }
    }

    func reset() {}
}
