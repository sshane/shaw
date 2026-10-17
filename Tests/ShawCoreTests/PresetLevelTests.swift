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
