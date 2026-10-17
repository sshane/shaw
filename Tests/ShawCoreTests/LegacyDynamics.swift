import Foundation
@testable import ShawCore

// The Limiter, Compressor, and Saturator as they were before the 2026-10 rewrite, kept
// verbatim so tests can compare old and new behavior (THD, aliasing, and levels).

final class LegacyLimiterFX: EffectProcessor {
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
            ol = max(-ceil, min(ceil, ol)); or = max(-ceil, min(ceil, or))
            buf.l[i] = ol; buf.r[i] = or
        }
    }

    func reset() { dl.reset(); dr.reset(); gain = 1 }
}

final class LegacyCompressorFX: EffectProcessor {
    var env: Float = -96
    let sr: Double
    init(sampleRate: Double) { sr = sampleRate }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        let th = Float(p[0]), ratio = Float(p[1])
        let att = Float(exp(-1 / (p[2] / 1000 * sr))), rel = Float(exp(-1 / (p[3] / 1000 * sr)))
        let makeup = Float(dbToGain(p[4])), mix = Float(p[5])
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

final class LegacySaturatorFX: EffectProcessor {
    var lpL = OnePole(), lpR = OnePole()
    var lastTone = -1.0
    let sr: Double
    init(sampleRate: Double) { sr = sampleRate }

    @inline(__always) func shape(_ x: Float, _ t: Int) -> Float {
        switch t {
        case 1: return max(-1, min(1, x))
        case 2: return x >= 0 ? 1 - expf(-x) : -(1 - expf(x)) * 0.8
        case 3: return sinf(x * 0.5 * .pi)
        default: return tanhf(x)
        }
    }

    func process(_ buf: StereoBuffer, frames: Int, params p: [Double], ctx: RenderContext, beat: Double) {
        if p[2] != lastTone { lastTone = p[2]; lpL.setLowpass(p[2], sampleRate: sr); lpR.a = lpL.a }
        let drive = Float(dbToGain(p[0])), t = Int(p[1])
        let comp = 1 / max(1, sqrtf(drive))
        let out = Float(dbToGain(p[3])) * comp, mix = Float(p[4])
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
