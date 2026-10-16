import XCTest
@testable import ShawCore

final class EngineTests: XCTestCase {
    let sr = 48000.0

    func rms(_ x: [Float], from: Int, to: Int) -> Float {
        let s = max(0, from), e = min(x.count, to)
        guard e > s else { return 0 }
        var acc: Float = 0
        for i in s..<e { acc += x[i] * x[i] }
        return sqrt(acc / Float(e - s))
    }

    func frames(_ beats: Double, bpm: Double = 120) -> Int { Int(beats * sr * 60 / bpm) }

    /// Main contains composition "Inner" twice; Inner contains a kick on beat 0.
    func makeLinkedProject() -> (Project, AssetID, AssetID) {
        var p = Project()
        var drums = DrumPattern(steps: 4, stepsPerBeat: 4)
        drums.rows[0].steps[0] = 1 // kick on the first step
        let beat = Asset(name: "Beat", colorIndex: 1, content: .drums(drums))
        var inner = Composition(length: 4)
        var t = Track(name: "Drums", colorIndex: 1)
        t.clips = [Clip(assetID: beat.id, start: 0, length: 1)]
        inner.tracks = [t]
        let innerAsset = Asset(name: "Inner", colorIndex: 2, content: .composition(inner))
        p.assets += [beat, innerAsset]
        p.updateComposition(p.mainCompositionID) { c in
            var mt = Track(name: "Comp", colorIndex: 2)
            mt.clips = [Clip(assetID: innerAsset.id, start: 0, length: 4), Clip(assetID: innerAsset.id, start: 8, length: 4)]
            c.tracks = [mt]
        }
        return (p, innerAsset.id, beat.id)
    }

    func testLinkedCompositionsPlayInEveryInstance() {
        let (p, _, _) = makeLinkedProject()
        let (l, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 16, sampleRate: sr)
        XCTAssertGreaterThan(rms(l, from: 0, to: frames(0.5)), 0.01, "first instance should play")
        XCTAssertLessThan(rms(l, from: frames(5), to: frames(8)), 0.001, "gap should be silent")
        XCTAssertGreaterThan(rms(l, from: frames(8), to: frames(8.5)), 0.01, "second instance should play")
    }

    func testEditingSourcePropagatesToAllInstances() {
        var (p, _, beatID) = makeLinkedProject()
        p.updateDrums(beatID) { $0.rows[0].steps[0] = 0 }
        let (l, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 16, sampleRate: sr)
        XCTAssertLessThan(rms(l, from: 0, to: l.count), 0.0001)
    }

    func testCompositionEffectsApplyAfterInner() {
        var (p, innerID, _) = makeLinkedProject()
        let original = p
        var util = EffectRegistry.descriptor("utility")!.makeEffect()
        util.params["gain"] = -36
        p.updateComposition(innerID) { $0.effects = [util] }
        let (quiet, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 1, sampleRate: sr)
        let (loud, _) = OfflineRenderer.renderToMemory(project: original, composition: original.mainCompositionID, beats: 1, sampleRate: sr)
        XCTAssertLessThan(rms(quiet, from: 0, to: quiet.count) * 20, rms(loud, from: 0, to: loud.count))
    }

    func testTrimPastEndIsSilentButLoopRepeats() {
        var p = Project()
        var notes = NotePattern(length: 1, instrument: .preset("Pluck"))
        notes.notes = [Note(pitch: 60, start: 0, length: 0.25)]
        let pat = Asset(name: "P", colorIndex: 3, content: .notes(notes))
        p.assets.append(pat)
        func render(loops: Bool) -> [Float] {
            var q = p
            q.updateComposition(q.mainCompositionID) { c in
                var t = Track(name: "Synth", colorIndex: 3)
                t.clips = [Clip(assetID: pat.id, start: 0, length: 8, loops: loops)]
                c.tracks = [t]
            }
            return OfflineRenderer.renderToMemory(project: q, composition: q.mainCompositionID, beats: 8, sampleRate: sr).0
        }
        let trimmed = render(loops: false), looped = render(loops: true)
        XCTAssertLessThan(rms(trimmed, from: frames(4), to: frames(4.3)), 0.0005)
        XCTAssertGreaterThan(rms(looped, from: frames(4), to: frames(4.3)), 0.005)
    }

    func testAllEffectsStayFinite() {
        for d in EffectRegistry.all {
            let proc = d.make(sr)
            let buf = StereoBuffer()
            let params = d.params.resolve([:])
            let ctx = RenderContext(sampleRate: sr, bpm: 128)
            for block in 0..<200 {
                for i in 0..<512 {
                    let t = Float(block * 512 + i)
                    buf.l[i] = sinf(t * 0.05) * 0.8
                    buf.r[i] = (block % 7 == 0 && i == 0) ? 1 : sinf(t * 0.031) * 0.5
                }
                proc.process(buf, frames: 512, params: params, ctx: ctx, beat: Double(block) * 0.1)
                for i in 0..<512 {
                    XCTAssert(buf.l[i].isFinite && buf.r[i].isFinite, "\(d.name) produced non-finite output")
                    XCTAssertLessThan(abs(buf.l[i]), 8, "\(d.name) exploded")
                }
            }
        }
    }

    func testEverySynthPresetMakesSound() {
        for name in SynthPresets.names {
            let s = Synth(sampleRate: sr)
            let params = SynthParams.defs.resolve(SynthPresets.params(for: name))
            let l = UnsafeMutablePointer<Float>.allocate(capacity: 512); defer { l.deallocate() }
            let r = UnsafeMutablePointer<Float>.allocate(capacity: 512); defer { r.deallocate() }
            s.noteOn(48, velocity: 0.9, params: params)
            var energy: Float = 0
            for _ in 0..<60 {
                l.initialize(repeating: 0, count: 512); r.initialize(repeating: 0, count: 512)
                s.render(l, r, frames: 512, params: params)
                for i in 0..<512 { XCTAssert(l[i].isFinite); energy += l[i] * l[i] }
            }
            XCTAssertGreaterThan(energy, 1, "\(name) is silent")
        }
    }

    func testDrumKitsGenerateEveryVoice() {
        for kit in DrumKits.kits {
            for v in DrumKits.voices {
                let s = DrumKits.sample(kit: kit.id, voice: v.id, sampleRate: sr)
                XCTAssertNotNil(s)
                XCTAssertGreaterThan(s!.frames, 100)
            }
        }
    }

    func testCycleDetection() {
        let (p, innerID, _) = makeLinkedProject()
        XCTAssertTrue(p.composition(p.mainCompositionID, contains: innerID))
        XCTAssertFalse(p.composition(innerID, contains: p.mainCompositionID))
    }

    func testProjectRoundTripsThroughJSON() throws {
        let (p, _, _) = makeLinkedProject()
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(p, back)
    }
}
