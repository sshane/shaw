import XCTest
import ShawCore
@testable import Shaw

final class WorkflowTests: XCTestCase {
    func emptyStore() -> Store { Store(project: DemoProject.empty(), headless: true) }

    func testNewProjectIsEmptyAndGuided() {
        let s = emptyStore()
        XCTAssertFalse(s.hasContent)
        XCTAssertTrue(s.activeComp!.tracks.isEmpty)
    }

    func testAddInstrumentCreatesTrackClipLoopAndOpensEditor() {
        let s = emptyStore()
        s.addInstrument(.kit("trap"))
        XCTAssertTrue(s.hasContent)
        let comp = s.activeComp!
        XCTAssertEqual(comp.tracks.count, 1)
        XCTAssertEqual(comp.tracks[0].name, "Trap 808")
        let clip = comp.tracks[0].clips[0]
        XCTAssertEqual(s.pianoRollAsset, clip.assetID, "drums open in the piano roll")
        XCTAssertEqual(s.editingClip, clip.id)
        XCTAssertTrue(s.loopEnabled)
        XCTAssertEqual(s.loopStart, clip.start)
        XCTAssertEqual(s.loopEnd, clip.end)

        s.addInstrument(.synth("Pluck"))
        XCTAssertEqual(s.activeComp!.tracks.count, 2)
        XCTAssertEqual(s.activeComp!.tracks[1].clips[0].start, 0, "new layers line up with what's looping")
        XCTAssertEqual(s.focus, .pianoRoll)
    }

    func testSaveVariationKeepsOriginalAndLoopsTheCopy() {
        let s = emptyStore()
        s.addInstrument(.synth("Pluck"))
        let first = s.activeComp!.tracks[0].clips[0]
        s.edit { $0.updateNotes(first.assetID) { $0.notes = [Note(pitch: 60, start: 0, length: 1)] } }

        s.saveVariation()
        let clips = s.activeComp!.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[1].start, first.end, "variation goes right after the original")
        XCTAssertNotEqual(clips[1].assetID, first.assetID, "variation is its own copy")
        XCTAssertEqual(s.pianoRollAsset, clips[1].assetID)
        XCTAssertEqual(s.loopStart, clips[1].start)

        // Editing the variation leaves the original alone.
        s.edit { $0.updateNotes(clips[1].assetID) { $0.notes.append(Note(pitch: 64, start: 2, length: 1)) } }
        if case .notes(let orig)? = s.project.asset(first.assetID)?.content { XCTAssertEqual(orig.notes.count, 1) }

        s.saveVariation()
        s.loopVariationRun()
        XCTAssertEqual(s.loopStart, first.start)
        XCTAssertEqual(s.loopEnd, first.start + 3 * first.length, "Loop All covers all three versions")
        XCTAssertEqual(s.project.asset(s.pianoRollAsset!)?.name, "Pluck 3")
    }

    func testReplaceInstrumentKeepsNotes() {
        let s = emptyStore()
        s.addInstrument(.synth("Pluck"))
        let clip = s.activeComp!.tracks[0].clips[0]
        s.edit { $0.updateNotes(clip.assetID) { $0.notes = [Note(pitch: 62, start: 0, length: 1)] } }
        XCTAssertTrue(s.replaceInstrument(ofAsset: clip.assetID, with: .synth("Pad")))
        guard case .notes(let p)? = s.project.asset(clip.assetID)?.content else { return XCTFail() }
        XCTAssertEqual(p.instrument.preset, "Pad")
        XCTAssertEqual(p.notes.count, 1)
        XCTAssertTrue(s.replaceInstrument(ofAsset: clip.assetID, with: .kit("house")), "drums and synths are both piano-roll patterns")
        guard case .notes(let q)? = s.project.asset(clip.assetID)?.content else { return XCTFail() }
        XCTAssertEqual(q.instrument.kit, "house")
        XCTAssertEqual(q.notes.count, 1)
    }

    func testKeyboardPlaysCurrentInstrument() {
        let s = emptyStore()
        s.addInstrument(.synth("Keys"))
        XCTAssertTrue(s.keyboardKey("a", down: true, isRepeat: false))
        XCTAssertEqual(s.heldKeys["a"]?.pitch, 48, "A plays C3 by default")
        XCTAssertEqual(s.playingPitches, [48], "held key lights up in the piano roll")
        XCTAssertTrue(s.keyboardKey("a", down: false, isRepeat: false))
        XCTAssertTrue(s.playingPitches.isEmpty)
        XCTAssertTrue(s.keyboardKey("x", down: true, isRepeat: false))
        XCTAssertTrue(s.keyboardKey("w", down: true, isRepeat: false))
        XCTAssertEqual(s.heldKeys["w"]?.pitch, 61, "octave up, W is C#4")
        XCTAssertFalse(s.keyboardKey("q", down: true, isRepeat: false), "unmapped keys pass through")
    }

    func testDrumKitKeyboardPlaysSoundsInOrder() {
        let s = emptyStore()
        s.addInstrument(.kit("trap"))
        XCTAssertTrue(s.keyboardKey("s", down: true, isRepeat: false))
        XCTAssertEqual(s.heldKeys["s"]?.pitch, DrumKits.basePitch + 1, "S plays the second sound (snare)")
    }
}

final class ClipboardTests: XCTestCase {
    func store() -> Store { Store(project: DemoProject.empty(), headless: true) }

    func testCopyEffectsOntoSeveralClips() {
        let s = store()
        s.addInstrument(.synth("Pluck"))
        s.addInstrument(.synth("Pad"))
        s.addInstrument(.kit("house"))
        let comp = s.activeComp!
        let a = comp.tracks[0].clips[0], b = comp.tracks[1].clips[0], c = comp.tracks[2].clips[0]
        let host = EffectHost.clip(s.activeCompID, a.id)
        s.addEffect("reverb", to: host)
        s.addEffect("delay", to: host)
        s.selectEffect(s.effects(of: host)[0].id, in: host, extend: false)
        s.selectAllEffects()
        XCTAssertEqual(s.selectedEffects.count, 2, "⌘A selects every effect on the layer")
        XCTAssertTrue(s.copySelection())

        s.focus = .timeline
        s.selectedClips = [b.id, c.id]
        XCTAssertTrue(s.paste())
        for k in [b, c] {
            let fx = s.effects(of: .clip(s.activeCompID, k.id))
            XCTAssertEqual(fx.map(\.kind), ["reverb", "delay"], "pasted in stack order")
            XCTAssertFalse(fx.contains { e in s.effects(of: host).contains { $0.id == e.id } }, "pasted effects get new ids")
        }
        s.undo()
        XCTAssertTrue(s.effects(of: .clip(s.activeCompID, b.id)).isEmpty, "one paste is one undo step")
    }

    func testReorderAndCopyByDragging() {
        let s = store()
        s.addInstrument(.synth("Pluck"))
        s.addInstrument(.synth("Pad"))
        let comp = s.activeComp!
        let t0 = EffectHost.track(s.activeCompID, comp.tracks[0].id), t1 = EffectHost.track(s.activeCompID, comp.tracks[1].id)
        s.addEffect("reverb", to: t0)
        s.addEffect("delay", to: t0)
        let fx = s.effects(of: t0)
        s.dropEffect(fx[1].id, onto: t0, before: fx[0].id)
        XCTAssertEqual(s.effects(of: t0).map(\.kind), ["delay", "reverb"], "dragging within a layer reorders")
        s.dropEffect(fx[0].id, onto: t1, before: nil)
        XCTAssertEqual(s.effects(of: t1).map(\.kind), ["reverb"], "dragging to another layer copies")
        XCTAssertEqual(s.effects(of: t0).count, 2)
    }

    func testCopyPasteClipsAtPlayhead() {
        let s = store()
        s.addInstrument(.synth("Pluck"))
        let clip = s.activeComp!.tracks[0].clips[0]
        s.focus = .timeline
        s.selectedClips = [clip.id]
        XCTAssertTrue(s.copySelection())
        s.seek(8)
        s.paste()
        let clips = s.activeComp!.tracks[0].clips
        XCTAssertEqual(clips.count, 2)
        XCTAssertTrue(clips.contains { $0.start == 8 && $0.assetID == clip.assetID }, "pasted clip is linked, at the playhead")
    }
}

final class KeyframeWorkflowTests: XCTestCase {
    func store() -> Store { Store(project: DemoProject.empty(), headless: true) }

    func testStopwatchThenChangeValueAddsKeyframes() {
        let s = store()
        s.addInstrument(.synth("Sub Bass"))
        let clip = s.activeComp!.tracks[0].clips[0]
        let host = EffectHost.clip(s.activeCompID, clip.id)
        s.addEffect("volume", to: host)
        let fx = s.effects(of: host)[0]
        s.seek(0)
        s.toggleAnimation(host, effect: fx.id, param: "volume")
        s.setParam(host, effect: fx.id, param: "volume", value: -60, live: false)
        s.seek(2)
        s.setParam(host, effect: fx.id, param: "volume", value: 0, live: false)
        let keys = s.effect(fx.id, in: host)!.keyframes["volume"]!
        XCTAssertEqual(keys.map(\.time), [0, 2])
        XCTAssertEqual(keys.map(\.value), [-60, 0])
        XCTAssertTrue(s.expandedTracks.contains(s.activeComp!.tracks[0].id), "keyframe rows open automatically")
        XCTAssertEqual(s.trackLayout(for: s.activeComp!).heights[0], s.trackHeight + TrackLayout.propRowHeight)

        s.selectedKeyframes = [keys[0].id, keys[1].id]
        s.deleteSelectedKeyframes()
        let e = s.effect(fx.id, in: host)!
        XCTAssertFalse(e.isAnimated("volume"))
        XCTAssertEqual(e.params["volume"], 0, "deleting the last keyframes keeps the last value")
    }

    func testFadeInFromClipMenu() {
        let s = store()
        s.addInstrument(.synth("Sub Bass"))
        let clip = s.activeComp!.tracks[0].clips[0]
        s.addFade(clip: clip.id, fadeIn: true)
        s.addFade(clip: clip.id, fadeIn: false)
        let fx = s.effects(of: .clip(s.activeCompID, clip.id))
        XCTAssertEqual(fx.count, 1, "fade in and out share one Volume effect")
        XCTAssertEqual(fx[0].keyframes["volume"]?.count, 4)
        XCTAssertEqual(fx[0].keyframes["volume"]?.first?.value, -60)
    }

    func testSwapInstrumentRenamesAutoNamedPatternAndLayer() {
        let s = store()
        s.addInstrument(.synth("Pluck"))
        let clip = s.activeComp!.tracks[0].clips[0]
        s.replaceInstrument(ofAsset: clip.assetID, with: .synth("Pad"))
        XCTAssertEqual(s.project.asset(clip.assetID)?.name, "Pad")
        XCTAssertEqual(s.activeComp!.tracks[0].name, "Pad")
        s.replaceInstrument(ofAsset: clip.assetID, with: .kit("trap"))
        XCTAssertEqual(s.project.asset(clip.assetID)?.name, "Trap 808 Beat")

        s.renameAsset(clip.assetID, to: "My Groove")
        s.replaceInstrument(ofAsset: clip.assetID, with: .synth("Keys"))
        XCTAssertEqual(s.project.asset(clip.assetID)?.name, "My Groove", "names you chose are kept")
    }
}

final class EditSafetyTests: XCTestCase {
    /// Regression: typing a pattern length crashed (reading the project inside its own edit).
    func testEditsMayReadTheProject() {
        let s = Store(project: DemoProject.empty(), headless: true)
        s.addInstrument(.synth("808 Bass"))
        let id = s.pianoRollAsset!
        s.live { $0.updateNotes(id) { $0.length = 3 * Double(s.project.beatsPerBar) } }
        s.endGesture()
        s.edit { $0.updateComposition(s.activeCompID) { $0.length = 2 * Double(s.project.beatsPerBar) } }
        if case .notes(let p)? = s.project.asset(id)?.content { XCTAssertEqual(p.length, 12) }
        XCTAssertEqual(s.activeComp?.length, 8)
    }
}

final class MergeTests: XCTestCase {
    /// Three separate one-bar 808 clips on one layer, one note each.
    func threeBasses() -> (Store, [UUID]) {
        let s = Store(project: DemoProject.empty(), headless: true)
        s.addInstrument(.synth("808 Bass"))
        let first = s.activeComp!.tracks[0].clips[0]
        s.edit { $0.updateNotes(first.assetID) { $0.notes = [Note(pitch: 33, start: 0, length: 2)] } }
        s.selectedClips = [first.id]
        s.saveVariation()
        s.saveVariation()
        let clips = s.activeComp!.tracks[0].clips.sorted { $0.start < $1.start }
        for (i, c) in clips.enumerated() {
            s.edit { $0.updateNotes(c.assetID) { $0.notes = [Note(pitch: 33 + i * 3, start: 0, length: 2)] } }
        }
        return (s, clips.map(\.id))
    }

    func testMergeIntoOneLinkedClipSoundsTheSame() {
        let (s, ids) = threeBasses()
        let main = s.project.mainCompositionID
        let patternsBefore = s.project.assets.filter { $0.kind == .notes }.count
        let (before, _) = OfflineRenderer.renderToMemory(project: s.project, composition: main, beats: 12)
        s.selectedClips = Set(ids)
        XCTAssertNil(s.mergeProblem(s.selectedClips))
        s.mergeSelectedClips()
        let clips = s.activeComp!.tracks[0].clips
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips[0].start, 0)
        XCTAssertEqual(clips[0].length, 12)
        guard case .notes(let p)? = s.project.asset(clips[0].assetID)?.content else { return XCTFail() }
        XCTAssertEqual(p.notes.map(\.start), [0, 4, 8])
        XCTAssertEqual(p.notes.map(\.pitch), [33, 36, 39])
        XCTAssertEqual(s.project.assets.filter { $0.kind == .notes }.count, patternsBefore - 2, "three patterns become one")
        let (after, _) = OfflineRenderer.renderToMemory(project: s.project, composition: main, beats: 12)
        // Synth oscillators start at random phases, so compare loudness beat by beat, not samples.
        let fpb = Int(48000 * 60 / s.project.bpm)
        func rms(_ x: [Float], _ b: Int) -> Float {
            let seg = x[(b * fpb)..<min(x.count, (b + 1) * fpb)]
            return sqrt(seg.reduce(0) { $0 + $1 * $1 } / Float(max(1, seg.count)))
        }
        for b in 0..<12 {
            let a = rms(before, b), c = rms(after, b)
            XCTAssertLessThan(abs(a - c), max(0.01, a * 0.1), "beat \(b) should sound the same after merging")
        }
        s.undo()
        XCTAssertEqual(s.activeComp!.tracks[0].clips.count, 3, "one undo brings the three clips back")
    }

    func testMergeIsStrict() {
        let (s, ids) = threeBasses()
        XCTAssertNotNil(s.mergeProblem([ids[0]]), "needs two or more")
        s.replaceInstrument(ofAsset: s.clip(ids[2])!.assetID, with: .synth("Pluck"))
        XCTAssertEqual(s.mergeProblem(Set(ids)), "Clips use different instruments")
        XCTAssertNil(s.mergeProblem([ids[0], ids[1]]))
        s.addEffect("reverb", to: .clip(s.activeCompID, ids[0]))
        XCTAssertEqual(s.mergeProblem([ids[0], ids[1]]), "Clips have different effects")

        s.addInstrument(.synth("808 Bass"))
        let other = s.activeComp!.tracks[1].clips[0].id
        XCTAssertEqual(s.mergeProblem([ids[1], other]), "Clips are on different layers")
    }

    func testAudibleNotesHonourTrimAndLoop() {
        var p = NotePattern(length: 4)
        p.notes = [Note(pitch: 60, start: 0, length: 1), Note(pitch: 62, start: 2, length: 1)]
        var trimmed = Clip(assetID: UUID(), start: 0, length: 2, offset: 2)
        XCTAssertEqual(Store.audibleNotes(of: trimmed, pattern: p).map(\.pitch), [62], "only what's inside the trimmed window")
        trimmed.loops = true
        trimmed.length = 8
        XCTAssertEqual(Store.audibleNotes(of: trimmed, pattern: p).map(\.start), [0, 2, 4, 6], "looping repeats it")
    }
}
