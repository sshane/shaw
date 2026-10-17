import XCTest
@testable import ShawCore

final class PerfTests: XCTestCase {
    func testRealtimeFactor() {
        var p = Project()
        var assets: [Asset] = []
        for i in 0..<8 {
            var pat = NotePattern(length: 16, instrument: .preset("Supersaw"))
            for b in 0..<4 { for k in [0, 4, 7] { pat.notes.append(Note(pitch: 48 + k + i, start: Double(b * 4), length: 4)) } }
            assets.append(Asset(name: "P\(i)", colorIndex: i, content: .notes(pat)))
        }
        p.assets += assets
        p.updateComposition(p.mainCompositionID) { c in
            c.tracks = assets.map { a in
                var t = Track(name: a.name, colorIndex: 0)
                t.clips = [Clip(assetID: a.id, start: 0, length: 16)]
                t.effects = [EffectRegistry.descriptor("reverb")!.makeEffect(), EffectRegistry.descriptor("delay")!.makeEffect()]
                return t
            }
        }
        let start = Date()
        _ = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 16, sampleRate: 48000)
        let elapsed = Date().timeIntervalSince(start)
        let audio = 16 * 60 / 120.0
        print("PERF: rendered \(audio)s of 8x(3-note 7-voice supersaw + reverb + delay) in \(elapsed)s, \(audio / elapsed)x realtime")
    }

    /// CPU use of the dynamics effects, as a share of one core at 48 kHz. Meaningful in release
    /// builds only: `swift test -c release -Xswiftc -enable-testing --filter PerfTests`.
    func testDynamicsEffectsCPU() {
        let sr = 48000.0, seconds = 10.0, block = 512
        // Loud drums over a bass line, so the limiter and compressor are working the whole time.
        let drums = Measure.drums(seconds: 2)
        let bass = Measure.sine(55, amp: 0.5, seconds: 2)
        let src = zip(drums, bass).map { $0 + $1 }
        let cases: [(String, EffectProcessor, [Double])] = [
            ("Limiter +9 dB", LimiterFX(sampleRate: sr), LimiterFX.params.resolve(["gain": 9])),
            ("Compressor", CompressorFX(sampleRate: sr), CompressorFX.params.resolve(["threshold": -24, "ratio": 4])),
            ("Saturator Soft", SaturatorFX(sampleRate: sr), SaturatorFX.params.resolve(["drive": 12, "type": 0])),
            ("Saturator Hard", SaturatorFX(sampleRate: sr), SaturatorFX.params.resolve(["drive": 12, "type": 1])),
            ("Saturator Tube", SaturatorFX(sampleRate: sr), SaturatorFX.params.resolve(["drive": 12, "type": 2])),
            ("Saturator Fold", SaturatorFX(sampleRate: sr), SaturatorFX.params.resolve(["drive": 12, "type": 3])),
        ]
        let buf = StereoBuffer()
        let ctx = RenderContext(sampleRate: sr, bpm: 120)
        let blocks = Int(seconds * sr) / block
        for (name, fx, params) in cases {
            var elapsed = 0.0
            for b in 0..<blocks {
                let o = (b * block) % (src.count - block)
                for i in 0..<block { buf.l[i] = src[o + i]; buf.r[i] = src[o + i] * 0.9 }
                let t0 = DispatchTime.now().uptimeNanoseconds
                fx.process(buf, frames: block, params: params, ctx: ctx, beat: 0)
                elapsed += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
            }
            let share = elapsed / seconds * 100
            print(String(format: "PERF: %@ uses %.3f%% of one core at 48 kHz", name, share))
            #if !DEBUG
            XCTAssertLessThan(share, name.hasPrefix("Saturator") ? 2 : 1, name)
            #endif
        }
    }
}
