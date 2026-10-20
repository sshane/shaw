import Foundation

// MARK: - Blur Delay

/// Echoes that smear, turn around, and bloom into a reverb wash.
///
/// A tempo-synced delay whose feedback runs through a short allpass diffuser (each repeat comes
/// back blurrier than the last) and a tone filter (each one darker). The echoes also feed a
/// reverser, which plays them backwards in overlapping, crossfaded windows; Reverse blends the
/// two. Then the echoes go through a reverb: Blur sets how much of them washes out, Decay how long.
/// Like the other space effects, it allocates everything in `init` and nothing on the audio thread.
final class BlurDelayFX: EffectProcessor {
    static let params = [
        ParamDef.choice("time", "Time", SyncDivision.names, 6),
        ParamDef("feedback", "Feedback", 0, 0.95, 0.5, .percent),
        ParamDef("reverse", "Reverse", 0, 1, 0.35, .percent),
        ParamDef("blur", "Blur", 0, 1, 0.5, .percent),
        ParamDef("decay", "Decay", 0, 1, 0.6, .percent),
        ParamDef("tone", "Tone", 500, 16000, 5000, .hz, .log),
        ParamDef.choice("pingpong", "Ping-Pong", ["Off", "On"], 1),
        ParamDef("mix", "Dry/Wet", 0, 1, 0.3, .percent),
    ]

    static let chunk = 32
    /// Allpass lengths for the diffuser in each side's feedback path, ms (different per side,
    /// so the smear spreads the stereo image instead of collapsing it).
    static let diffuseMs: [[Double]] = [[7.1, 12.7, 23.3], [7.9, 13.9, 21.7]]

    let sr: Float
    // The echo line.
    let lineL: UnsafeMutablePointer<Float>, lineR: UnsafeMutablePointer<Float>
    let lineLen: Int, lineMask: Int
    var w = 0
    var delay = ControlGlide(0)
    // The diffuser: three allpasses a side.
    let apBuf: [UnsafeMutablePointer<Float>]
    let apLen: [Int]
    var apPos = [Int](repeating: 0, count: 6)
    // The reverser: the echoes go in, and two heads read them backwards, half a window apart.
    let revL: UnsafeMutablePointer<Float>, revR: UnsafeMutablePointer<Float>
    let revLen: Int, revMask: Int
    var rw = 0
    /// Each head's place in its window, where its window started, and how long it is. A head picks
    /// up a new window length only when it starts over, so changing the time never makes it jump.
    var phase = (0, 0), anchor = (0, 0), span = (1, 1)
    // Feedback filters and the reverb the echoes bloom into.
    var toneL = SVF(), toneR = SVF(), lowL = SVF(), lowR = SVF()
    var tone = ControlGlide(5000)
    var feedback = ControlGlide(0.5), reverse = ControlGlide(0.35), blur = ControlGlide(0.5), mix = ControlGlide(0.3)
    let reverb: ReverbFX
    let wet: StereoBuffer
    var primed = false

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        lineLen = Self.powerOfTwo(Int(sampleRate * 5) + 4)
        lineMask = lineLen - 1
        lineL = .allocate(capacity: lineLen); lineL.initialize(repeating: 0, count: lineLen)
        lineR = .allocate(capacity: lineLen); lineR.initialize(repeating: 0, count: lineLen)
        var bufs: [UnsafeMutablePointer<Float>] = [], lens: [Int] = []
        for side in Self.diffuseMs {
            for ms in side {
                let n = max(1, Int(ms * sampleRate / 1000))
                let b = UnsafeMutablePointer<Float>.allocate(capacity: n)
                b.initialize(repeating: 0, count: n)
                bufs.append(b); lens.append(n)
            }
        }
        apBuf = bufs; apLen = lens
        // Windows of up to a second, read up to two windows back.
        revLen = Self.powerOfTwo(Int(sampleRate * 2.2))
        revMask = revLen - 1
        revL = .allocate(capacity: revLen); revL.initialize(repeating: 0, count: revLen)
        revR = .allocate(capacity: revLen); revR.initialize(repeating: 0, count: revLen)
        reverb = ReverbFX(sampleRate: sampleRate)
        wet = StereoBuffer()
        lowL.set(cutoff: 110, resonance: 0.3, sampleRate: sr); lowR.copyCoefficients(lowL)
    }

    deinit {
        lineL.deallocate(); lineR.deallocate(); revL.deallocate(); revR.deallocate()
        for b in apBuf { b.deallocate() }
    }

    private static func powerOfTwo(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    /// Linear below the knee, then a smooth bend toward the ceiling, so the loop can't run away.
    @inline(__always) private static func limit(_ x: Float) -> Float {
        let ax = abs(x)
        if ax <= 0.6 { return x }
        let y = 0.6 + 0.5 * tanhf((ax - 0.6) / 0.5)
        return x < 0 ? -y : y
    }

    /// One Schroeder allpass: smears without coloring the overall tone.
    @inline(__always) private func allpass(_ x: Float, _ i: Int, _ g: Float) -> Float {
        let b = apBuf[i], pos = apPos[i]
        let d = b[pos]
        let y = d - g * x
        b[pos] = x + g * y
        apPos[i] = pos + 1 == apLen[i] ? 0 : pos + 1
        return y
    }

    /// Reads the echo line `d` samples back, between samples.
    @inline(__always) private func read(_ line: UnsafeMutablePointer<Float>, _ d: Float) -> Float {
        let pos = Float(w) - d
        let i = Int(floorf(pos)), t = pos - floorf(pos)
        let m = lineMask
        return lagrange4(line[(i - 1) & m], line[i & m], line[(i + 1) & m], line[(i + 2) & m], t)
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let div = SyncDivision.beats[max(0, min(SyncDivision.beats.count - 1, Int(p[0])))]
        let seconds = min(div * 60 / ctx.bpm, 4.9)
        delay.target = Float(seconds) * sr
        feedback.target = Float(p[1]); reverse.target = Float(p[2]); blur.target = Float(p[3])
        tone.target = Float(p[5]); mix.target = Float(p[7])
        let ping = p[6] > 0.5
        // The reverse window follows the echo time, between a tenth of a second and a second.
        let win = max(Int(0.1 * sr), min(Int(sr), Int(delay.target)))
        if !primed {
            primed = true
            delay.snap(delay.target); feedback.snap(feedback.target); reverse.snap(reverse.target)
            blur.snap(blur.target); tone.snap(tone.target); mix.snap(mix.target)
            toneL.set(cutoff: tone.value, resonance: 0.2, sampleRate: sr); toneR.copyCoefficients(toneL)
            span = (win, win)
            phase = (0, win / 2)
        }

        var start = 0
        while start < frames {
            let n = min(Self.chunk, frames - start)
            let k = 1 - expf(-Float(n) / (0.04 * sr))
            if tone.step(k) { toneL.set(cutoff: tone.value, resonance: 0.2, sampleRate: sr); toneR.copyCoefficients(toneL) }
            let d0 = delay.value, fb0 = feedback.value, rev0 = reverse.value
            _ = delay.step(k); _ = feedback.step(k); _ = reverse.step(k); _ = blur.step(k)
            let inv = 1 / Float(n)
            let dStep = (delay.value - d0) * inv, fbStep = (feedback.value - fb0) * inv, revStep = (reverse.value - rev0) * inv
            // More blur, more smear in every repeat.
            let g = 0.62 * blur.value
            let l = buf.l + start, r = buf.r + start
            for j in 0..<n {
                let jf = Float(j)
                let d = max(4, d0 + dStep * jf), fb = fb0 + fbStep * jf, rv = rev0 + revStep * jf
                let eL = read(lineL, d), eR = read(lineR, d)
                // The repeat going back in: diffused, darkened, kept out of the low end, and limited.
                var fL = allpass(allpass(allpass(eL, 0, g), 1, g), 2, g)
                var fR = allpass(allpass(allpass(eR, 3, g), 4, g), 5, g)
                fL = lowL.process(toneL.process(fL).0).2
                fR = lowR.process(toneR.process(fR).0).2
                fL = Self.limit(fL * fb); fR = Self.limit(fR * fb)
                let inL = l[j], inR = r[j]
                if ping {
                    lineL[w] = (inL + inR) * 0.5 + fR
                    lineR[w] = fL
                } else {
                    lineL[w] = inL + fL
                    lineR[w] = inR + fR
                }
                w = (w + 1) & lineMask

                // The reverser: each head reads its last window backwards, faded in and out, half a
                // window apart, so the two always sum to a steady level.
                revL[rw] = eL; revR[rw] = eR
                rw = (rw + 1) & revMask
                var bL: Float = 0, bR: Float = 0
                for h in 0..<2 {
                    var ph = h == 0 ? phase.0 : phase.1
                    var an = h == 0 ? anchor.0 : anchor.1
                    var sp = h == 0 ? span.0 : span.1
                    if ph == 0 { an = rw; sp = max(win, 2) }
                    let x = sinf(Float.pi * Float(ph) / Float(sp))
                    let gain = x * x
                    let idx = (an - 1 - ph) & revMask
                    bL += revL[idx] * gain; bR += revR[idx] * gain
                    ph += 1
                    if ph >= sp { ph = 0 }
                    if h == 0 { phase.0 = ph; anchor.0 = an; span.0 = sp } else { phase.1 = ph; anchor.1 = an; span.1 = sp }
                }
                wet.l[start + j] = eL + (bL - eL) * rv
                wet.r[start + j] = eR + (bR - eR) * rv
            }
            start += n
        }
        // The bloom: the echoes through a reverb, Blur deciding how much of them washes out.
        let size = 0.35 + 0.6 * p[4]
        reverb.process(wet, frames: frames, params: [size, 0.55, 0, 150, 1, Double(min(1, blur.value * 1.1))], ctx: ctx, beat: beat)

        // Out: the dry signal, with the echoes mixed in.
        let m0 = mix.value
        _ = mix.step(1 - expf(-Float(frames) / (0.04 * sr)))
        let mStep = (mix.value - m0) / Float(max(frames, 1))
        for i in 0..<frames {
            let m = m0 + mStep * Float(i)
            buf.l[i] = buf.l[i] * (1 - m * 0.5) + wet.l[i] * m
            buf.r[i] = buf.r[i] * (1 - m * 0.5) + wet.r[i] * m
        }
    }

    func reset() {
        lineL.update(repeating: 0, count: lineLen); lineR.update(repeating: 0, count: lineLen)
        revL.update(repeating: 0, count: revLen); revR.update(repeating: 0, count: revLen)
        for (b, n) in zip(apBuf, apLen) { b.update(repeating: 0, count: n) }
        toneL.reset(); toneR.reset(); lowL.reset(); lowR.reset()
        reverb.reset()
        phase = (0, span.0 / 2)
    }
}
