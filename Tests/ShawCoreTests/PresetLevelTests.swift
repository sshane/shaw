import XCTest
@testable import ShawCore

/// Keeps presets at similar loudness, so switching presets never jumps 10 dB.
final class PresetLevelTests: XCTestCase {
    let sr = 48000.0

    /// RMS and peak (dBFS) of one note held 1.5 s, through the preset's own effects.
    func level(_ name: String) -> (rms: Double, peak: Double) {
        let s = Synth(sampleRate: sr)
        let params = SynthParams.defs.resolve(SynthPresets.params(for: name))
        let slots = SynthPresets.effects(for: name).compactMap { e -> EffectSlot? in
            guard let d = EffectRegistry.descriptor(e.kind) else { return nil }
            return EffectSlot(processor: d.make(sr), params: d.params.resolve(e.params))
        }
        let chain = EffectChain(slots)
        let buf = StereoBuffer(capacity: 512)
        let ctx = RenderContext(sampleRate: sr, bpm: 128)
        let bass = SynthPresets.categories[name] == "Bass" || name.contains("Bass") || name.contains("808") || name.contains("Reese")
        s.noteOn(bass ? 36 : 60, velocity: 0.8, params: params)
        var sum = 0.0, peak: Float = 0, n = 0
        var beat = 0.0
        for _ in 0..<Int(1.5 * sr / 512) {
            buf.clear(512)
            s.render(buf.l, buf.r, frames: 512, params: params, bpm: 128, beat: beat)
            chain.process(buf, frames: 512, ctx: ctx, beat: beat, time: beat)
            beat += 512 * ctx.beatsPerSample
            for i in 0..<512 {
                let m = (buf.l[i] + buf.r[i]) * 0.5
                sum += Double(m * m); n += 1
                peak = max(peak, abs(buf.l[i]), abs(buf.r[i]))
            }
        }
        return (10 * log10(max(1e-12, sum / Double(n))), 20 * log10(Double(max(peak, 1e-6))))
    }

    func testPresetLevelsAreConsistent() {
        var report = ""
        for name in SynthPresets.names where !["Noise Riser", "Downlifter", "Init"].contains(name) {
            let (rms, peak) = level(name)
            report += String(format: "%-16@ rms %6.1f  peak %6.1f\n", name as NSString, rms, peak)
            XCTAssertLessThan(peak, -3, "\(name) peaks too close to clipping")
            XCTAssertGreaterThan(rms, -40, "\(name) is far too quiet")
        }
        print(report)
    }
}

final class OscillatorTests: XCTestCase {
    func render(_ params: [String: Double]) -> [Float] {
        let s = Synth(sampleRate: 48000)
        let p = SynthParams.defs.resolve(params)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 4800); defer { l.deallocate() }
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 4800); defer { r.deallocate() }
        l.initialize(repeating: 0, count: 4800); r.initialize(repeating: 0, count: 4800)
        s.noteOn(57, velocity: 0.8, params: p)
        s.render(l, r, frames: 4800, params: p)
        return Array(UnsafeBufferPointer(start: l, count: 4800))
    }

    /// The editor rewrites Osc Mix as per-oscillator levels; the sound must not change.
    func testNormalizingLevelsKeepsTheSound() {
        for name in ["Reese Bass", "Pluck", "Lead", "Sub Bass", "Organ", "Growl Bass"] {
            var p = SynthPresets.params(for: name)
            p["drift"] = 0
            let a = render(p), b = render(OscillatorLevels.normalized(p))
            let diff = zip(a, b).map { abs($0 - $1) }.max() ?? 0
            XCTAssertLessThan(diff, 1e-3, "\(name) changed when normalized")
        }
    }

    func testExtraOscillatorsAddSound() {
        var p = SynthPresets.scratch()
        p["drift"] = 0
        let one = render(p)
        p["on3"] = 1; p["osc3"] = 2; p["lvl3"] = 1
        let two = render(p)
        let e1 = one.reduce(0) { $0 + $1 * $1 }, e2 = two.reduce(0) { $0 + $1 * $1 }
        XCTAssertGreaterThan(e2, e1 * 1.3, "osc 3 should add energy")
    }
}
