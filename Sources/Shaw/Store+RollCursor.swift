import Foundation
import ShawCore

/// A box drawn with ⇧ and the arrow keys: across time, from the line where the cursor started to the
/// line it's on now (like selecting text); up and down, every row from the one it started on to this one.
struct RollBox: Equatable {
    var anchorBeat: Double
    var anchorPitch: Int
    var headBeat: Double
    var headPitch: Int
    /// The notes it selected, to tell whether something else has changed the selection since.
    var picked: Set<UUID> = []
}

/// Editing in the piano roll without the mouse. The cursor marks a beat and a row, like a cell in a
/// spreadsheet. With nothing selected, the arrow keys move it, Return adds a note there, and ⇧ with a
/// note key adds that key's note at the cursor's beat. The note keys on their own only play, so you can
/// try ideas without adding anything. ⇧ and the arrow keys draw a box that selects the notes inside it,
/// Tab and ⇧Tab jump from note to note, and with notes selected the arrow keys move them.
extension Store {
    private static let eps = 1e-6

    /// The number keys' note lengths: 1/16, 1/8, 1/4, 1/2, and a bar.
    var stepLengths: [Double] { [0.25, 0.5, 1, 2, Double(project.beatsPerBar)] }

    static let pianoKeyLetters: [Int: String] = Dictionary(uniqueKeysWithValues: pianoKeys.map { ($0.value, $0.key.uppercased()) })

    var openPattern: (id: AssetID, pattern: NotePattern)? {
        guard let id = pianoRollAsset, case .notes(let p)? = project.asset(id)?.content else { return nil }
        return (id, p)
    }

    /// One grid step (the Grid menu, or a sixteenth when it's off).
    var rollStep: Double { rollSnap > 0 ? rollSnap : 0.25 }

    private func snapUp(_ beat: Double) -> Double { ((beat / rollStep) - 1e-6).rounded(.up) * rollStep }

    /// Where the cursor starts if you haven't put it anywhere: right after the last note.
    func defaultCursor(_ p: NotePattern) -> Double {
        p.notes.map(\.end).max().map(snapUp) ?? 0
    }

    /// The row the cursor starts on: the last note's, or the C the A key plays (the kick on drums).
    func defaultCursorPitch(_ p: NotePattern) -> Int {
        if let last = p.notes.max(by: { ($0.start, $0.pitch) < ($1.start, $1.pitch) }) { return last.pitch }
        return p.instrument.isDrumKit ? DrumKits.basePitch : keyboardBasePitch
    }

    /// The cursor's beat and row, filling in the defaults.
    func cursorSpot(_ p: NotePattern) -> (beat: Double, pitch: Int) {
        (rollCursor ?? defaultCursor(p), RowLayout.of(p.instrument).clamp(rollCursorPitch ?? defaultCursorPitch(p)))
    }

    /// How long the notes Return adds are: the last length you used, or one grid step on drums.
    func cursorNoteLength(_ p: NotePattern) -> Double { p.instrument.isDrumKit ? rollStep : lastNoteLength }

    /// The note a key plays in this pattern: up from the C the A key plays, or a drum sound.
    func keyPitch(_ key: String, drums: Bool) -> Int? {
        if drums {
            guard let i = Store.drumKeys.firstIndex(of: key), i < DrumKits.voices.count else { return nil }
            return DrumKits.basePitch + i
        }
        return Store.pianoKeys[key].map { min(127, max(0, keyboardBasePitch + $0)) }
    }

    // MARK: Adding and deleting

    /// Return: add a note at the cursor. The cursor stays where it is.
    func addNoteAtCursor() {
        guard let (_, p) = openPattern else { return }
        let c = cursorSpot(p)
        rollCursor = c.beat
        rollCursorPitch = c.pitch
        place(c.pitch, at: c.beat)
        audition(c.pitch, instrument: p.instrument)
    }

    /// ⇧ and a note key: play that key's note and add it at the cursor's beat, whatever row the cursor is on.
    func addKeyAtCursor(_ key: String) {
        guard keyboardEnabled, let (_, p) = openPattern, let pitch = keyPitch(key, drums: p.instrument.isDrumKit) else { return }
        let beat = rollCursor ?? defaultCursor(p)
        rollCursor = beat
        place(pitch, at: beat)
        _ = keyboardKey(key, down: true, isRepeat: false)
    }

    /// Add a note, replacing one on the same row that starts on the same beat, and grow the pattern to fit it.
    private func place(_ pitch: Int, at beat: Double) {
        guard let (id, p) = openPattern else { return }
        let note = Note(pitch: pitch, start: beat, length: cursorNoteLength(p), velocity: keyboardVelocity)
        edit { proj in
            let bar = Double(proj.beatsPerBar)
            proj.updateNotes(id) { pat in
                pat.notes.removeAll { $0.pitch == pitch && abs($0.start - beat) < Store.eps }
                pat.notes.append(note)
                if note.end > pat.length { pat.length = (note.end / bar - 1e-9).rounded(.up) * bar }
            }
        }
        rollRevealRequest += 1
    }

    /// Delete with nothing selected: delete the note under the cursor.
    func deleteNoteAtCursor() {
        guard let (id, p) = openPattern else { return }
        let c = cursorSpot(p)
        guard let n = p.notes.last(where: { $0.pitch == c.pitch && c.beat > $0.start - Store.eps && c.beat < $0.end - Store.eps }) else { return }
        edit { $0.updateNotes(id) { $0.notes.removeAll { $0.id == n.id } } }
    }

    /// 1–5: the length of the notes Return adds.
    func setStepLength(_ index: Int) {
        guard stepLengths.indices.contains(index) else { return }
        lastNoteLength = stepLengths[index]
    }

    // MARK: Cursor

    /// The arrow keys with nothing selected: move the cursor along the grid, or up and down a row
    /// (and hear the note there).
    func moveCursor(beats: Double = 0, rows: Int = 0) {
        guard let (_, p) = openPattern else { return }
        let c = cursorSpot(p)
        let pitch = RowLayout.of(p.instrument).clamp(c.pitch + rows)
        rollCursor = min(max(0, c.beat + beats), max(p.length, c.beat))
        rollCursorPitch = pitch
        if pitch != c.pitch { audition(pitch, instrument: p.instrument) }
        rollRevealRequest += 1
    }

    /// ⌘← / ⌘→ with nothing selected: the start or end of the pattern.
    func cursorToEdge(end: Bool) {
        guard let (_, p) = openPattern else { return }
        rollCursorPitch = cursorSpot(p).pitch
        rollCursor = end ? p.length : 0
        rollRevealRequest += 1
    }

    /// Esc: deselect, and put the cursor on the first selected note.
    func deselectToCursor() {
        if let (_, p) = openPattern,
           let first = p.notes.filter({ selectedNotes.contains($0.id) }).min(by: { ($0.start, $0.pitch) < ($1.start, $1.pitch) }) {
            rollCursor = first.start
            rollCursorPitch = first.pitch
        }
        selectedNotes = []
        rollBox = nil
        rollRevealRequest += 1
    }

    // MARK: Selected notes

    /// The arrow keys with notes selected: move them, and the cursor with them. They move together,
    /// so the earliest stops at the start and the highest and lowest stop at the edges.
    func moveSelectedNotes(beats: Double = 0, semitones: Int = 0) {
        guard let (id, p) = openPattern else { return }
        let sel = selectedNotes
        let chosen = p.notes.filter { sel.contains($0.id) }
        guard let first = chosen.min(by: { ($0.start, $0.pitch) < ($1.start, $1.pitch) }),
              let lo = chosen.map(\.pitch).min(), let hi = chosen.map(\.pitch).max() else { return }
        let layout = RowLayout.of(p.instrument)
        // Drum rows aren't semitones, so drums move one sound at a time.
        let rows = min(max(layout == .piano ? semitones : semitones.signum(), layout.bottom - lo), layout.top - hi)
        let d = max(beats, -first.start)
        rollBox = nil
        guard abs(d) > Store.eps || rows != 0 else { return }
        edit { $0.updateNotes(id) { pat in
            for i in pat.notes.indices where sel.contains(pat.notes[i].id) {
                pat.notes[i].start += d
                pat.notes[i].pitch += rows
            }
        } }
        rollCursor = first.start + d
        rollCursorPitch = first.pitch + rows
        if rows != 0 { audition(first.pitch + rows, instrument: p.instrument) }
        rollRevealRequest += 1
    }

    // MARK: Selecting

    /// The distinct times notes start, in order. A chord is one stop.
    func noteStops(_ p: NotePattern) -> [Double] {
        var out: [Double] = []
        for s in p.notes.map(\.start).sorted() where out.last.map({ s - $0 > Store.eps }) ?? true { out.append(s) }
        return out
    }

    /// Tab / ⇧Tab: select the next or previous note (or chord), hear it, and put the cursor on it.
    func selectNeighbor(next: Bool) {
        guard let (_, p) = openPattern else { return }
        let stops = noteStops(p)
        let chosen = p.notes.filter { selectedNotes.contains($0.id) }.map(\.start)
        let target: Double?
        if next {
            if let last = chosen.max() { target = stops.first { $0 > last + Store.eps } }
            else { let c = rollCursor ?? 0; target = stops.first { $0 >= c - Store.eps } }
        } else {
            if let first = chosen.min() { target = stops.last { $0 < first - Store.eps } }
            else { let c = rollCursor ?? p.length; target = stops.last { $0 < c - Store.eps } }
        }
        guard let t = target else { return }
        let here = p.notes.filter { abs($0.start - t) < Store.eps }
        selectedNotes = Set(here.map(\.id))
        rollBox = nil
        rollCursor = t
        rollCursorPitch = here.map(\.pitch).min()
        for n in here { audition(n.pitch, instrument: p.instrument) }
        rollRevealRequest += 1
    }

    /// The box, while it still matches the selection and the cursor. Clicking, moving notes, or
    /// moving the cursor ends it.
    var activeBox: RollBox? {
        guard let b = rollBox, b.picked == selectedNotes, rollCursorPitch == b.headPitch,
              let c = rollCursor, abs(c - b.headBeat) < Store.eps else { return nil }
        return b
    }

    /// The beats and rows a box covers. It's always at least one grid step wide: moved only up or
    /// down so far, it covers the step after the cursor's line (a chord there, say).
    func boxBounds(_ b: RollBox) -> (start: Double, end: Double, low: Int, high: Int) {
        let start = min(b.anchorBeat, b.headBeat)
        return (start, max(max(b.anchorBeat, b.headBeat), start + rollStep),
                min(b.anchorPitch, b.headPitch), max(b.anchorPitch, b.headPitch))
    }

    /// ⇧ and the arrow keys: stretch a box from where the cursor was and select every note in it.
    func extendBox(beats: Double = 0, rows: Int = 0) {
        guard let (_, p) = openPattern else { return }
        let c = cursorSpot(p)
        var box = activeBox ?? RollBox(anchorBeat: c.beat, anchorPitch: c.pitch, headBeat: c.beat, headPitch: c.pitch)
        box.headBeat = min(max(0, box.headBeat + beats), max(p.length, box.headBeat))
        box.headPitch = RowLayout.of(p.instrument).clamp(box.headPitch + rows)
        let r = boxBounds(box)
        box.picked = Set(p.notes.filter {
            $0.pitch >= r.low && $0.pitch <= r.high && $0.start < r.end - Store.eps && $0.end > r.start + Store.eps
        }.map(\.id))
        selectedNotes = box.picked
        rollBox = box
        rollCursor = box.headBeat
        rollCursorPitch = box.headPitch
        rollRevealRequest += 1
    }
}
