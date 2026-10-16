import AppKit
import ShawCore

/// Something you can add from the Instruments tab. Synths and drum kits live side by side.
enum InstrumentChoice: Equatable, Identifiable {
    case synth(String)
    case kit(String)

    var id: String {
        switch self {
        case .synth(let p): return "synth:\(p)"
        case .kit(let k): return "kit:\(k)"
        }
    }

    var name: String {
        switch self {
        case .synth(let p): return p
        case .kit(let k): return DrumKits.kitName(k)
        }
    }

    var category: String {
        switch self {
        case .synth(let p): return SynthPresets.categories[p] ?? "Synth"
        case .kit: return "Drums"
        }
    }

    var icon: String {
        switch self {
        case .synth: return "pianokeys"
        case .kit: return "circle.grid.3x3.fill"
        }
    }

    var payload: DragPayload {
        switch self {
        case .synth(let p): return .preset(p)
        case .kit(let k): return .kit(k)
        }
    }

    static var all: [InstrumentChoice] {
        DrumKits.kits.map { .kit($0.id) } + SynthPresets.names.map { .synth($0) }
    }

    /// Display order of categories in the Instruments tab.
    static let categoryOrder = ["Drums", "Bass", "Keys", "Pluck", "Lead", "Pad", "FX", "Synth"]
}

extension Store {
    // MARK: - Empty-project guidance

    /// True once anything has been placed, so the UI can stop guiding and un-gray controls.
    var hasContent: Bool {
        project.assets.contains { a in
            guard case .composition(let c) = a.content else { return false }
            return c.tracks.contains { !$0.clips.isEmpty || !$0.slots.isEmpty }
        }
    }

    // MARK: - Instruments

    /// Short audition when you click an instrument in the browser.
    func previewInstrument(_ choice: InstrumentChoice) {
        switch choice {
        case .synth(let p):
            let inst = Instrument.preset(p)
            let notes = p == "Noise Riser" ? [60] : [48, 55, 60]
            for (i, n) in notes.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                    self.engine.previewNoteOn(n, velocity: 0.8, instrument: inst)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09 + 0.35) { self.engine.previewNoteOff(n) }
            }
        case .kit(let k):
            // Kick, hat, snare, hat — quick, under half a second.
            for (i, sound) in ["kick", "chat", "snare", "chat"].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.11) {
                    self.engine.previewDrum(kit: k, sound: sound, velocity: sound == "chat" ? 0.6 : 0.9)
                }
            }
        }
    }

    /// Add an instrument: a new track with an empty one-bar pattern (or beat), looped and open for editing.
    func addInstrument(_ choice: InstrumentChoice, at start: Double? = nil, track: UUID? = nil) {
        let bar = Double(project.beatsPerBar)
        let id: AssetID
        switch choice {
        case .synth(let p): id = newPattern(preset: p, bars: 1)
        case .kit(let k): id = newBeat(kit: k)
        }
        let at = start ?? (loopEnabled && hasContentIn(activeCompID) ? loopStart : 0)
        let trackID = track ?? addTrack(name: choice.name)
        if let c = addClip(asset: id, at: (at / bar).rounded(.down) * bar, track: trackID) {
            selectedClips = [c]
            open(asset: id, clip: c)
        }
    }

    func hasContentIn(_ comp: AssetID) -> Bool {
        project.composition(comp)?.tracks.contains { !$0.clips.isEmpty } ?? false
    }

    // MARK: - Looping what you edit

    /// The clip in the active composition that best represents `asset` (the one under the loop/playhead).
    func contextClip(for asset: AssetID) -> Clip? {
        guard let comp = activeComp else { return nil }
        let clips = comp.tracks.flatMap(\.clips).filter { $0.assetID == asset }
        let pos = transport.position
        return clips.first { pos >= $0.start && pos < $0.end } ?? clips.first { $0.start >= loopStart - 1e-6 } ?? clips.first
    }

    /// Loop one pass of a clip's content, so edits are heard in context while it repeats.
    func loop(aroundClip id: UUID) {
        guard let c = clip(id) else { return }
        let L = project.sourceLength(of: c.assetID)
        let pass = c.loops ? L : max(0.25, min(c.length, L - c.offset))
        loopStart = c.start
        loopEnd = c.start + min(c.length, pass)
        loopEnabled = true
    }

    func loopWholeComposition() {
        guard let comp = activeComp else { return }
        loopStart = 0
        loopEnd = max(Double(project.beatsPerBar), comp.length)
        loopEnabled = true
    }

    /// Loop the run of back-to-back clips on the edited clip's track (e.g. all your variations).
    func loopVariationRun() {
        guard let id = editingClip, let comp = activeComp, let (ti, _) = comp.locate(clip: id) else { return }
        let clips = comp.tracks[ti].clips.sorted { $0.start < $1.start }
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        var lo = idx, hi = idx
        while lo > 0 && abs(clips[lo - 1].end - clips[lo].start) < 1e-6 { lo -= 1 }
        while hi < clips.count - 1 && abs(clips[hi].end - clips[hi + 1].start) < 1e-6 { hi += 1 }
        loopStart = clips[lo].start
        loopEnd = clips[hi].end
        loopEnabled = true
    }

    // MARK: - Variations

    /// The pattern or beat an editor is working on right now.
    var editedAsset: AssetID? {
        switch focus {
        case .pianoRoll: return pianoRollAsset
        default:
            if let id = editingClip, let c = clip(id) { return c.assetID }
            return lastInstrumentAsset
        }
    }

    /// Keep the current version and continue on a copy placed right after it, looping the copy.
    /// While it loops you can keep tweaking; earlier versions stay put so you can hear them in order.
    func saveVariation() {
        guard let asset = editedAsset, let original = project.asset(asset), original.kind == .notes else { NSSound.beep(); return }
        let source = (editingClip.flatMap { clip($0) }).flatMap { $0.assetID == asset ? $0 : nil } ?? contextClip(for: asset)
        var copy = original
        copy.id = UUID()
        copy.name = project.uniqueName(Store.baseName(original.name))
        let cid = activeCompID
        var newClipID: UUID?
        let bpb = Double(project.beatsPerBar)
        edit { p in
            if let i = p.index(of: asset) { p.assets.insert(copy, at: i + 1) } else { p.assets.append(copy) }
            guard let src = source else { return }
            p.updateComposition(cid) { c in
                guard let (ti, _) = c.locate(clip: src.id) else { return }
                var k = src
                k.id = UUID()
                k.assetID = copy.id
                // First free spot after the original on the same track.
                var start = src.end
                let others = c.tracks[ti].clips.sorted { $0.start < $1.start }
                for o in others where o.id != src.id && o.end > start && o.start < start + k.length { start = o.end }
                k.start = start
                c.tracks[ti].clips.append(k)
                newClipID = k.id
                if k.end > c.length { c.length = (k.end / bpb).rounded(.up) * bpb }
            }
        }
        if let n = newClipID { selectedClips = [n] }
        open(asset: copy.id, clip: newClipID)
    }

    /// "Chords" → "Chords", "Chords 3" → "Chords" (so copies number up neatly).
    static func baseName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count > 1, Int(parts.last!) != nil { return parts.dropLast().joined(separator: " ") }
        return name
    }

    // MARK: - Computer keyboard

    static let pianoKeys: [String: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7, "y": 8, "h": 9, "u": 10, "j": 11,
        "k": 12, "o": 13, "l": 14, "p": 15, ";": 16, "'": 17,
    ]
    static let drumKeys = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"]

    /// The pattern or beat the keyboard plays.
    var keyboardTarget: AssetID? {
        switch focus {
        case .pianoRoll: if let a = pianoRollAsset { return a }
        default: break
        }
        if selectedClips.count == 1, let id = selectedClips.first, let c = clip(id),
           project.asset(c.assetID)?.kind == .notes { return c.assetID }
        return lastInstrumentAsset.flatMap { project.asset($0) != nil ? $0 : nil }
    }

    /// Returns true if the key was handled (played, octave, velocity).
    func keyboardKey(_ chars: String, down: Bool, isRepeat: Bool) -> Bool {
        guard keyboardEnabled else { return false }
        let k = chars.lowercased()
        if down {
            switch k {
            case "z": releaseKeyboard(); keyboardOctave = max(-1, keyboardOctave - 1); return true
            case "x": releaseKeyboard(); keyboardOctave = min(8, keyboardOctave + 1); return true
            case "c": keyboardVelocity = max(0.1, keyboardVelocity - 0.15); return true
            case "v": keyboardVelocity = min(1, keyboardVelocity + 0.15); return true
            default: break
            }
        }
        guard let target = keyboardTarget, let asset = project.asset(target) else {
            return Store.pianoKeys[k] != nil
        }
        if !down {
            guard let held = heldKeys.removeValue(forKey: k) else { return Store.pianoKeys[k] != nil }
            if !held.isDrum { engine.previewNoteOff(held.pitch) }
            if !heldKeys.values.contains(where: { $0.pitch == held.pitch }) { playingPitches.remove(held.pitch) }
            return true
        }
        if isRepeat { return Store.pianoKeys[k] != nil }
        switch asset.content {
        case .notes(let p) where p.instrument.isDrumKit:
            // Drum kits: the home row plays the sounds in order (A = kick, S = snare, …).
            guard let i = Store.drumKeys.firstIndex(of: k) else { return Store.pianoKeys[k] != nil }
            guard i < DrumKits.voices.count else { return true }
            heldKeys[k] = (DrumKits.basePitch + i, true)
            playingPitches.insert(DrumKits.basePitch + i)
            engine.previewNoteOn(DrumKits.basePitch + i, velocity: keyboardVelocity, instrument: p.instrument)
            return true
        case .notes(let p):
            guard let off = Store.pianoKeys[k] else { return false }
            let pitch = min(127, max(0, (keyboardOctave + 1) * 12 + off))
            if let old = heldKeys[k], !old.isDrum { engine.previewNoteOff(old.pitch); playingPitches.remove(old.pitch) }
            heldKeys[k] = (pitch, false)
            playingPitches.insert(pitch)
            engine.previewNoteOn(pitch, velocity: keyboardVelocity, instrument: p.instrument)
            return true
        default:
            return false
        }
    }

    /// Let go of everything held (e.g. when changing octave mid-chord).
    func releaseKeyboard() {
        for (_, h) in heldKeys where !h.isDrum { engine.previewNoteOff(h.pitch) }
        heldKeys.removeAll()
        playingPitches.removeAll()
    }

    /// Lowest pitch the A key plays.
    var keyboardBasePitch: Int { (keyboardOctave + 1) * 12 }

    /// Label for the keyboard indicator, e.g. "Pluck · C3".
    var keyboardLabel: String {
        guard let t = keyboardTarget, let a = project.asset(t) else { return "No instrument" }
        if case .notes(let p) = a.content, p.instrument.isDrumKit { return "\(a.name) · drums (A S D F…)" }
        return "\(a.name) · C\(keyboardOctave)"
    }

    // MARK: - Auditioning while editing

    /// Editors call this when you click/add/move notes. Silent while the song plays, and off unless enabled.
    func audition(_ pitch: Int, instrument: Instrument) {
        guard auditionNotes, !transport.playing else { return }
        engine.previewNoteOn(pitch, velocity: 0.75, instrument: instrument)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.engine.previewNoteOff(pitch) }
    }

}

extension Store {
    // MARK: - Swapping instruments

    /// Replace the instrument of one pattern or beat, keeping its notes.
    @discardableResult
    func replaceInstrument(ofAsset id: AssetID, with choice: InstrumentChoice) -> Bool {
        // Any pattern can take any instrument: drums and synths are both piano-roll patterns.
        guard project.asset(id)?.kind == .notes else { NSSound.beep(); return false }
        switch choice {
        case .synth(let preset): edit { $0.updateNotes(id) { $0.instrument = .preset(preset) } }
        case .kit(let kit): edit { $0.updateNotes(id) { $0.instrument = .kit(kit) } }
        }
        return true
    }
}
