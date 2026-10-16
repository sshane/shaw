import Foundation
import ShawCore

/// Starter content. `make()` is a complete arranged song that shows off linked
/// compositions, patterns, beats, effects at every level and session clips.
enum DemoProject {
    static func empty() -> Project {
        var p = Project(name: "Untitled", bpm: 124)
        // No tracks: adding an instrument creates its track, so there's nothing to figure out first.
        p.updateComposition(p.mainCompositionID) { c in
            c.length = 32
            c.tracks = []
        }
        return p
    }

    // MARK: Helpers

    static func effect(_ kind: String, _ params: [String: Double] = [:]) -> Effect {
        var e = EffectRegistry.descriptor(kind)!.makeEffect()
        for (k, v) in params { e.params[k] = v }
        return e
    }

    static func notes(_ list: [(Int, Double, Double)], vel: Double = 0.8) -> [Note] {
        list.map { Note(pitch: $0.0, start: $0.1, length: $0.2, velocity: vel) }
    }

    static func beat(_ kit: String, steps: Int = 16, _ pattern: [String: [Int]],
                     velocities: [String: [Int: Double]] = [:], swing: Double = 0) -> DrumPattern {
        var d = DrumPattern(kit: kit, steps: steps, swing: swing)
        for i in d.rows.indices {
            let s = d.rows[i].sound
            for step in pattern[s] ?? [] where step < steps { d.rows[i].steps[step] = velocities[s]?[step] ?? 0.85 }
        }
        return d
    }

    static func track(_ name: String, _ color: Int, volume: Double = 0, pan: Double = 0, _ clips: [Clip], effects: [Effect] = []) -> Track {
        var t = Track(name: name, colorIndex: color)
        t.volume = volume
        t.pan = pan
        t.clips = clips
        t.effects = effects
        return t
    }

    /// Loops only when the clip is longer than its source (like an Option-dragged edge).
    static func clip(_ a: Asset, at start: Double, length: Double, loops: Bool? = nil) -> Clip {
        let source: Double
        switch a.content {
        case .composition(let c): source = c.length
        case .notes(let n): source = n.length
        case .drums(let d): source = d.length
        case .audio: source = length
        }
        return Clip(assetID: a.id, start: start, length: length, loops: loops ?? (length > source + 1e-9))
    }

    // MARK: The song

    /// "First Light": A minor house, 124 BPM, 72 bars.
    /// Intro (8) · Build (8) · Drop (16) · Breakdown (8) · Build (8) · Drop + Lead (16) · Outro (8)
    static func make() -> Project {
        var p = Project(name: "First Light", bpm: 124)

        // Am – F – C – G, one bar each.
        let voicings: [[Int]] = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
        let roots = [33, 29, 36, 31]

        // Patterns
        var chordNotes: [Note] = []
        for (bar, v) in voicings.enumerated() {
            chordNotes += v.map { Note(pitch: $0, start: Double(bar * 4), length: 4, velocity: 0.7) }
            chordNotes.append(Note(pitch: v[0] - 12, start: Double(bar * 4), length: 4, velocity: 0.55))
        }
        let chords = Asset(name: "Chords", colorIndex: 4, content: .notes(NotePattern(length: 16, notes: chordNotes, instrument: .preset("Pad"))))

        var bassNotes: [Note] = []
        for (bar, r) in roots.enumerated() {
            for i in 0..<4 {
                bassNotes.append(Note(pitch: r, start: Double(bar * 4 + i) + 0.5, length: 0.42, velocity: 0.9))
            }
            // A little pickup into the next chord.
            bassNotes.append(Note(pitch: r + 12, start: Double(bar * 4) + 3.75, length: 0.2, velocity: 0.6))
        }
        let bass = Asset(name: "Bassline", colorIndex: 1, content: .notes(NotePattern(length: 16, notes: bassNotes, instrument: .preset("Reese Bass"))))

        var arpNotes: [Note] = []
        for (bar, v) in voicings.enumerated() {
            // Chord tones only, so the arp always fits the chord underneath.
            let shape = [v[0], v[1], v[2], v[0] + 12, v[2], v[1], v[0] + 12, v[2] + 12]
            for i in 0..<16 {
                let pitch = shape[i % 8] + 12
                arpNotes.append(Note(pitch: pitch, start: Double(bar * 4) + Double(i) * 0.25, length: 0.18,
                                     velocity: i % 4 == 0 ? 0.9 : 0.55))
            }
        }
        let arp = Asset(name: "Arp", colorIndex: 6, content: .notes(NotePattern(length: 16, notes: arpNotes, instrument: .preset("Pluck"))))

        var stabNotes: [Note] = []
        for (bar, v) in voicings.enumerated() {
            for off in [0.5, 1.5, 2.5, 3.5] where !(bar == 3 && off == 3.5) {
                stabNotes += v.map { Note(pitch: $0 + 12, start: Double(bar * 4) + off, length: 0.22, velocity: off == 0.5 ? 0.85 : 0.7) }
            }
        }
        let stabs = Asset(name: "Stabs", colorIndex: 10, content: .notes(NotePattern(length: 16, notes: stabNotes, instrument: .preset("Keys"))))

        // Lead melody, 8 bars (two passes over the progression).
        let lead = Asset(name: "Lead Melody", colorIndex: 7, content: .notes(NotePattern(length: 32, notes: notes([
            (76, 0, 1.5), (74, 1.5, 0.5), (72, 2, 1), (69, 3, 1),
            (72, 4, 1.5), (74, 5.5, 0.5), (76, 6, 1), (77, 7, 1),
            (79, 8, 1.5), (76, 9.5, 0.5), (72, 10, 2),
            (74, 12, 1), (76, 13, 0.5), (74, 13.5, 0.5), (71, 14, 2),
            (76, 16, 1.5), (74, 17.5, 0.5), (72, 18, 1), (69, 19, 1),
            (72, 20, 1.5), (74, 21.5, 0.5), (76, 22, 1), (81, 23, 1),
            (79, 24, 1), (77, 25, 0.5), (76, 25.5, 0.5), (74, 26, 1), (76, 27, 1),
            (74, 28, 1), (72, 29, 1), (71, 30, 0.5), (69, 30.5, 1.5),
        ], vel: 0.85), instrument: .preset("Lead"))))

        let riser = Asset(name: "Noise Riser", colorIndex: 9, content: .notes(NotePattern(length: 16, notes: [
            Note(pitch: 60, start: 0, length: 16, velocity: 1),
        ], instrument: .preset("Noise Riser"))))

        // Beats
        let houseBeat = Asset(name: "House Beat", colorIndex: 2, content: .drums(beat("house",
            ["kick": [0, 4, 8, 12], "clap": [4, 12], "chat": [2, 6, 10, 14], "ohat": [], "perc": [7, 15], "rim": [3, 11]],
            velocities: ["perc": [7: 0.4, 15: 0.5], "rim": [3: 0.35, 11: 0.3]])))

        let hats = Asset(name: "Shuffle Hats", colorIndex: 8, content: .drums(beat("house",
            ["chat": Array(0..<16), "ohat": [2, 6, 10, 14]],
            velocities: ["chat": [0: 0.4, 1: 0.25, 3: 0.3, 4: 0.4, 5: 0.25, 7: 0.3, 8: 0.4, 9: 0.25, 11: 0.3, 12: 0.4, 13: 0.25, 15: 0.3],
                         "ohat": [2: 0.6, 6: 0.6, 10: 0.6, 14: 0.6]],
            swing: 0.3)))

        // 4-bar snare roll that doubles in speed each bar and gets louder.
        var roll = DrumPattern(kit: "house", steps: 64)
        for i in roll.rows.indices {
            switch roll.rows[i].sound {
            case "snare":
                for s in 0..<64 {
                    let on = s < 16 ? s % 4 == 0 : (s < 32 ? s % 2 == 0 : true)
                    if on { roll.rows[i].steps[s] = 0.3 + 0.7 * Double(s) / 63 }
                }
            case "kick":
                for s in stride(from: 0, to: 48, by: 4) { roll.rows[i].steps[s] = 0.85 }
            case "chat":
                for s in stride(from: 2, to: 64, by: 4) { roll.rows[i].steps[s] = 0.5 }
            default: break
            }
        }
        let snareRoll = Asset(name: "Snare Roll", colorIndex: 5, content: .drums(roll))

        let crash = Asset(name: "Impact", colorIndex: 3, content: .drums(beat("techno", ["crash": [0], "kick": [0]])))

        let trap = Asset(name: "Trap Beat", colorIndex: 5, content: .drums(beat("trap", steps: 32,
            ["kick": [0, 7, 16, 22], "snare": [8, 24], "chat": Array(stride(from: 0, to: 32, by: 2)) + [27, 29, 31], "ohat": [14, 30]])))

        // Compositions (8 bars = 32 beats each)
        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Chords", 4, volume: -2, [clip(chords, at: 0, length: 32)], effects: [effect("chorus", ["mix": 0.3])]),
            track("Hats", 8, volume: -8, [clip(hats, at: 16, length: 16)]),
            track("Arp", 6, volume: -10, [clip(arp, at: 24, length: 8)], effects: [effect("delay", ["mix": 0.3])]),
        ], effects: [
            // Composition effects: the whole intro is filtered, like an adjustment layer on a precomp.
            effect("filter", ["cutoff": 650, "resonance": 0.35, "lfoamount": 0.45, "lforate": 7]),
            effect("reverb", ["mix": 0.25, "size": 0.85]),
        ])))

        let build = Asset(name: "Build", colorIndex: 5, content: .composition(Composition(length: 32, tracks: [
            track("Groove", 2, volume: -3, [clip(houseBeat, at: 0, length: 16)]),
            track("Chords", 4, volume: -6, [clip(chords, at: 0, length: 32)], effects: [effect("filter", ["type": 1, "cutoff": 300])]),
            track("Arp", 6, volume: -9, [clip(arp, at: 0, length: 32)], effects: [effect("delay", ["mix": 0.25])]),
            track("Snare Roll", 5, volume: -10, [clip(snareRoll, at: 16, length: 16, loops: false)], effects: [effect("reverb", ["mix": 0.2])]),
            track("Riser", 9, volume: -6, [clip(riser, at: 16, length: 16, loops: false)], effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ])))

        let drop = Asset(name: "Drop", colorIndex: 0, content: .composition(Composition(length: 32, tracks: [
            track("Drums", 2, [clip(houseBeat, at: 0, length: 32)]),
            track("Hats", 8, volume: -7, pan: 0.1, [clip(hats, at: 0, length: 32)], effects: [effect("autopan", ["amount": 0.3, "rate": 4])]),
            track("Bass", 1, volume: -2, [clip(bass, at: 0, length: 32)],
                  effects: [effect("saturator", ["drive": 4]), effect("pump", ["depth": 0.8])]),
            track("Stabs", 10, volume: -10, [clip(stabs, at: 0, length: 32)],
                  effects: [effect("pump", ["depth": 0.6]), effect("reverb", ["mix": 0.2])]),
            track("Arp", 6, volume: -11, [clip(arp, at: 0, length: 32)],
                  effects: [effect("delay", ["mix": 0.25, "feedback": 0.35]), effect("pump", ["depth": 0.5])]),
        ], effects: [
            effect("compressor", ["threshold": -14, "ratio": 3, "attack": 20, "release": 150]),
        ])))

        let breakdown = Asset(name: "Breakdown", colorIndex: 7, content: .composition(Composition(length: 32, tracks: [
            track("Pad", 4, volume: -3, [clip(chords, at: 0, length: 32)], effects: [effect("phaser", ["mix": 0.3, "rate": 0.15])]),
            track("Lead", 7, volume: -5, [clip(lead, at: 0, length: 32, loops: false)],
                  effects: [effect("delay", ["mix": 0.35, "feedback": 0.45])]),
            track("Arp", 6, volume: -13, [clip(arp, at: 16, length: 16)], effects: [effect("autopan", ["amount": 0.8, "rate": 3])]),
        ], effects: [
            effect("reverb", ["mix": 0.3, "size": 0.92, "predelay": 30]),
        ])))

        // Main arrangement: 72 bars.
        let bar = 4.0
        var main = Composition(length: 72 * bar)
        var tIntro = track("Intro / Outro", 11, [clip(intro, at: 0, length: 32), clip(intro, at: 64 * bar, length: 32)])
        var tBuild = track("Builds", 5, [clip(build, at: 8 * bar, length: 32), clip(build, at: 40 * bar, length: 32)])
        var tDrop = track("Drops", 0, [
            clip(drop, at: 16 * bar, length: 32), clip(drop, at: 24 * bar, length: 32),
            clip(drop, at: 48 * bar, length: 32), clip(drop, at: 56 * bar, length: 32),
        ])
        let tBreak = track("Breakdown", 7, [clip(breakdown, at: 32 * bar, length: 32)])
        var tLead = track("Lead", 7, volume: -6, [clip(lead, at: 48 * bar, length: 64)],
                          effects: [effect("saturator", ["drive": 3, "mix": 0.5]),
                                    effect("delay", ["time": 6, "mix": 0.3, "feedback": 0.4]),
                                    effect("reverb", ["mix": 0.25])])
        var tFX = track("Impacts", 3, volume: -4, [
            clip(crash, at: 16 * bar, length: 4, loops: false), clip(crash, at: 32 * bar, length: 4, loops: false),
            clip(crash, at: 48 * bar, length: 4, loops: false), clip(crash, at: 64 * bar, length: 4, loops: false),
        ], effects: [effect("reverb", ["mix": 0.3, "size": 0.9])])
        // Session slots for jamming: press Tab and launch scenes.
        tIntro.slots = [0: SessionClip(assetID: chords.id), 1: SessionClip(assetID: arp.id)]
        tBuild.slots = [0: SessionClip(assetID: hats.id), 1: SessionClip(assetID: houseBeat.id), 2: SessionClip(assetID: trap.id)]
        tDrop.slots = [1: SessionClip(assetID: drop.id)]
        tLead.slots = [1: SessionClip(assetID: lead.id), 2: SessionClip(assetID: stabs.id)]
        tFX.slots = [1: SessionClip(assetID: bass.id)]
        main.tracks = [tIntro, tBuild, tDrop, tBreak, tLead, tFX]
        // Main composition effects act as the master bus.
        main.effects = [effect("eq", ["lowgain": 1, "highgain": 1.5]), effect("limiter", ["gain": 2, "ceiling": -0.5])]
        p.updateComposition(p.mainCompositionID) { $0 = main }

        let comps = Folder(name: "Sections")
        let pats = Folder(name: "Patterns")
        let beats = Folder(name: "Beats")
        p.folders = [comps, pats, beats]
        func put(_ a: Asset, _ f: Folder) -> Asset { var a = a; a.folderID = f.id; return a }
        p.assets += [intro, build, drop, breakdown].map { put($0, comps) }
        p.assets += [chords, bass, arp, stabs, lead, riser].map { put($0, pats) }
        p.assets += [houseBeat, hats, snareRoll, crash, trap].map { put($0, beats) }
        p.migrateDrumPatterns() // beats are authored as step grids, played as drum-kit patterns
        return p
    }
}
