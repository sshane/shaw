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

    var isKit: Bool { if case .kit = self { return true } else { return false } }

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
    static let categoryOrder = ["Drums", "Bass", "Keys", "Pluck", "Lead", "Pad", "Strings & Brass", "Future Bass", "Dubstep & Bass House", "Hyperpop", "Chiptune", "FX", "Synth"]
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

    /// Short audition when you click an instrument in the browser: a little beat or phrase that
    /// shows off what the sound is for, through the preset's own effects.
    func previewInstrument(_ choice: InstrumentChoice) {
        switch choice {
        case .synth(let p):
            let (notes, bpm) = Store.phrase(forPreset: p)
            engine.playPhrase(notes, instrument: .preset(p), effects: SynthPresets.effects(for: p), bpm: bpm)
        case .kit(let k):
            let (notes, bpm) = Store.beat(forKit: k)
            engine.playPhrase(notes, instrument: .kit(k), bpm: bpm)
        }
    }

    /// One bar in the style the kit is made for. Beats are quarter notes; pitches are kit sounds.
    static func beat(forKit kit: String) -> ([PhraseNote], Double) {
        func d(_ sound: String) -> Int { DrumKits.pitch(of: sound) }
        var n: [PhraseNote] = []
        func hit(_ sound: String, _ sixteenths: [Double], _ vel: Double = 0.85) {
            for s in sixteenths { n.append(PhraseNote(s / 4, 0.25, d(sound), vel)) }
        }
        switch kit {
        case "house", "techno":
            // Four on the floor, clap on 2 and 4, open hats on the offbeats.
            hit("kick", [0, 4, 8, 12], 0.95)
            hit(kit == "house" ? "clap" : "snare", [4, 12])
            hit("ohat", [2, 6, 10, 14], 0.6)
            hit("chat", [1, 3, 5, 7, 9, 11, 13, 15], 0.4)
            if kit == "techno" { hit("perc", [7, 15], 0.5); hit("rim", [11], 0.6) }
            return (n, kit == "house" ? 124 : 132)
        case "boombap", "lofi":
            // Laid-back hip-hop: kick, snare on 2 and 4, swung eighth hats.
            hit("kick", [0, 7, 10], 0.9)
            hit("snare", [4, 12], 0.9)
            for (i, s) in [0.0, 2.33, 4, 6.33, 8, 10.33, 12, 14.33].enumerated() {
                n.append(PhraseNote(s / 4, 0.25, d("chat"), i % 2 == 0 ? 0.6 : 0.4))
            }
            return (n, kit == "lofi" ? 82 : 90)
        case "electro":
            hit("kick", [0, 6, 10], 0.95)
            hit("snare", [4, 12], 0.9)
            hit("chat", [0, 2, 4, 6, 8, 10, 12, 14], 0.5)
            hit("chat", [1, 3, 5, 7, 9, 11, 13, 15], 0.3)
            hit("tomlo", [14.5], 0.6)
            return (n, 118)
        default:
            // Trap and drill: half-time snare on 3, rolling hats with a fast roll at the end.
            let drill = kit == "drill"
            hit("kick", drill ? [0, 6, 11] : [0, 7, 10], 0.95)
            hit("snare", drill ? [4, 13] : [8], 0.9)
            hit("chat", drill ? [0, 3, 6, 8, 11, 14] : [0, 2, 4, 6, 8, 10], 0.5)
            for i in 0..<6 { n.append(PhraseNote((12 + Double(i) * 0.667) / 4, 0.1, d("chat"), 0.35 + Double(i) * 0.06)) }
            hit("ohat", [drill ? 9 : 14], 0.5)
            return (n, drill ? 142 : 140)
        }
    }

    /// A short musical phrase suited to the preset: riffs for basses, chords for pads,
    /// arpeggios for plucks, melodies for leads. Mostly in A minor, beats are quarter notes.
    static func phrase(forPreset name: String) -> ([PhraseNote], Double) {
        let cat = SynthPresets.categories[name] ?? "Synth"
        let p = SynthPresets.params(for: name)
        func chord(_ at: Double, _ len: Double, _ pitches: [Int], _ vel: Double = 0.8) -> [PhraseNote] {
            pitches.map { PhraseNote(at, len, $0, vel) }
        }
        let am = [57, 60, 64, 67], f = [53, 57, 60, 64], c = [55, 60, 64, 67], g = [55, 59, 62, 67]
        let wobbles = (p["lfocut"] ?? 0) > 0 || (p["lfofm"] ?? 0) > 0 || (p["lfoamp"] ?? 0) > 0.3
        let mono = (p["mode"] ?? 0) > 0

        switch name {
        case "Noise Riser": return ([PhraseNote(0, 6, 60)], 120)
        case "Downlifter": return ([PhraseNote(0, 3, 60)], 120)
        case "Impact Boom": return ([PhraseNote(0, 2, 36, 0.9)], 120)
        case "Laser Zap": return ([PhraseNote(0, 0.25, 72), PhraseNote(0.5, 0.25, 76), PhraseNote(1, 0.25, 79), PhraseNote(1.75, 0.5, 84)], 120)
        case "808 Bass", "Distorted 808", "Bubble Bass":
            // 808 pattern with an overlapping slide up and back.
            return ([PhraseNote(0, 1.5, 33, 0.9), PhraseNote(1.75, 0.5, 33), PhraseNote(2.5, 1.0, 40), PhraseNote(3.25, 0.75, 45, 0.85)], 140)
        default: break
        }

        let bass = cat == "Bass" || name.contains("Bass") || name.contains("Reese")
        if bass && wobbles {
            // Long notes so you hear the wobble move, with a quick pickup.
            return ([PhraseNote(0, 1.5, 33, 0.9), PhraseNote(1.5, 0.5, 36), PhraseNote(2, 1.75, 31, 0.9)], 140)
        }
        if bass {
            // Octave-bouncing riff.
            let riff: [(Double, Double, Int)] = [(0, 0.5, 33), (0.75, 0.25, 33), (1, 0.5, 45), (1.5, 0.5, 33),
                                                (2, 0.5, 41), (2.5, 0.25, 41), (3, 0.5, 43), (3.5, 0.5, 45)]
            return (riff.map { PhraseNote($0.0, $0.1, $0.2, 0.85) }, 124)
        }
        switch cat {
        case "Pad", "Strings & Brass" where name != "Pizzicato" && name != "Brass":
            return (chord(0, 2, am, 0.7) + chord(2, 2, f, 0.7), 90)
        case "Future Bass" where ["Future Chords", "Wub Chords", "Heaven Pad"].contains(name):
            if name == "Heaven Pad" { return (chord(0, 2, am, 0.7) + chord(2, 2, f, 0.7), 90) }
            // Future bass chord stabs: Am then F, with the classic 3-3-2 rhythm.
            var n: [PhraseNote] = []
            for (at, len) in [(0.0, 0.7), (0.75, 0.7), (1.5, 0.45)] { n += chord(at, len, am + [72]) }
            for (at, len) in [(2.0, 0.7), (2.75, 0.7), (3.5, 0.45)] { n += chord(at, len, f + [69]) }
            return (n, 150)
        case "Keys":
            return (chord(0, 1.5, am, 0.75) + chord(1.5, 0.5, g, 0.7) + chord(2, 2, f + [69], 0.75), 100)
        default: break
        }
        if ["Supersaw", "Stab", "Hyper Saw", "Hoover"].contains(name) {
            var n: [PhraseNote] = []
            let shift = name == "Hoover" ? -12 : 0
            for (at, len, ch) in [(0.0, 0.4, am), (0.75, 0.4, am), (1.5, 0.4, c), (2.25, 0.4, g), (3.0, 0.9, f)] {
                n += chord(at, len, ch.map { $0 + shift })
            }
            return (n, 128)
        }
        let plucky = cat == "Pluck" || ["Bell", "Music Box", "Pizzicato", "Dream Pluck", "Glitter Pluck", "Digi Bell", "Chip Arp",
                                        "Electric Piano", "Init"].contains(name)
        if plucky {
            // Rising and falling arpeggio over Am then F.
            let up = [57, 60, 64, 69, 72, 69, 64, 60, 53, 57, 60, 65, 69, 65, 60, 57]
            let lift = ["Glitter Pluck", "Music Box", "Digi Bell", "Bell"].contains(name) ? 12 : 0
            return (up.enumerated().map { PhraseNote(Double($0.offset) * 0.25, 0.22, $0.element + lift, $0.offset % 4 == 0 ? 0.9 : 0.7) }, 128)
        }
        // Leads: a short hook that steps and leaps, with overlaps so mono presets glide.
        let hook: [(Double, Double, Int)] = [(0, 0.5, 69), (0.5, 0.5, 72), (1, 0.75, 76), (1.75, 0.25, 74),
                                             (2, 0.5, 72), (2.5, 0.5, 71), (3, 1, 69)]
        let down = ["Screech Lead", "Brass", "Vowel Lead"].contains(name) ? -12 : 0
        return (hook.map { PhraseNote($0.0, $0.1 + (mono ? 0.05 : 0), $0.2 + down, 0.85) }, 128)
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
        if track == nil, case .synth(let p) = choice {
            let fx = SynthPresets.effects(for: p)
            if !fx.isEmpty { updateTrack(trackID) { $0.effects = fx } }
        }
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
            previewNoteOn(DrumKits.basePitch + i, velocity: keyboardVelocity, instrument: p.instrument, asset: asset.id)
            return true
        case .notes(let p):
            guard let off = Store.pianoKeys[k] else { return false }
            let pitch = min(127, max(0, (keyboardOctave + 1) * 12 + off))
            if let old = heldKeys[k], !old.isDrum { engine.previewNoteOff(old.pitch); playingPitches.remove(old.pitch) }
            heldKeys[k] = (pitch, false)
            playingPitches.insert(pitch)
            previewNoteOn(pitch, velocity: keyboardVelocity, instrument: p.instrument, asset: asset.id)
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

    /// Play a preview note through the effects of the layer (and clip) the pattern lives on,
    /// so it sounds like it will in the song.
    func previewNoteOn(_ pitch: Int, velocity: Double = 0.8, instrument: Instrument, asset: AssetID?) {
        engine.setPreviewEffects(asset.map(layerEffects(for:)) ?? [])
        engine.previewNoteOn(pitch, velocity: velocity, instrument: instrument)
    }

    /// Clip effects then layer effects of the clip that best represents `asset` (clip effects run first).
    func layerEffects(for asset: AssetID) -> [Effect] {
        guard let c = contextClip(for: asset), let comp = activeComp,
              let t = comp.tracks.first(where: { $0.clips.contains { $0.id == c.id } }) else { return [] }
        return c.effects + t.effects
    }

    /// Editors call this when you click/add/move notes. Silent while the song plays, and off unless enabled.
    func audition(_ pitch: Int, instrument: Instrument) {
        guard auditionNotes, !transport.playing else { return }
        previewNoteOn(pitch, velocity: 0.75, instrument: instrument, asset: pianoRollAsset)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.engine.previewNoteOff(pitch) }
    }

}

extension Store {
    // MARK: - Swapping instruments

    /// Replace the instrument of one pattern or beat, keeping its notes.
    @discardableResult
    func replaceInstrument(ofAsset id: AssetID, with choice: InstrumentChoice) -> Bool {
        // Any pattern can take any instrument: drums and synths are both piano-roll patterns.
        guard let asset = project.asset(id), case .notes(let pat) = asset.content else { NSSound.beep(); return false }
        // Names that still follow the instrument ("Pluck", "Pluck 2", "Trap 808 Beat") follow the new one;
        // names you typed yourself are left alone.
        let oldSound = pat.instrument.kit.map { DrumKits.kitName($0) } ?? pat.instrument.preset.replacingOccurrences(of: "*", with: "")
        let oldAssetBase = pat.instrument.isDrumKit ? "\(oldSound) Beat" : oldSound
        let newAssetBase = choice.isKit ? "\(choice.name) Beat" : choice.name
        let renameAsset = Store.baseName(asset.name) == oldAssetBase
        let newAssetName = renameAsset ? project.uniqueName(newAssetBase, excluding: id) : asset.name
        let cid = activeCompID
        edit { p in
            switch choice {
            case .synth(let preset): p.updateNotes(id) { $0.instrument = .preset(preset) }
            case .kit(let kit): p.updateNotes(id) { $0.instrument = .kit(kit) }
            }
            p.updateAsset(id) { $0.name = newAssetName }
            // Layers named after the old sound follow too.
            p.updateComposition(cid) { c in
                for ti in c.tracks.indices where c.tracks[ti].clips.contains(where: { $0.assetID == id })
                    && (c.tracks[ti].name == oldSound || c.tracks[ti].name == oldAssetBase) {
                    c.tracks[ti].name = choice.name
                }
            }
        }
        return true
    }
}
