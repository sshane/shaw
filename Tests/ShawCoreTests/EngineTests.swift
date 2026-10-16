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
            // Slow-attack presets (the riser fades in over seconds) get longer to speak.
            let blocks = name == "Noise Riser" ? 900 : 60
            for _ in 0..<blocks {
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

final class DrumKitPatternTests: XCTestCase {
    func testKitPatternPlaysAndMatchesConvertedBeat() {
        var d = DrumPattern(kit: "house", steps: 16)
        d.rows[0].steps[0] = 1; d.rows[0].steps[8] = 1 // kicks
        d.rows[1].steps[4] = 0.8                        // snare
        let notes = d.asNotePattern()
        XCTAssertEqual(notes.instrument.kit, "house")
        XCTAssertEqual(Set(notes.notes.map(\.pitch)), [36, 37])
        XCTAssertEqual(notes.notes.count, 3)

        var p = Project()
        let a = Asset(name: "B", colorIndex: 0, content: .drums(d))
        p.assets.append(a)
        p.updateComposition(p.mainCompositionID) { c in
            var t = Track(name: "D", colorIndex: 0)
            t.clips = [Clip(assetID: a.id, start: 0, length: 4)]
            c.tracks = [t]
        }
        let (before, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 4)
        p.migrateDrumPatterns()
        guard case .notes? = p.asset(a.id)?.content else { return XCTFail("should be a note pattern now") }
        let (after, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 4)
        var diff: Float = 0
        for i in 0..<before.count { diff = max(diff, abs(before[i] - after[i])) }
        XCTAssertLessThan(diff, 0.001, "converted beat should sound identical")
    }
}

final class KeyframeTests: XCTestCase {
    func rms(_ x: ArraySlice<Float>) -> Float { sqrt(x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))) }

    func testInterpolation() {
        let keys = [Keyframe(time: 0, value: -60), Keyframe(time: 4, value: 0)]
        XCTAssertEqual(Keyframe.interpolate(keys, at: -1, hold: false), -60)
        XCTAssertEqual(Keyframe.interpolate(keys, at: 2, hold: false), -30)
        XCTAssertEqual(Keyframe.interpolate(keys, at: 9, hold: false), 0)
        XCTAssertEqual(Keyframe.interpolate(keys, at: 3.9, hold: true), -60)
    }

    func testVolumeFadeInFollowsTheClip() {
        func render(clipStart: Double) -> [Float] {
            var p = Project(bpm: 120)
            var n = NotePattern(length: 8, instrument: .preset("Sub Bass"))
            n.notes = [Note(pitch: 40, start: 0, length: 8)]
            let a = Asset(name: "Bass", colorIndex: 0, content: .notes(n))
            p.assets.append(a)
            var fade = EffectRegistry.descriptor("volume")!.makeEffect()
            fade.keyframes["volume"] = [Keyframe(time: 0, value: -60), Keyframe(time: 4, value: 0)]
            var clip = Clip(assetID: a.id, start: clipStart, length: 8)
            clip.effects = [fade]
            p.updateComposition(p.mainCompositionID) { c in
                var t = Track(name: "Bass", colorIndex: 0)
                t.clips = [clip]
                c.tracks = [t]
            }
            return OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: clipStart + 8).0
        }
        let fpb = 24000 // 120 BPM at 48 kHz
        let out = render(clipStart: 0)
        let q1 = rms(out[0..<fpb]), q2 = rms(out[fpb * 2..<fpb * 3]), q3 = rms(out[fpb * 5..<fpb * 6])
        XCTAssertLessThan(q1, q2, "fade rises")
        XCTAssertLessThan(q2, q3, "fade keeps rising until full")
        XCTAssertLessThan(q1, q3 * 0.1)

        // Keyframes are in clip time: move the clip and the fade moves with it.
        let moved = render(clipStart: 4)
        let m1 = rms(moved[fpb * 4..<fpb * 5]), m3 = rms(moved[fpb * 9..<fpb * 10])
        XCTAssertLessThan(m1, m3 * 0.1)
    }

    func testOldProjectsWithoutKeyframesStillLoad() throws {
        let json = #"{"id":"\#(UUID().uuidString)","kind":"reverb","enabled":true,"params":{"mix":0.3},"expanded":true}"#
        let e = try JSONDecoder().decode(Effect.self, from: Data(json.utf8))
        XCTAssertTrue(e.keyframes.isEmpty)
        XCTAssertEqual(e.params["mix"], 0.3)
    }
}
