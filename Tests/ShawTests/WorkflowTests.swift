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
