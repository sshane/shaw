import XCTest
@testable import ShawCore
@testable import Shaw

/// Writing and editing melodies with the keyboard alone (Store+StepEntry.swift).
final class StepEntryTests: XCTestCase {
    func store(drums: Bool = false) -> (Store, AssetID) {
        let s = Store(project: DemoProject.empty(), headless: true)
        let id = drums ? s.newBeat(kit: "house") : s.newPattern(preset: "Keys", bars: 1)
        s.open(asset: id)
        return (s, id)
    }

    func notes(_ s: Store, _ id: AssetID) -> [Note] {
        guard case .notes(let p)? = s.project.asset(id)?.content else { return [] }
        return p.notes.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    func tap(_ s: Store, _ key: String) {
        XCTAssertTrue(s.keyboardKey(key, down: true, isRepeat: false))
        XCTAssertTrue(s.keyboardKey(key, down: false, isRepeat: false))
    }

    func testTypingPlacesNotesOneAfterAnother() {
        let (s, id) = store()
        s.startTyping()
        s.setStepLength(1) // eighth notes
        for k in ["d", "f", "g"] { tap(s, k) }
        s.stepForward() // a rest
        tap(s, "g")
        XCTAssertEqual(notes(s, id).map(\.pitch), [52, 53, 55, 55])
        XCTAssertEqual(notes(s, id).map(\.start), [0, 0.5, 1, 2])
        XCTAssertEqual(notes(s, id).map(\.length), [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(s.rollCursor, 2.5)
        s.undo()
        XCTAssertEqual(notes(s, id).count, 3, "each note is its own undo step")
    }

    func testKeysTogetherMakeAChordButRolloverDoesNot() {
        let (s, id) = store()
        s.startTyping()
        s.lastNoteLength = 1
        for k in ["a", "d", "g"] { XCTAssertTrue(s.keyboardKey(k, down: true, isRepeat: false)) }
        for k in ["a", "d", "g"] { _ = s.keyboardKey(k, down: false, isRepeat: false) }
        XCTAssertEqual(notes(s, id).map(\.start), [0, 0, 0])
        XCTAssertEqual(notes(s, id).map(\.pitch), [48, 52, 55])
        XCTAssertEqual(s.rollCursor, 1)
        // Pressing the next key a moment later, before letting go of the last one, is the next note.
        s.typeNote(60, key: "k", now: 10)
        s.typeNote(62, key: "l", now: 10.3)
        XCTAssertEqual(notes(s, id).filter { $0.pitch >= 60 }.map(\.start), [1, 2])
    }

    func testHoldingAKeyAndPressingRightMakesItLonger() {
        let (s, id) = store()
        s.startTyping()
        s.lastNoteLength = 0.5
        XCTAssertTrue(s.keyboardKey("a", down: true, isRepeat: false))
        s.stepForward()
        s.stepForward()
        _ = s.keyboardKey("a", down: false, isRepeat: false)
        XCTAssertEqual(notes(s, id).map(\.length), [1.5])
        XCTAssertEqual(s.rollCursor, 1.5)
    }

    func testDeleteErasesBackwardsLikeText() {
        let (s, id) = store()
        s.startTyping()
        s.lastNoteLength = 0.5
        tap(s, "a")
        tap(s, "s")
        s.stepForward() // C, D, then a rest: the cursor is at 1.5
        s.stepBackspace()
        XCTAssertEqual(s.rollCursor, 1, "steps back through the rest first")
        XCTAssertEqual(notes(s, id).count, 2)
        s.stepBackspace()
        XCTAssertEqual(notes(s, id).map(\.pitch), [48])
        XCTAssertEqual(s.rollCursor, 0.5)
    }

    func testUpAndDownNudgeTheNoteJustTyped() {
        let (s, id) = store()
        s.startTyping()
        tap(s, "a")
        s.stepNudge(1)
        s.stepNudge(12)
        XCTAssertEqual(notes(s, id).map(\.pitch), [61])
    }

    func testTypingPastTheEndGrowsThePattern() {
        let (s, id) = store() // one bar of 4 beats
        s.startTyping()
        s.setStepLength(3) // half notes
        for k in ["a", "s", "d"] { tap(s, k) }
        guard case .notes(let p)? = s.project.asset(id)?.content else { return XCTFail("no pattern") }
        XCTAssertEqual(p.length, 8, "grew by a bar so the last note isn't cut off")
    }

    func testReturnStartsAfterTheSelectionAndOtherPanelsStopTyping() {
        let (s, id) = store()
        s.edit { $0.updateNotes(id) { $0.notes = [Note(pitch: 60, start: 1, length: 0.8)] } }
        s.selectedNotes = Set(notes(s, id).map(\.id))
        s.startTyping()
        XCTAssertTrue(s.stepTyping)
        XCTAssertEqual(s.rollCursor, 2, "right after the selected note, on the grid")
        XCTAssertTrue(s.selectedNotes.isEmpty)
        s.focus = .timeline
        XCTAssertFalse(s.stepTyping, "clicking another panel stops typing")
        _ = s.keyboardKey("a", down: true, isRepeat: false)
        XCTAssertEqual(notes(s, id).count, 1, "outside typing, the keys only play")
    }

    func testTabSelectsNoteByNoteAndShiftArrowsGrowTheSelection() {
        let (s, id) = store()
        // C at beat 0, an E and G chord at 1, and A at 2.
        s.edit { $0.updateNotes(id) { $0.notes = [Note(pitch: 60, start: 0, length: 1), Note(pitch: 64, start: 1, length: 1),
                                               Note(pitch: 67, start: 1, length: 1), Note(pitch: 69, start: 2, length: 1)] } }
        func picked() -> [Int] { notes(s, id).filter { s.selectedNotes.contains($0.id) }.map(\.pitch) }
        s.rollCursor = 0
        s.selectNeighbor(next: true)
        XCTAssertEqual(picked(), [60])
        s.selectNeighbor(next: true)
        XCTAssertEqual(picked(), [64, 67], "a chord is one stop")
        XCTAssertEqual(s.rollCursor, 1)
        s.extendSelection(next: true)
        XCTAssertEqual(picked(), [64, 67, 69])
        s.extendSelection(next: false)
        XCTAssertEqual(picked(), [64, 67])
        s.extendSelection(next: false)
        XCTAssertEqual(picked(), [60, 64, 67], "past where it started, it grows the other way")
        s.selectNeighbor(next: false)
        XCTAssertEqual(picked(), [60, 64, 67], "nothing before the first note keeps the selection")
        s.selectedNotes = []
        s.rollCursor = 4
        s.selectNeighbor(next: false)
        XCTAssertEqual(picked(), [69], "⇧Tab from the cursor picks the note before it")
        s.selectedNotes = []
        s.rollCursor = 0.5
        s.extendSelection(next: true)
        XCTAssertEqual(picked(), [64, 67], "⇧→ from the cursor starts with the next note")
    }

    func testCursorMovesWhenNothingIsSelected() {
        let (s, _) = store()
        s.rollCursor = 1
        s.moveCursor(by: 0.25)
        XCTAssertEqual(s.rollCursor, 1.25)
        s.moveCursor(by: -5)
        XCTAssertEqual(s.rollCursor, 0)
        s.cursorToEdge(end: true)
        XCTAssertEqual(s.rollCursor, 4)
    }

    func testTypingDrumsUsesTheDrumKeys() {
        let (s, id) = store(drums: true)
        s.startTyping()
        tap(s, "a")
        tap(s, "s")
        XCTAssertEqual(notes(s, id).map(\.pitch), [DrumKits.basePitch, DrumKits.basePitch + 1], "A is the kick, S the snare")
        XCTAssertEqual(notes(s, id).map(\.start), [0, 0.25])
    }

    func testOpeningAnotherPatternResetsTheCursor() {
        let (s, _) = store()
        s.startTyping()
        s.rollCursor = 2
        s.open(asset: s.newPattern(preset: "Pluck"))
        XCTAssertNil(s.rollCursor)
        XCTAssertFalse(s.stepTyping)
    }
}
