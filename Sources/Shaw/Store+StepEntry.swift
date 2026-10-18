import Foundation
import QuartzCore
import ShawCore

/// What the piano roll's keyboard controls remember between key presses.
struct RollKeyState {
    /// The note or chord typed last: where it starts, how long it is, when its first key went down, and its notes.
    var start = 0.0
    var length = 0.0
    var time = -Double.infinity
    var notes: [UUID] = []
    /// Note keys held down right now.
    var held: Set<String> = []
    /// ⇧← / ⇧→ selection: the note (or chord) it started from and the one it reaches, by start beat.
    var range: (anchor: Double, head: Double)?
}

/// Writing and editing in the piano roll without the mouse. A cursor marks where notes go.
/// Typing (Return) turns the note keys into note entry: each key places a note at the cursor and
/// moves past it, like typing text. Outside typing, Tab and ⇧Tab select notes and ⇧← / ⇧→ grow
/// the selection, while the arrow keys move the cursor or the selected notes.
extension Store {
    /// Keys pressed this close together (while the first is still held) make a chord.
    static let chordWindow = 0.08
    private static let eps = 1e-6

    /// The number keys' note lengths while typing: 1/16, 1/8, 1/4, 1/2, and a bar.
    var stepLengths: [Double] { [0.25, 0.5, 1, 2, Double(project.beatsPerBar)] }

    var stepLengthName: String {
        let names = ["1/16", "1/8", "1/4", "1/2", "1 bar"]
        if let i = stepLengths.firstIndex(where: { abs($0 - lastNoteLength) < Store.eps }) { return names[i] }
        return String(format: "%g beats", lastNoteLength)
    }

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

    // MARK: Typing

    /// Return: start typing at the cursor, or right after the selected notes.
    func startTyping() {
        guard let (_, p) = openPattern else { return }
        if let end = p.notes.filter({ selectedNotes.contains($0.id) }).map(\.end).max() {
            rollCursor = snapUp(end)
            selectedNotes = []
        } else if rollCursor == nil {
            rollCursor = defaultCursor(p)
        }
        rollKeys = RollKeyState()
        keyboardEnabled = true
        focus = .pianoRoll
        stepTyping = true
        rollRevealRequest += 1
    }

    func stopTyping() {
        stepTyping = false
        rollKeys.held = []
    }

    /// A note key went down while typing: place the note at the cursor and move the cursor past it.
    func typeNote(_ pitch: Int, key: String, now: Double = CACurrentMediaTime()) {
        guard stepTyping, let (id, p) = openPattern else { return }
        let joins = !rollKeys.held.isEmpty && now - rollKeys.time < Store.chordWindow
        if !joins {
            rollKeys.start = rollCursor ?? defaultCursor(p)
            rollKeys.length = lastNoteLength
            rollKeys.time = now
            rollKeys.notes = []
        }
        rollKeys.held.insert(key)
        let note = Note(pitch: pitch, start: rollKeys.start, length: rollKeys.length, velocity: keyboardVelocity)
        edit { proj in
            let bar = Double(proj.beatsPerBar)
            proj.updateNotes(id) { pat in
                pat.notes.removeAll { $0.pitch == pitch && abs($0.start - note.start) < Store.eps }
                pat.notes.append(note)
                if note.end > pat.length { pat.length = (note.end / bar - 1e-9).rounded(.up) * bar }
            }
        }
        rollKeys.notes.append(note.id)
        selectedNotes = []
        rollCursor = rollKeys.start + rollKeys.length
        rollRevealRequest += 1
    }

    /// → while typing: a rest, or, while a note key is held, a longer note.
    func stepForward() {
        guard let (id, p) = openPattern else { return }
        if !rollKeys.held.isEmpty && !rollKeys.notes.isEmpty {
            rollKeys.length += lastNoteLength
            let ids = Set(rollKeys.notes), length = rollKeys.length, end = rollKeys.start + rollKeys.length
            edit { proj in
                let bar = Double(proj.beatsPerBar)
                proj.updateNotes(id) { pat in
                    for i in pat.notes.indices where ids.contains(pat.notes[i].id) { pat.notes[i].length = length }
                    if end > pat.length { pat.length = (end / bar - 1e-9).rounded(.up) * bar }
                }
            }
            rollCursor = end
        } else {
            rollCursor = (rollCursor ?? defaultCursor(p)) + lastNoteLength
        }
        rollRevealRequest += 1
    }

    /// ← while typing: step back one note length.
    func stepBack() {
        guard let (_, p) = openPattern else { return }
        rollCursor = max(0, (rollCursor ?? defaultCursor(p)) - lastNoteLength)
        rollRevealRequest += 1
    }

    /// Delete while typing: erase the note (or chord) just behind the cursor and step back to it,
    /// like Backspace in text. A rest behind the cursor gets stepped back through first.
    func stepBackspace() {
        guard let (id, p) = openPattern else { return }
        let c = rollCursor ?? defaultCursor(p)
        defer { rollRevealRequest += 1 }
        guard let prev = p.notes.filter({ $0.start < c - Store.eps }).map(\.start).max() else {
            rollCursor = max(0, c - lastNoteLength)
            return
        }
        let group = p.notes.filter { abs($0.start - prev) < Store.eps }
        let end = group.map(\.end).max() ?? prev
        if end >= c - Store.eps {
            let ids = Set(group.map(\.id))
            edit { $0.updateNotes(id) { $0.notes.removeAll { ids.contains($0.id) } } }
            rollKeys.notes.removeAll { ids.contains($0) }
            rollCursor = prev
        } else {
            rollCursor = max(end, c - lastNoteLength)
        }
    }

    /// ↑ / ↓ while typing: move the note (or chord) you just typed. Drum hits move to the next sound.
    func stepNudge(_ semitones: Int) {
        guard let (id, p) = openPattern else { return }
        let ids = Set(rollKeys.notes)
        let typed = p.notes.filter { ids.contains($0.id) }
        guard !typed.isEmpty else { return }
        let layout = RowLayout.of(p.instrument)
        let d = layout == .piano ? semitones : (semitones > 0 ? 1 : -1)
        edit { $0.updateNotes(id) { pat in
            for i in pat.notes.indices where ids.contains(pat.notes[i].id) { pat.notes[i].pitch = layout.clamp(pat.notes[i].pitch + d) }
        } }
        for n in typed { audition(layout.clamp(n.pitch + d), instrument: p.instrument) }
    }

    /// 1–5 while typing: the length of the notes you type next.
    func setStepLength(_ index: Int) {
        guard stepLengths.indices.contains(index) else { return }
        lastNoteLength = stepLengths[index]
    }

    // MARK: Cursor

    /// ← / → with nothing selected.
    func moveCursor(by beats: Double) {
        guard let (_, p) = openPattern else { return }
        let c = rollCursor ?? defaultCursor(p)
        rollCursor = min(max(0, c + beats), max(p.length, c))
        rollRevealRequest += 1
    }

    /// ⌘← / ⌘→ with nothing selected: the start or end of the pattern.
    func cursorToEdge(end: Bool) {
        guard let (_, p) = openPattern else { return }
        rollCursor = end ? p.length : 0
        rollRevealRequest += 1
    }

    // MARK: Selecting

    /// The distinct times notes start, in order. A chord is one stop.
    func noteStops(_ p: NotePattern) -> [Double] {
        var out: [Double] = []
        for s in p.notes.map(\.start).sorted() where out.last.map({ s - $0 > Store.eps }) ?? true { out.append(s) }
        return out
    }

    /// Tab / ⇧Tab: select the next or previous note (or chord), hear it, and put the cursor there.
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
        selectStops(from: t, to: t, in: p)
    }

    /// ⇧→ / ⇧←: grow or shrink the selection one note (or chord) at a time. Like a Finder list,
    /// the note you started from stays selected and the far end moves.
    func extendSelection(next: Bool) {
        guard let (_, p) = openPattern else { return }
        let stops = noteStops(p)
        guard !stops.isEmpty else { return }
        func index(_ beat: Double) -> Int? { stops.firstIndex { abs($0 - beat) < Store.eps } }
        let chosen = p.notes.filter { selectedNotes.contains($0.id) }.map(\.start)
        let step = next ? 1 : -1
        var anchor: Int, head: Int
        if let r = rollKeys.range, let a = index(r.anchor), let h = index(r.head),
           selectedNotes == ids(between: stops[a], stops[h], in: p) {
            anchor = a
            head = min(stops.count - 1, max(0, h + step))
        } else if let lo = chosen.min().flatMap(index), let hi = chosen.max().flatMap(index) {
            anchor = next ? lo : hi
            head = min(stops.count - 1, max(0, (next ? hi : lo) + step))
        } else {
            let c = rollCursor ?? 0
            guard let i = next ? stops.firstIndex(where: { $0 >= c - Store.eps }) : stops.lastIndex(where: { $0 < c - Store.eps }) else { return }
            anchor = i
            head = i
        }
        selectStops(from: stops[anchor], to: stops[head], in: p)
    }

    private func ids(between a: Double, _ b: Double, in p: NotePattern) -> Set<UUID> {
        let lo = min(a, b) - Store.eps, hi = max(a, b) + Store.eps
        return Set(p.notes.filter { $0.start >= lo && $0.start <= hi }.map(\.id))
    }

    /// Select every note starting from `a` through `b`, move the cursor to `b`, and play what's there.
    private func selectStops(from a: Double, to b: Double, in p: NotePattern) {
        selectedNotes = ids(between: a, b, in: p)
        rollKeys.range = (a, b)
        rollCursor = b
        for n in p.notes where abs(n.start - b) < Store.eps { audition(n.pitch, instrument: p.instrument) }
        rollRevealRequest += 1
    }
}
