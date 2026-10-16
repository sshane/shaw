import Foundation
import ShawCore

/// Starter content: shows linked compositions, patterns, beats, effects and session clips.
enum DemoProject {
    static func empty() -> Project {
        var p = Project(name: "Untitled", bpm: 124)
        p.updateComposition(p.mainCompositionID) { c in
            c.length = 64
            c.tracks = (1...4).map { Track(name: "Track \($0)", colorIndex: $0 - 1) }
        }
        return p
    }

    static func effect(_ kind: String, _ params: [String: Double] = [:]) -> Effect {
        var e = EffectRegistry.descriptor(kind)!.makeEffect()
        for (k, v) in params { e.params[k] = v }
        return e
    }

    static func chord(_ pitches: [Int], at start: Double, length: Double, vel: Double = 0.7) -> [Note] {
        pitches.map { Note(pitch: $0, start: start, length: length, velocity: vel) }
    }

    static func beat(_ kit: String, steps: Int = 16, _ pattern: [String: [Int]], velocities: [String: [Int: Double]] = [:], swing: Double = 0) -> DrumPattern {
        var d = DrumPattern(kit: kit, steps: steps, swing: swing)
        for i in d.rows.indices {
            let s = d.rows[i].sound
            for step in pattern[s] ?? [] where step < steps { d.rows[i].steps[step] = velocities[s]?[step] ?? 0.85 }
        }
        return d
    }

    static func make() -> Project {
        var p = Project(name: "Demo", bpm: 124)
        let bar = 4.0

        // Patterns
        let chords: [Note] =
            chord([57, 60, 64], at: 0, length: 4) +    // Am
            chord([53, 57, 60], at: 4, length: 4) +    // F
            chord([55, 60, 64], at: 8, length: 4) +    // C
            chord([55, 59, 62], at: 12, length: 4)     // G
        let chordsAsset = Asset(name: "Chords", colorIndex: 4,
                                content: .notes(NotePattern(length: 16, notes: chords, instrument: .preset("Pad"))))

        let roots = [33, 29, 36, 31]
        var bass: [Note] = []
        for (b, r) in roots.enumerated() {
            for i in 0..<4 { bass.append(Note(pitch: r, start: Double(b) * bar + Double(i) + 0.5, length: 0.4, velocity: 0.85)) }
        }
        let bassAsset = Asset(name: "Bassline", colorIndex: 1,
                              content: .notes(NotePattern(length: 16, notes: bass, instrument: .preset("Reese Bass"))))

        let arpShape = [0, 7, 12, 7]
        let arpRoots = [69, 65, 72, 67]
        var arp: [Note] = []
        for (b, r) in arpRoots.enumerated() {
            for i in 0..<16 {
                let pitch = r + arpShape[i % 4] - (i % 8 >= 4 ? 0 : 12)
                arp.append(Note(pitch: pitch, start: Double(b) * bar + Double(i) * 0.25, length: 0.2, velocity: i % 4 == 0 ? 0.9 : 0.6))
            }
        }
        let arpAsset = Asset(name: "Arp", colorIndex: 6,
                             content: .notes(NotePattern(length: 16, notes: arp, instrument: .preset("Pluck"))))

        let house = beat("house", ["kick": [0, 4, 8, 12], "clap": [4, 12], "chat": [2, 6, 10, 14], "ohat": [], "perc": [7, 15]],
                         velocities: ["perc": [7: 0.4, 15: 0.5]])
        let houseAsset = Asset(name: "House Beat", colorIndex: 2, content: .drums(house))

        let hats = beat("house", ["chat": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], "ohat": [2, 6, 10, 14]],
                        velocities: ["chat": [0: 0.4, 1: 0.25, 3: 0.3, 4: 0.4, 5: 0.25, 7: 0.3, 8: 0.4, 9: 0.25, 11: 0.3, 12: 0.4, 13: 0.25, 15: 0.3]],
                        swing: 0.25)
        let hatsAsset = Asset(name: "Shuffle Hats", colorIndex: 8, content: .drums(hats))

        let trap = beat("trap", steps: 32, ["kick": [0, 7, 16, 22], "snare": [8, 24], "chat": Array(stride(from: 0, to: 32, by: 2)) + [27, 29, 31],
                                             "ohat": [14, 30]])
        let trapAsset = Asset(name: "Trap Beat", colorIndex: 5, content: .drums(trap))

        // "Drop" composition: drums + bass + arp, with a pump on the comp itself.
        var drop = Composition(length: 16)
        var dDrums = Track(name: "Drums", colorIndex: 2)
        dDrums.clips = [Clip(assetID: houseAsset.id, start: 0, length: 16, loops: true)]
        var dHats = Track(name: "Hats", colorIndex: 8)
        dHats.clips = [Clip(assetID: hatsAsset.id, start: 0, length: 16, loops: true)]
        var dBass = Track(name: "Bass", colorIndex: 1)
        dBass.clips = [Clip(assetID: bassAsset.id, start: 0, length: 16)]
        dBass.effects = [effect("pump", ["depth": 0.75])]
        var dArp = Track(name: "Arp", colorIndex: 6)
        dArp.clips = [Clip(assetID: arpAsset.id, start: 0, length: 16)]
        dArp.effects = [effect("delay", ["mix": 0.25, "feedback": 0.35]), effect("pump", ["depth": 0.5])]
        dArp.volume = -4
        drop.tracks = [dDrums, dHats, dBass, dArp]
        drop.effects = [effect("compressor", ["threshold": -14, "ratio": 3, "attack": 20])]
        let dropAsset = Asset(name: "Drop", colorIndex: 0, content: .composition(drop))

        // Main: intro chords, the linked Drop twice, chords throughout.
        p.updateComposition(p.mainCompositionID) { c in
            c.length = 64
            var tChords = Track(name: "Chords", colorIndex: 4)
            tChords.clips = [Clip(assetID: chordsAsset.id, start: 0, length: 64, loops: true)]
            tChords.effects = [effect("reverb", ["mix": 0.35, "size": 0.8]), effect("filter", ["cutoff": 3500])]
            tChords.volume = -3
            var tDrop = Track(name: "Drop", colorIndex: 0)
            tDrop.clips = [Clip(assetID: dropAsset.id, start: 16, length: 16), Clip(assetID: dropAsset.id, start: 40, length: 16)]
            var tIntro = Track(name: "Intro Hats", colorIndex: 8)
            tIntro.clips = [Clip(assetID: hatsAsset.id, start: 8, length: 8, loops: true)]
            var tExtra = Track(name: "Trap Ideas", colorIndex: 5)
            tExtra.slots = [0: SessionClip(assetID: trapAsset.id)]
            tChords.slots = [0: SessionClip(assetID: chordsAsset.id), 1: SessionClip(assetID: arpAsset.id)]
            tDrop.slots = [0: SessionClip(assetID: dropAsset.id)]
            tIntro.slots = [1: SessionClip(assetID: houseAsset.id), 0: SessionClip(assetID: hatsAsset.id)]
            c.tracks = [tChords, tIntro, tDrop, tExtra]
        }
        let folder = Folder(name: "Patterns")
        var patterns = [chordsAsset, bassAsset, arpAsset, houseAsset, hatsAsset, trapAsset]
        for i in patterns.indices { patterns[i].folderID = folder.id }
        p.folders = [folder]
        p.assets += [dropAsset] + patterns
        return p
    }
}
