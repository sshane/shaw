import XCTest
@testable import ShawCore
@testable import Shaw

/// Editing the piano roll with the keyboard alone (Store+RollCursor.swift).
final class RollCursorTests: XCTestCase {
    func store(drums: Bool = false) -> (Store, AssetID) {
        let s = Store(project: DemoProject.empty(), headless: true)
        let id = drums ? s.newBeat(kit: "house") : s.newPattern(preset: "Keys", bars: 1)
        s.open(asset: id)
        s.focus = .pianoRoll
        return (s, id)
    }

    func notes(_ s: Store, _ id: AssetID) -> [Note] {
        guard case .notes(let p)? = s.project.asset(id)?.content else { return [] }
        return p.notes.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    func set(_ s: Store, _ id: AssetID, _ ns: [Note]) {
        s.edit { $0.updateNotes(id) { $0.notes = ns } }
    }

    func picked(_ s: Store, _ id: AssetID) -> [Int] {
        notes(s, id).filter { s.selectedNotes.contains($0.id) }.map(\.pitch)
    }

    func cursor(_ s: Store) -> [Double] { [s.rollCursor ?? -1, Double(s.rollCursorPitch ?? -1)] }

    func testArrowsMoveTheCursorAndReturnAddsANoteThere() {
        let (s, id) = store()
        s.moveCursor(beats: 0.25)
        XCTAssertEqual(cursor(s), [0.25, 48], "it starts on the C the A key plays")
        s.moveCursor(rows: 2)
        s.addNoteAtCursor()
        XCTAssertEqual(notes(s, id).map(\.pitch), [50])
        XCTAssertEqual(notes(s, id).map(\.start), [0.25])
        XCTAssertEqual(cursor(s), [0.25, 50], "the cursor stays put")
        XCTAssertTrue(s.selectedNotes.isEmpty, "so the arrows keep moving the cursor")
        s.undo()
        XCTAssertTrue(notes(s, id).isEmpty)
    }

    func testTheNoteKeysOnlyPlayButShiftAddsThemAtTheCursor() {
        let (s, id) = store()
        s.rollCursor = 1
        s.rollCursorPitch = 70
        XCTAssertTrue(s.keyboardKey("a", down: true, isRepeat: false))
        _ = s.keyboardKey("a", down: false, isRepeat: false)
        XCTAssertTrue(notes(s, id).isEmpty, "playing a key adds nothing")
        s.addKeyAtCursor("a")
        s.addKeyAtCursor("d")
        XCTAssertEqual(notes(s, id).map(\.pitch), [48, 52], "the key's note, whatever row the cursor is on")
        XCTAssertEqual(notes(s, id).map(\.start), [1, 1])
        XCTAssertEqual(cursor(s), [1, 70])
        _ = s.keyboardKey("a", down: false, isRepeat: false)
        _ = s.keyboardKey("d", down: false, isRepeat: false)
        XCTAssertTrue(s.playingPitches.isEmpty, "letting go stops them")
    }

    func testDeleteRemovesTheNoteUnderTheCursor() {
        let (s, id) = store()
        set(s, id, [Note(pitch: 60, start: 0, length: 1), Note(pitch: 64, start: 0, length: 1)])
        s.rollCursor = 0.5
        s.rollCursorPitch = 64
        s.deleteNoteAtCursor()
        XCTAssertEqual(notes(s, id).map(\.pitch), [60])
        s.rollCursorPitch = 62
        s.deleteNoteAtCursor()
        XCTAssertEqual(notes(s, id).count, 1, "an empty cell deletes nothing")
    }

    func testAddingAtTheEndGrowsThePattern() {
        let (s, id) = store() // one bar of 4 beats
        s.cursorToEdge(end: true)
        s.setStepLength(2) // quarter notes
        s.addNoteAtCursor()
        guard case .notes(let p)? = s.project.asset(id)?.content else { return XCTFail("no pattern") }
        XCTAssertEqual(p.length, 8, "grew by a bar so the note isn't cut off")
        XCTAssertEqual(notes(s, id).map(\.length), [1])
    }

    func testShiftArrowsDrawABox() {
        let (s, id) = store()
        s.rollSnap = 1
        // C4, E4, G4, and C5, one beat each.
        set(s, id, [Note(pitch: 60, start: 0, length: 1), Note(pitch: 64, start: 1, length: 1),
                    Note(pitch: 67, start: 2, length: 1), Note(pitch: 72, start: 3, length: 1)])
        s.rollCursor = 3
        s.rollCursorPitch = 60 // the bottom right, on the line where the C5 starts
        s.extendBox(rows: 7)
        XCTAssertEqual(picked(s, id), [], "a box with no width takes the notes crossing the line: none below C5 here")
        s.extendBox(beats: -1)
        XCTAssertEqual(picked(s, id), [67], "back to beat 2: just the G, nothing past where it started")
        s.extendBox(beats: -1)
        XCTAssertEqual(picked(s, id), [64, 67])
        s.extendBox(rows: -7)
        XCTAssertEqual(picked(s, id), [], "back down to the row it started on")
        s.extendBox(rows: 12)
        XCTAssertEqual(picked(s, id), [64, 67], "the C5 starts on the line where the box started, so it stays out")
        XCTAssertEqual(cursor(s), [1, 72], "the cursor is the corner that moves")
        XCTAssertNotNil(s.activeBox)
        // With notes selected, the arrows move them, and that ends the box.
        s.moveSelectedNotes(semitones: 1)
        XCTAssertEqual(notes(s, id).map(\.pitch), [60, 65, 68, 72])
        XCTAssertNil(s.activeBox)
        s.extendBox(rows: 3)
        XCTAssertEqual(picked(s, id), [65], "a new box starts from the first moved note; with no width it takes what crosses its line")
        s.extendBox(beats: 2)
        XCTAssertEqual(picked(s, id), [65, 68])
    }

    func testEscPutsTheCursorOnTheFirstSelectedNote() {
        let (s, id) = store()
        set(s, id, [Note(pitch: 67, start: 2, length: 1), Note(pitch: 64, start: 1, length: 1), Note(pitch: 60, start: 1, length: 1)])
        s.selectedNotes = Set(notes(s, id).map(\.id))
        s.rollCursor = 3
        s.deselectToCursor()
        XCTAssertTrue(s.selectedNotes.isEmpty)
        XCTAssertEqual(cursor(s), [1, 60])
    }

    func testSelectedNotesMoveTogether() {
        let (s, id) = store()
        set(s, id, [Note(pitch: 60, start: 0, length: 1), Note(pitch: 126, start: 1, length: 1)])
        s.selectedNotes = Set(notes(s, id).map(\.id))
        s.moveSelectedNotes(beats: -1)
        XCTAssertEqual(notes(s, id).map(\.start), [0, 1], "the first note stops at the start, and the other keeps its place")
        s.moveSelectedNotes(semitones: 12)
        XCTAssertEqual(notes(s, id).map(\.pitch), [61, 127], "they keep their shape at the top")
        s.moveSelectedNotes(beats: 0.25)
        XCTAssertEqual(cursor(s), [0.25, 61], "the cursor rides on the first note")
    }

    func testTabSelectsNoteByNote() {
        let (s, id) = store()
        // C at beat 0, an E and G chord at 1, and A at 2.
        set(s, id, [Note(pitch: 60, start: 0, length: 1), Note(pitch: 64, start: 1, length: 1),
                    Note(pitch: 67, start: 1, length: 1), Note(pitch: 69, start: 2, length: 1)])
        s.rollCursor = 0
        s.selectNeighbor(next: true)
        XCTAssertEqual(picked(s, id), [60])
        s.selectNeighbor(next: true)
        XCTAssertEqual(picked(s, id), [64, 67], "a chord is one stop")
        XCTAssertEqual(cursor(s), [1, 64])
        s.selectNeighbor(next: false)
        s.selectNeighbor(next: false)
        XCTAssertEqual(picked(s, id), [60], "nothing before the first note keeps the selection")
        s.selectedNotes = []
        s.rollCursor = 4
        s.selectNeighbor(next: false)
        XCTAssertEqual(picked(s, id), [69], "⇧Tab from the cursor picks the note before it")
    }

    func testTheCursorStaysInsideThePattern() {
        let (s, _) = store()
        s.rollCursor = 1
        s.moveCursor(beats: 0.25)
        XCTAssertEqual(s.rollCursor, 1.25)
        s.moveCursor(beats: -5)
        XCTAssertEqual(s.rollCursor, 0)
        s.moveCursor(beats: 10)
        XCTAssertEqual(s.rollCursor, 4)
        s.rollCursorPitch = 125
        s.moveCursor(rows: 12)
        XCTAssertEqual(s.rollCursorPitch, 127)
    }

    func testDrumsUseTheDrumKeysAndRows() {
        let (s, id) = store(drums: true)
        s.addNoteAtCursor()
        XCTAssertEqual(notes(s, id).map(\.pitch), [DrumKits.basePitch], "the cursor starts on the kick")
        s.moveCursor(beats: 0.25)
        s.addKeyAtCursor("s")
        XCTAssertEqual(notes(s, id).map(\.pitch), [DrumKits.basePitch, DrumKits.basePitch + 1], "S is the snare")
        XCTAssertEqual(notes(s, id).map(\.length), [0.25, 0.25], "drum hits are one grid step")
        s.selectedNotes = Set(notes(s, id).suffix(1).map(\.id))
        s.moveSelectedNotes(semitones: 12)
        XCTAssertEqual(notes(s, id).last?.pitch, DrumKits.basePitch + 2, "drums move one sound at a time")
    }

    func testOpeningAnotherPatternResetsTheCursor() {
        let (s, _) = store()
        s.rollCursor = 2
        s.rollCursorPitch = 60
        s.open(asset: s.newPattern(preset: "Pluck"))
        XCTAssertNil(s.rollCursor)
        XCTAssertNil(s.rollCursorPitch)
    }
}
