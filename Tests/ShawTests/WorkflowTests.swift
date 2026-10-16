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
