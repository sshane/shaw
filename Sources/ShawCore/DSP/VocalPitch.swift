import Accelerate
import Foundation

// Pitch detection, note finding, and pitch shifting for a recorded voice (or any single-note
// instrument). Offline: these run over a whole take, off the audio thread.

// MARK: - Pitch tracking (pYIN)

/// The pitch of a take, every `hop` samples: in MIDI note numbers (fractional, so 60.25 is a quarter
/// tone above middle C), 0 where nothing is sung (breaths, "s" sounds, silence).
public struct PitchTrack: Equatable {
    public var hop: Int
    public var sampleRate: Double
    public var pitch: [Float]
    public var rms: [Float]
    /// Samples from a frame's first sample to the moment its pitch describes.
    public var center: Int
    public var frameSeconds: Double { Double(hop) / sampleRate }
    /// When frame `i` happens in the take, in seconds.
    public func seconds(_ i: Int) -> Double { Double(i * hop + center) / sampleRate }
    public func isVoiced(_ i: Int) -> Bool { pitch[i] > 0 }
}

/// Probabilistic YIN (Mauch & Dixon, 2014): YIN's dips at the period of the voice, scored over a
/// spread of thresholds into candidates with probabilities, then a hidden Markov model picks the
/// most likely path through them over time, which also decides where the voice is singing at all.
/// Octave jumps and stray frames mostly vanish, because the path has to make sense from frame to frame.
public enum PitchTracker {
    public static let lowestHz = 65.0
    public static let highestHz = 1100.0
    /// Pitch resolution of the model: 20 cents a step (each frame is refined between steps afterwards).
    static let binCents = 20.0

    public static func track(_ x: [Float], sampleRate sr: Double, hopSeconds: Double = 0.005) -> PitchTrack {
        let hop = max(1, Int(sr * hopSeconds))
        let maxLag = Int(sr / lowestHz) + 2, minLag = max(2, Int(sr / highestHz))
        // The integration window: long enough for two periods of the lowest note.
        let win = maxLag + 2
        let frameLen = win + maxLag
        let count = x.count < frameLen ? 0 : (x.count - frameLen) / hop + 1
        var cands: [[(lag: Double, p: Float)]] = Array(repeating: [], count: count)
        var rms = [Float](repeating: 0, count: count)

        // The threshold prior: a beta(2, 18) distribution over thresholds 0.01...1 (pYIN's default).
        let thresholds = (1...100).map { Double($0) / 100 }
        var prior = thresholds.map { s in pow(s, 1) * pow(1 - s, 17) }
        let total = prior.reduce(0, +)
        prior = prior.map { $0 / total }

        let fftN = nextPow2(frameLen * 2), log2n = vDSP_Length(log2(Double(fftN)))
        guard let fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return PitchTrack(hop: hop, sampleRate: sr, pitch: [], rms: [], center: 0) }
        defer { vDSP_destroy_fftsetup(fft) }
        var aRe = [Float](repeating: 0, count: fftN / 2), aIm = aRe, bRe = aRe, bIm = aRe
        var padA = [Float](repeating: 0, count: fftN), padB = padA
        var corr = [Float](repeating: 0, count: fftN)
        var d = [Float](repeating: 0, count: maxLag + 2)

        for f in 0..<count {
            let s = f * hop
            // Level, over the window around the frame's center.
            var e: Float = 0
            x.withUnsafeBufferPointer { p in vDSP_svesq(p.baseAddress! + s, 1, &e, vDSP_Length(frameLen)) }
            rms[f] = sqrt(e / Float(frameLen))
            if rms[f] < 1e-4 { continue }

            // YIN's difference d(τ) = e0 + eτ − 2r(τ), with r from one FFT cross-correlation.
            for i in 0..<fftN { padA[i] = 0; padB[i] = 0 }
            for i in 0..<frameLen { padA[i] = x[s + i] }
            for i in 0..<win { padB[i] = x[s + i] }
            correlate(&padA, &padB, &aRe, &aIm, &bRe, &bIm, &corr, fft, log2n, fftN)
            var e0: Float = 0
            for i in 0..<win { e0 += x[s + i] * x[s + i] }
            var et = e0
            d[0] = 0
            for tau in 1...maxLag {
                et += x[s + win - 1 + tau] * x[s + win - 1 + tau] - x[s + tau - 1] * x[s + tau - 1]
                d[tau] = max(0, e0 + et - 2 * corr[tau])
            }
            // Cumulative mean normalized difference.
            var running: Float = 0
            var cm = [Float](repeating: 1, count: maxLag + 1)
            for tau in 1...maxLag {
                running += d[tau]
                cm[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
            }
            // Dips: local minima in range, each refined between lags.
            var dips: [(lag: Int, v: Float)] = []
            for tau in max(minLag, 2)..<maxLag where cm[tau] < cm[tau - 1] && cm[tau] <= cm[tau + 1] { dips.append((tau, cm[tau])) }
            guard !dips.isEmpty else { continue }
            var probs = [Float](repeating: 0, count: dips.count)
            let global = dips.indices.min { dips[$0].v < dips[$1].v }!
            for (k, s0) in thresholds.enumerated() {
                if let i = dips.firstIndex(where: { Double($0.v) < s0 }) {
                    probs[i] += Float(prior[k])
                } else {
                    probs[global] += Float(prior[k]) * 0.01
                }
            }
            for (i, dip) in dips.enumerated() where probs[i] > 1e-4 {
                let t = dip.lag
                let y0 = Double(cm[t - 1]), y1 = Double(cm[t]), y2 = Double(cm[t + 1])
                let den = y0 - 2 * y1 + y2
                let shift = abs(den) > 1e-9 ? max(-0.5, min(0.5, 0.5 * (y0 - y2) / den)) : 0
                cands[f].append((Double(t) + shift, probs[i]))
            }
        }
        let pitch = decode(cands, rms: rms, sampleRate: sr)
        // What a frame hears is centered about halfway through everything it reads (measured: tuning
        // a vibrato flat is cleanest with this alignment).
        return PitchTrack(hop: hop, sampleRate: sr, pitch: pitch, rms: rms, center: frameLen / 2 + Int(sr / 1000))
    }

    /// Viterbi over pitch steps plus one "not singing" state.
    static func decode(_ cands: [[(lag: Double, p: Float)]], rms: [Float], sampleRate sr: Double) -> [Float] {
        let n = cands.count
        guard n > 0 else { return [] }
        let lowMidi = 69 + 12 * log2(lowestHz / 440)
        let bins = Int((1200 * log2(highestHz / lowestHz)) / binCents) + 1
        func bin(_ lag: Double) -> Int? {
            let midi = 69 + 12 * log2(sr / lag / 440)
            let b = Int(((midi - lowMidi) * 100 / binCents).rounded())
            return b >= 0 && b < bins ? b : nil
        }
        let jump = 12 // steps a pitch may move from one frame to the next (240 cents in 5 ms)
        var trans = [Float](repeating: 0, count: 2 * jump + 1)
        for k in -jump...jump { trans[k + jump] = Float(jump + 1 - abs(k)) }
        // Relative to holding the same pitch (which costs nothing), so a held note isn't charged
        // every frame for the jumps it didn't make, and staying sung competes fairly with silence.
        let logTrans = trans.map { log($0 / Float(jump + 1)) }
        let stay = log(Float(0.99)), switchP = log(Float(0.01))
        let floorP = log(Float(1e-6))
        let u = bins // the unvoiced state
        var score = [Float](repeating: -1e30, count: bins + 1), next = score
        var back = [[Int32]](repeating: [Int32](repeating: 0, count: bins + 1), count: n)
        var obs = [Float](repeating: floorP, count: bins + 1)
        // Quiet frames are breath or room: they can't be sung.
        let peakRMS = rms.max() ?? 0
        let gate = max(1e-4, peakRMS * 0.01)
        func observe(_ f: Int) {
            for i in 0...bins { obs[i] = floorP }
            var voiced: Float = 0
            if rms[f] >= gate {
                for c in cands[f] { if let b = bin(c.lag) { obs[b] = log(max(1e-6, exp(obs[b]) + c.p)); voiced += c.p } }
            }
            obs[u] = log(max(1e-6, 1 - min(1, voiced)))
        }
        observe(0)
        for i in 0...bins { score[i] = obs[i] }
        for f in 1..<n {
            observe(f)
            for b in 0..<bins {
                var best: Float = -1e30, arg: Int32 = 0
                let lo = max(0, b - jump), hi = min(bins - 1, b + jump)
                for a in lo...hi {
                    let v = score[a] + logTrans[a - b + jump] + stay
                    if v > best { best = v; arg = Int32(a) }
                }
                // From silence into a note: any pitch is equally likely.
                let fromU = score[u] + switchP - log(Float(bins))
                if fromU > best { best = fromU; arg = Int32(u) }
                next[b] = best + obs[b]
                back[f][b] = arg
            }
            var bestU = score[u] + stay, argU = Int32(u)
            for a in 0..<bins where score[a] + switchP > bestU { bestU = score[a] + switchP; argU = Int32(a) }
            next[u] = bestU + obs[u]
            back[f][u] = argU
            swap(&score, &next)
        }
        var state = (0...bins).max { score[$0] < score[$1] }!
        var path = [Int](repeating: u, count: n)
        for f in stride(from: n - 1, through: 0, by: -1) {
            path[f] = state
            state = Int(back[f][state])
        }
        // Refine: each voiced frame takes its nearest candidate's exact pitch.
        var out = [Float](repeating: 0, count: n)
        for f in 0..<n where path[f] != u {
            let center = lowMidi + Double(path[f]) * binCents / 100
            var best: Double?
            for c in cands[f] {
                let m = 69 + 12 * log2(sr / c.lag / 440)
                if abs(m - center) <= binCents / 100 * 1.5, best.map({ abs(m - center) < abs($0 - center) }) ?? true { best = m }
            }
            out[f] = Float(best ?? center)
        }
        return out
    }

    private static func correlate(_ a: inout [Float], _ b: inout [Float], _ aRe: inout [Float], _ aIm: inout [Float],
                                  _ bRe: inout [Float], _ bIm: inout [Float], _ out: inout [Float],
                                  _ fft: FFTSetup, _ log2n: vDSP_Length, _ n: Int) {
        aRe.withUnsafeMutableBufferPointer { ar in aIm.withUnsafeMutableBufferPointer { ai in
        bRe.withUnsafeMutableBufferPointer { br in bIm.withUnsafeMutableBufferPointer { bi in
            var sa = DSPSplitComplex(realp: ar.baseAddress!, imagp: ai.baseAddress!)
            var sb = DSPSplitComplex(realp: br.baseAddress!, imagp: bi.baseAddress!)
            a.withUnsafeBufferPointer { p in p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &sa, 1, vDSP_Length(n / 2)) } }
            b.withUnsafeBufferPointer { p in p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &sb, 1, vDSP_Length(n / 2)) } }
            vDSP_fft_zrip(fft, &sa, 1, log2n, FFTDirection(FFT_FORWARD))
            vDSP_fft_zrip(fft, &sb, 1, log2n, FFTDirection(FFT_FORWARD))
            // A · conj(B), packed (DC and Nyquist sit in the first real and imaginary slots).
            let dc = sa.realp[0] * sb.realp[0], ny = sa.imagp[0] * sb.imagp[0]
            vDSP_zvcmul(&sb, 1, &sa, 1, &sa, 1, vDSP_Length(n / 2))
            sa.realp[0] = dc; sa.imagp[0] = ny
            vDSP_fft_zrip(fft, &sa, 1, log2n, FFTDirection(FFT_INVERSE))
            out.withUnsafeMutableBufferPointer { o in o.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ztoc(&sa, 1, $0, 2, vDSP_Length(n / 2)) } }
        }}}}
        // vDSP's forward real FFTs are scaled by 2 each, the inverse by n: undo it.
        var scale = 1 / Float(4 * n)
        vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(n))
    }

    static func nextPow2(_ n: Int) -> Int { var p = 1; while p < n { p <<= 1 }; return p }
}

// MARK: - Notes

/// One sung note: where it is (frames of the pitch track), its center, and how far its pitch drifts
/// slowly (drift) and moves quickly (vibrato and the like) around that center, frame by frame.
public struct SungNote: Equatable, Identifiable {
    public var id: Int { start }
    public var start: Int
    public var end: Int
    /// The pitch the note is heard as (MIDI, fractional).
    public var center: Double
    /// Per frame from `start`: the slow wander around the center, and the fast movement on top (semitones).
    public var drift: [Float]
    public var modulation: [Float]
}

/// Turns a pitch track into notes the way pitch editors do: a note runs while the pitch holds, a new
/// one starts when it settles somewhere else for long enough, tiny fragments join a neighbor, and each
/// note's center is a weighted middle that ignores its scoop in and its fall away.
public enum NoteFinder {
    /// How far (semitones) and how long (seconds) the pitch has to move to count as a new note.
    public static let splitSemitones = 0.6
    public static let splitHold = 0.07
    public static let shortest = 0.06

    public static func notes(in t: PitchTrack) -> [SungNote] {
        let n = t.pitch.count
        let hold = max(1, Int(splitHold / t.frameSeconds)), shortestFrames = max(1, Int(shortest / t.frameSeconds))
        // A lightly smoothed pitch (median over ~25 ms) decides where notes change.
        let smooth = median(t.pitch, radius: 2)
        var ranges: [(Int, Int)] = []
        var i = 0
        while i < n {
            guard t.pitch[i] > 0 else { i += 1; continue }
            var j = i
            while j < n && (t.pitch[j] > 0 || (j + 1 < n && t.pitch[j + 1] > 0 && j > i)) { j += 1 } // a one-frame gap doesn't end a phrase
            // Split the voiced run where the pitch moves and stays moved.
            var start = i
            var ref = Double(smooth[i])
            var away = 0, awayStart = i
            for k in i..<j {
                let p = Double(smooth[k])
                guard p > 0 else { continue }
                if abs(p - ref) > splitSemitones {
                    if away == 0 { awayStart = k }
                    away += 1
                    if away >= hold {
                        ranges.append((start, awayStart))
                        start = awayStart
                        let settled = Double(smooth[min(j - 1, awayStart + hold / 2)])
                        ref = settled > 0 ? settled : p // (a one-frame gap has no pitch to settle on)
                        away = 0
                    }
                } else {
                    away = 0
                    ref += (p - ref) * 0.05 // follow slow drift
                }
            }
            ranges.append((start, j))
            i = j
        }
        // Fragments too short to be notes join the neighbor closest in pitch.
        var merged: [(Int, Int)] = []
        for r in ranges {
            if r.1 - r.0 < shortestFrames, let last = merged.last, r.0 - last.1 <= 2 {
                merged[merged.count - 1].1 = r.1
            } else {
                merged.append(r)
            }
        }
        return merged.compactMap { r -> SungNote? in
            guard r.1 - r.0 >= 2 else { return nil }
            return describe(t, from: r.0, to: r.1)
        }
    }

    /// The center (a weighted median of the note's steady middle) and the drift/modulation split.
    static func describe(_ t: PitchTrack, from a: Int, to b: Int) -> SungNote {
        let len = b - a
        let edge = Int(Double(len) * 0.18)
        var pairs: [(Double, Double)] = []
        for k in a..<b where t.pitch[k] > 0 {
            let inner = k >= a + edge && k < b - edge
            let slope = k > a && t.pitch[k - 1] > 0 ? abs(Double(t.pitch[k] - t.pitch[k - 1])) : 0
            let w = Double(t.rms[k]) * (inner ? 1 : 0.15) / (1 + slope * 20)
            pairs.append((Double(t.pitch[k]), w))
        }
        pairs.sort { $0.0 < $1.0 }
        let total = pairs.reduce(0) { $0 + $1.1 }
        var acc = 0.0, center = pairs.first?.0 ?? 0
        for (p, w) in pairs { acc += w; if acc >= total / 2 { center = p; break } }
        // Drift: the deviation low-passed at ~2.5 Hz, forward and back so it doesn't lag.
        var dev = (a..<b).map { t.pitch[$0] > 0 ? Float(Double(t.pitch[$0]) - center) : 0 }
        let k = Float(1 - exp(-2 * Double.pi * 2.5 * t.frameSeconds))
        var drift = dev
        var y = drift.first ?? 0
        for i in drift.indices { y += (drift[i] - y) * k; drift[i] = y }
        y = drift.last ?? 0
        for i in drift.indices.reversed() { y += (drift[i] - y) * k; drift[i] = y }
        for i in dev.indices { dev[i] -= drift[i] }
        return SungNote(start: a, end: b, center: center, drift: drift, modulation: dev)
    }

    static func median(_ x: [Float], radius: Int) -> [Float] {
        x.indices.map { i in
            let w = x[max(0, i - radius)...min(x.count - 1, i + radius)].filter { $0 > 0 }.sorted()
            return x[i] > 0 && !w.isEmpty ? w[w.count / 2] : x[i]
        }
    }
}

// MARK: - Pitch shifting

/// Moves pitch without moving time. The take is stretched longer (to go up) or shorter (to go down)
/// by the shift, in overlapping grains that are each placed where their waveform lines up with the
/// grain before (WSOLA), then read back faster or slower by the same amount, which restores the
/// timing and moves the pitch. Grains never cut a wave mid-cycle and every join is a long, even
/// crossfade, so nothing clicks. Where nothing moves, the output is the input.
public enum PitchShifter {
    /// Shift each channel by `cents` (one value per pitch-track frame; positive is up). The channels
    /// move together, lined up by their mix, so a stereo take keeps its image.
    public static func shift(_ channels: [[Float]], track t: PitchTrack, cents: [Float]) -> [[Float]] {
        let n = channels.first?.count ?? 0, sr = t.sampleRate
        guard n > 0, !cents.isEmpty, cents.contains(where: { $0 != 0 }) else { return channels }
        // Grains of ~30 ms overlapping by half; each may slide up to ~7.5 ms to line up, enough to
        // find a matching cycle of the lowest voice.
        let size = max(64, Int(sr * 0.03) / 2 * 2), hop = size / 2, slide = max(8, Int(sr * 0.0075))
        let pre = size, post = 2 * size + 2 * slide + 4
        // Each channel padded with silence, and their mix (what the grains line up by).
        let padded = channels.map { [Float](repeating: 0, count: pre) + $0.prefix(n) + [Float](repeating: 0, count: post + n - min(n, $0.count)) }
        var xp = padded[0]
        if padded.count > 1 {
            for c in padded.dropFirst() { for i in xp.indices { xp[i] += c[i] } }
            var k = 1 / Float(padded.count)
            vDSP_vsmul(xp, 1, &k, &xp, 1, vDSP_Length(xp.count))
        }
        // Energy up to each sample, for normalizing the line-up scores.
        var energy = [Double](repeating: 0, count: xp.count + 1)
        for i in 0..<xp.count { energy[i + 1] = energy[i] + Double(xp[i] * xp[i]) }
        func power(_ a: Int, _ len: Int) -> Double { energy[a + len] - energy[a] }

        // The shift at a padded position: cents interpolated between frame centers.
        func ratio(_ p: Double) -> Double {
            let f = (p - Double(pre) - Double(t.center)) / Double(t.hop)
            let k = Int(floor(f)), w = f - floor(f)
            let a = cents[min(cents.count - 1, max(0, k))], b = cents[min(cents.count - 1, max(0, k + 1))]
            return pow(2, (Double(a) * (1 - w) + Double(b) * w) / 1200)
        }
        func unvoiced(_ a: Int, _ len: Int) -> Bool {
            let lo = max(0, (a - pre - t.center) / t.hop), hi = min(t.pitch.count - 1, (a + len - pre - t.center) / t.hop)
            return lo > hi || !(lo...hi).contains { t.pitch[$0] > 0 }
        }

        // A periodic Hann window: halves overlapping by `hop` sum to exactly one.
        let window = (0..<size).map { i -> Float in let c = sin(Float.pi * Float(i) / Float(size)); return c * c }
        // Stretch. Grain k goes out at k·hop and comes from near `nominal`, which moves on by hop/ratio.
        var nominals: [Double] = []
        var stretched = [[Float]](repeating: [], count: padded.count)
        var nominal = 0.0, prev = 0
        while Int(nominal) + size + slide + 2 < xp.count && nominal <= Double(pre + n + 2 * hop) {
            let near = Int(nominal.rounded())
            var start = near
            if !nominals.isEmpty, !unvoiced(near, size) {
                // The continuation of the previous grain is the target: find the start, near where
                // this grain belongs, whose waveform matches it best (preferring the nearer of two
                // nearly equal matches, so timing stays close).
                let target = prev + hop
                let lo = max(0, near - slide), hi = min(xp.count - size - 1, near + slide)
                let et = power(target, hop)
                var best = -Double.infinity
                func score(_ c: Int) -> Double {
                    var dot: Float = 0
                    xp.withUnsafeBufferPointer { p in vDSP_dotpr(p.baseAddress! + target, 1, p.baseAddress! + c, 1, &dot, vDSP_Length(hop)) }
                    let norm = sqrt(et * power(c, hop))
                    return (norm > 1e-12 ? Double(dot) / norm : 0) - 0.08 * Double(abs(c - near)) / Double(slide)
                }
                if lo <= hi {
                    var coarse = near
                    for c in stride(from: lo, through: hi, by: 4) { let v = score(c); if v > best { best = v; coarse = c } }
                    if (lo...hi).contains(target) { let v = score(target); if v > best { best = v; coarse = target } }
                    start = coarse
                    for c in max(lo, coarse - 3)...min(hi, coarse + 3) { let v = score(c); if v > best { best = v; start = c } }
                }
            } else {
                // Through breaths and consonants, a grain comes from exactly where it belongs: noise
                // has no cycle to line up, and this keeps the gaps between notes where they were.
                nominal = nominal.rounded()
            }
            let out = nominals.count * hop
            for c in padded.indices {
                if stretched[c].count < out + size { stretched[c] += [Float](repeating: 0, count: out + size - stretched[c].count) }
                for i in 0..<size { stretched[c][out + i] += padded[c][start + i] * window[i] }
            }
            nominals.append(nominal)
            prev = start
            nominal += Double(hop) / ratio(nominal + Double(hop))
        }

        guard nominals.count >= 2 else { return channels }
        // Read back: output sample i is the stretched point that came from input position i, which
        // goes through the stretch exactly ratio times faster. Cubic interpolation between samples.
        return stretched.map { st in
            var y = [Float](repeating: 0, count: n)
            var k = 0
            for i in 0..<n {
                let p = Double(pre + i)
                while k + 2 < nominals.count && nominals[k + 1] <= p { k += 1 }
                let s = Double(k * hop) + (p - nominals[k]) * Double(hop) / (nominals[k + 1] - nominals[k])
                let j = Int(floor(s)), f = Float(s - floor(s))
                guard j >= 1, j + 2 < st.count else { continue }
                let a = st[j - 1], b = st[j], c = st[j + 1], d = st[j + 2]
                y[i] = b + 0.5 * f * (c - a + f * (2 * a - 5 * b + 4 * c - d + f * (3 * (b - c) + d - a)))
            }
            return y
        }
    }
}
