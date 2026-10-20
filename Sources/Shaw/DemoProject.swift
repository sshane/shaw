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
            // A light master chain, like a finished song: glue the mix together, then bring it up to volume.
            c.effects = [effect("compressor", ["threshold": -14, "ratio": 2, "attack": 30, "release": 150, "makeup": 1]),
                         effect("limiter", ["gain": 3, "ceiling": -0.5])]
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

    // MARK: Demo songs

    /// The default demo.
    static func make() -> Project { sunroom() }

    static func keyframed(_ kind: String, _ params: [String: Double] = [:], _ param: String, _ points: [(Double, Double)]) -> Effect {
        var e = effect(kind, params)
        e.keyframes[param] = points.map { Keyframe(time: $0.0, value: $0.1) }
        return e
    }

    // MARK: - Starlight FM

    /// "Starlight FM": C minor UK garage and future house, 134 BPM, 40 bars (about 72 seconds).
    /// Skippy 2-step drums, a bouncy bass, pumping garage chord stabs, vocal-chop leads,
    /// and a four-on-the-floor second drop with a bright topline.
    /// Intro (8) · Drop (16) · Break (4) · Drop 2 (8) · Outro (4)
    static func starlightFM() -> Project {
        var p = Project(name: "Starlight FM", bpm: 134)
        let bar = 4.0

        // Cm9 – Abmaj9 – Fm9 – G7, one bar each. The top voices barely move, which is the garage sound.
        // Cm9 – Abmaj9 – Fm7 – G7, voiced so no two notes sit a half step apart (that rub muddies a pad).
        let voicings: [[Int]] = [[51, 55, 58, 62], [51, 55, 58, 60], [51, 56, 60, 63], [50, 53, 55, 59]]
        let roots = [36, 32, 29, 31]

        /// `gain` turns the preset's own volume up or down (dB), so the parts sit together.
        func pattern(_ name: String, _ color: Int, _ preset: String, length: Double = 16, gain: Double = 0, _ notes: [Note]) -> Asset {
            var inst = Instrument.preset(preset)
            inst.params["volume"] = (inst.params["volume"] ?? -8) + gain
            return Asset(name: name, colorIndex: color, content: .notes(NotePattern(length: length, notes: notes, instrument: inst)))
        }

        // Airy pad under everything.
        var padNotes: [Note] = []
        for (b, v) in voicings.enumerated() {
            padNotes += v.map { Note(pitch: $0 + 12, start: Double(b) * bar, length: 4, velocity: 0.6) }
        }
        let pad = pattern("Air Pad", 10, "Heaven Pad", padNotes)

        // Garage organ-style stabs: hits on 1, the "e" of 1, the "and" of 2, the "and" of 3, and 4.
        var stabNotes: [Note] = []
        for (b, v) in voicings.enumerated() {
            for t in [0.0, 0.75, 1.5, 2.5, 3.0] {
                stabNotes += v.map { Note(pitch: $0 + 12, start: Double(b) * bar + t, length: 0.22, velocity: t == 0 ? 0.85 : 0.7) }
            }
        }
        let stabs = pattern("Garage Stabs", 4, "Future Chords", gain: 6, stabNotes)

        // Bouncy bass: root, octave pops, and a fifth that pulls to the next chord.
        var bassNotes: [Note] = []
        for (b, r) in roots.enumerated() {
            for (t, len, off) in [(0.0, 0.5, 0), (0.75, 0.25, 12), (1.5, 0.5, 0), (2.5, 0.4, 7), (3.25, 0.25, 0), (3.5, 0.4, 12)] {
                bassNotes.append(Note(pitch: r + off, start: Double(b) * bar + t, length: len, velocity: off == 0 ? 0.9 : 0.75))
            }
        }
        let bass = pattern("Bassline", 1, "Bass House", bassNotes)

        // The hook: short, syncopated, and only notes that sit well over each chord (no half-step rubs with the pad).
        let chops = pattern("Hook", 7, "Dream Pluck", gain: 4, notes([
            (72, 0, 0.25), (72, 0.5, 0.25), (77, 0.75, 0.5), (74, 1.5, 0.25), (72, 2, 0.5), (70, 2.75, 0.25), (67, 3, 0.75),
            (72, 4, 0.25), (75, 4.5, 0.25), (77, 4.75, 0.5), (75, 5.5, 0.25), (72, 6, 0.25), (70, 6.5, 1.25),
            (72, 8, 0.25), (72, 8.5, 0.25), (75, 8.75, 0.5), (77, 9.5, 0.25), (75, 10, 0.5), (72, 10.75, 0.25), (68, 11, 0.75),
            (74, 12, 0.25), (74, 12.5, 0.25), (77, 12.75, 0.5), (74, 13.5, 0.5), (71, 14, 0.5), (74, 14.75, 1),
        ], vel: 0.85))

        // Sparkle: an eighth-note arp two octaves up.
        var sparkleNotes: [Note] = []
        for (b, v) in voicings.enumerated() {
            let shape = [v[1], v[3], v[2] + 12, v[3], v[1] + 12, v[3], v[2] + 12, v[3] + 12]
            for i in 0..<8 {
                sparkleNotes.append(Note(pitch: shape[i] + 12, start: Double(b) * bar + Double(i) * 0.5, length: 0.3, velocity: i % 2 == 0 ? 0.8 : 0.55))
            }
        }
        let sparkle = pattern("Sparkle", 6, "Glitter Pluck", sparkleNotes)

        // The topline for Drop 2: bright, gliding, eight bars.
        let topline = pattern("Topline", 9, "Hyper Lead", length: 32, gain: 3, notes([
            (79, 0, 0.75), (77, 0.75, 0.25), (75, 1, 0.5), (72, 1.5, 1), (75, 2.5, 0.5), (77, 3, 1),
            (75, 4, 0.75), (74, 4.75, 0.25), (72, 5, 1), (70, 6, 0.5), (72, 6.5, 1.5),
            (77, 8, 0.75), (75, 8.75, 0.25), (72, 9, 0.5), (68, 9.5, 1), (72, 10.5, 0.5), (75, 11, 1),
            (74, 12, 1), (77, 13, 0.5), (79, 13.5, 1), (74, 14.5, 1.5),
            (79, 16, 0.75), (77, 16.75, 0.25), (75, 17, 0.5), (72, 17.5, 1), (75, 18.5, 0.5), (79, 19, 1),
            (80, 20, 0.75), (79, 20.75, 0.25), (77, 21, 1), (75, 22, 0.5), (77, 22.5, 1.5),
            (80, 24, 1), (79, 25, 0.5), (75, 25.5, 1), (72, 26.5, 0.5), (75, 27, 1),
            (74, 28, 0.5), (77, 28.5, 0.5), (79, 29, 1), (83, 30, 0.5), (84, 30.5, 1.5),
        ], vel: 0.85))

        let zaps = pattern("Zaps", 5, "Laser Zap", length: 16, [Note(pitch: 84, start: 15.5, length: 0.3), Note(pitch: 79, start: 15.75, length: 0.25)])
        let riser = pattern("Riser", 9, "Noise Riser", [Note(pitch: 60, start: 0, length: 16, velocity: 1)])
        let downlifter = pattern("Downlifter", 9, "Downlifter", length: 8, [Note(pitch: 60, start: 0, length: 6, velocity: 1)])
        let boom = pattern("Impact", 3, "Impact Boom", length: 4, [Note(pitch: 36, start: 0, length: 3, velocity: 1)])

        // Beats. 2-step: the kick skips beat 3 and lands on the "and" of 3; swung hats do the shuffle.
        let twoStep = Asset(name: "2-Step", colorIndex: 2, content: .drums(beat("house",
            ["kick": [0, 10], "clap": [4, 12], "chat": [2, 6, 10, 14, 3, 7, 11, 15], "rim": [7, 13], "ohat": [14]],
            velocities: ["chat": [3: 0.35, 7: 0.35, 11: 0.35, 15: 0.35, 2: 0.6, 6: 0.6, 10: 0.6, 14: 0.6], "rim": [7: 0.5, 13: 0.45], "ohat": [14: 0.5]],
            swing: 0.35)))
        let fourFloor = Asset(name: "Four on the Floor", colorIndex: 8, content: .drums(beat("house",
            ["kick": [0, 4, 8, 12], "ohat": [2, 6, 10, 14], "chat": Array(0..<16), "perc": [7, 15]],
            velocities: ["chat": Dictionary(uniqueKeysWithValues: (0..<16).map { ($0, $0 % 2 == 0 ? 0.4 : 0.25) }),
                         "ohat": [2: 0.55, 6: 0.55, 10: 0.55, 14: 0.55], "perc": [7: 0.4, 15: 0.45]],
            swing: 0.2)))
        var roll = DrumPattern(kit: "house", steps: 16)
        for i in roll.rows.indices where roll.rows[i].sound == "snare" {
            for st in 0..<16 { roll.rows[i].steps[st] = 0.3 + 0.6 * Double(st) / 15 }
        }
        let snareRoll = Asset(name: "Snare Roll", colorIndex: 5, content: .drums(roll))

        // Intro: the pad opens up from underwater while the chops drift in. Keyframes do all of it.
        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Air Pad", 10, volume: -2, [clip(pad, at: 0, length: 32)],
                  effects: [keyframed("filter", ["resonance": 0.3], "cutoff", [(0, 350), (28, 6000), (32, 14000)])]),
            track("Hook", 7, volume: -5, [clip(chops, at: 16, length: 16)],
                  effects: [effect("delay", ["time": 6, "feedback": 0.45, "mix": 0.3]),
                            keyframed("reverb", ["size": 0.85], "mix", [(16, 0.6), (32, 0.25)])]),
            track("Sparkle", 6, volume: -14, [clip(sparkle, at: 16, length: 16)], effects: [effect("reverb", ["mix": 0.35, "size": 0.8])]),
            track("Riser", 9, volume: -8, [clip(riser, at: 16, length: 16)], effects: [effect("reverb", ["mix": 0.4, "size": 0.9])]),
        ], effects: [effect("chorus", ["mix": 0.2])])))

        // Drop: the groove. The chops' delay "throws" at the end of each phrase are keyframes on its mix.
        let delayThrows: [(Double, Double)] = [(0, 0.15), (14.5, 0.15), (15, 0.6), (16, 0.15), (30.5, 0.15), (31, 0.6),
                                          (32, 0.15), (46.5, 0.15), (47, 0.6), (48, 0.15), (62.5, 0.15), (63, 0.7), (64, 0.15)]
        let drop = Asset(name: "Drop", colorIndex: 0, content: .composition(Composition(length: 64, tracks: [
            track("2-Step", 2, [clip(twoStep, at: 0, length: 64)]),
            track("Bassline", 1, volume: -3, [clip(bass, at: 0, length: 64)],
                  effects: [effect("saturator", ["drive": 8, "type": 2, "mix": 0.6]), effect("pump", ["depth": 0.55])]),
            track("Garage Stabs", 4, volume: -4, [clip(stabs, at: 0, length: 64)],
                  effects: [effect("pump", ["depth": 0.7]), effect("chorus", ["mix": 0.3]), effect("reverb", ["mix": 0.2])]),
            track("Hook", 7, volume: -2, [clip(chops, at: 0, length: 64)],
                  effects: [keyframed("delay", ["time": 6, "feedback": 0.45], "mix", delayThrows), effect("reverb", ["mix": 0.2])]),
            track("Sparkle", 6, volume: -13, [clip(sparkle, at: 32, length: 32)],
                  effects: [effect("delay", ["time": 2, "feedback": 0.3, "mix": 0.2]), effect("reverb", ["mix": 0.3])]),
            track("Zaps", 5, volume: -10, [clip(zaps, at: 0, length: 64)], effects: [effect("delay", ["mix": 0.35]), effect("reverb", ["mix": 0.3])]),
        ])))

        // Break: everything sinks under a closing filter, then a snare roll and the riser pull you back up.
        let breakdown = Asset(name: "Break", colorIndex: 7, content: .composition(Composition(length: 16, tracks: [
            track("Air Pad", 10, volume: -4, [clip(pad, at: 0, length: 16)]),
            track("Hook", 7, volume: -7, [clip(chops, at: 0, length: 16)],
                  effects: [effect("delay", ["time": 6, "feedback": 0.55, "mix": 0.4]), effect("reverb", ["mix": 0.45, "size": 0.9])]),
            track("Snare Roll", 5, volume: -10, [clip(snareRoll, at: 12, length: 4)], effects: [effect("reverb", ["mix": 0.25])]),
            track("Riser", 9, volume: -8, [clip(riser, at: 0, length: 16)]),
        ], effects: [keyframed("filter", ["resonance": 0.35], "cutoff", [(0, 12000), (8, 900), (15, 3000), (16, 18000)])])))

        // Drop 2: the first half of the Drop (linked), with four-on-the-floor and the topline on top.
        let drop2 = Asset(name: "Drop 2", colorIndex: 6, content: .composition(Composition(length: 32, tracks: [
            track("Drop", 0, [clip(drop, at: 0, length: 32)]),
            track("Four on the Floor", 8, volume: -4, [clip(fourFloor, at: 0, length: 32)]),
            track("Topline", 9, volume: -5, [clip(topline, at: 0, length: 32)],
                  effects: [keyframed("bitcrusher", ["downsample": 2], "mix", [(0, 0), (24, 0), (28, 0.5), (32, 0)]),
                            effect("delay", ["time": 6, "feedback": 0.35, "mix": 0.18]), effect("reverb", ["mix": 0.25])]),
        ])))

        // Outro: the pad and chops, fading out on a clip Volume keyframe.
        let outro = Asset(name: "Outro", colorIndex: 11, content: .composition(Composition(length: 16, tracks: [
            track("Air Pad", 10, volume: -5, [clip(pad, at: 0, length: 16)]),
            track("Hook", 7, volume: -8, [clip(chops, at: 0, length: 16)],
                  effects: [effect("delay", ["time": 6, "feedback": 0.55, "mix": 0.45]), effect("reverb", ["mix": 0.5, "size": 0.9])]),
        ], effects: [keyframed("volume", [:], "volume", [(0, 0), (8, -2), (16, -60)])])))

        var main = Composition(length: 40 * bar)
        main.tracks = [
            track("Intro / Outro", 11, [clip(intro, at: 0, length: 32), clip(outro, at: 36 * bar, length: 16)]),
            track("Drops", 0, [clip(drop, at: 8 * bar, length: 64), clip(drop2, at: 28 * bar, length: 32)]),
            track("Break", 7, [clip(breakdown, at: 24 * bar, length: 16)]),
            track("FX", 3, volume: -4, [clip(boom, at: 8 * bar, length: 4), clip(boom, at: 28 * bar, length: 4),
                                        clip(downlifter, at: 24 * bar, length: 8)],
                  effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ]
        // A simple master: gentle glue, then the limiter.
        main.effects = [effect("compressor", ["threshold": -10, "ratio": 2, "attack": 30, "release": 200]),
                        effect("limiter", ["gain": 4, "ceiling": -1])]
        p.updateComposition(p.mainCompositionID) { $0 = main }

        let sections = Folder(name: "Sections"), pats = Folder(name: "Patterns"), beats = Folder(name: "Beats"), fx = Folder(name: "FX")
        p.folders = [sections, pats, beats, fx]
        func put(_ a: Asset, _ f: Folder) -> Asset { var a = a; a.folderID = f.id; return a }
        p.assets += [intro, drop, breakdown, drop2, outro].map { put($0, sections) }
        p.assets += [pad, stabs, bass, chops, sparkle, topline].map { put($0, pats) }
        p.assets += [twoStep, fourFloor, snareRoll].map { put($0, beats) }
        p.assets += [riser, downlifter, boom, zaps].map { put($0, fx) }
        p.migrateDrumPatterns()
        return p
    }
}
