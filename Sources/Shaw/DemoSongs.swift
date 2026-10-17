import ShawCore

extension DemoProject {
    /// A synth pattern. `gain` turns the preset's volume up or down (dB) so parts sit together;
    /// `tweak` overrides any synth parameter (each pattern carries its own copy of the sound).
    static func synthPattern(_ name: String, _ color: Int, _ preset: String, length: Double = 16, gain: Double = 0,
                             tweak: [String: Double] = [:], _ notes: [Note]) -> Asset {
        var inst = Instrument.preset(preset)
        inst.params["volume"] = (inst.params["volume"] ?? -8) + gain
        for (k, v) in tweak { inst.params[k] = v }
        return Asset(name: name, colorIndex: color, content: .notes(NotePattern(length: length, notes: notes, instrument: inst)))
    }

    static func filed(_ p: inout Project, sections: [Asset], patterns: [Asset], beats: [Asset], fx: [Asset]) {
        let s = Folder(name: "Sections"), pa = Folder(name: "Patterns"), b = Folder(name: "Beats"), f = Folder(name: "FX")
        p.folders = [s, pa, b, f]
        func put(_ a: Asset, _ folder: Folder) -> Asset { var a = a; a.folderID = folder.id; return a }
        p.assets += sections.map { put($0, s) } + patterns.map { put($0, pa) } + beats.map { put($0, b) } + fx.map { put($0, f) }
        p.migrateDrumPatterns()
    }

    static func snareRoll(_ kit: String, bars: Int = 1, sound: String = "snare") -> DrumPattern {
        var roll = DrumPattern(kit: kit, steps: 16 * bars)
        let n = 16 * bars
        for i in roll.rows.indices where roll.rows[i].sound == sound {
            for st in 0..<n where bars == 1 || st >= n - 16 || st % 2 == 0 {
                roll.rows[i].steps[st] = 0.3 + 0.65 * Double(st) / Double(n - 1)
            }
        }
        return roll
    }

    // MARK: - Afterburn

    /// "Afterburn": F♯ minor bass house in the style of Knock2, 128 BPM, 40 bars (about 75 seconds).
    /// A hard four-on-the-floor drop with a call-and-response bass riff, "hey" chops, and rave stabs,
    /// then a trap half-time switch-up where a growl and a riddim bass trade bars.
    /// Intro (8) · Drop (16) · Switch-Up (8) · Last Drop (8)
    static func afterburn() -> Project {
        var p = Project(name: "Afterburn", bpm: 128)
        let bar = 4.0

        // The riff: two bars of call, two bars of answer.
        // No sub oscillator: the kick owns the very bottom, so the two don't pile up into boom.
        let riff = synthPattern("Bass Riff", 1, "Bass House", gain: 2, tweak: ["sub": 0], notes([
            (42, 0, 0.5), (42, 0.75, 0.25), (42, 1.5, 0.5), (54, 2.25, 0.25), (42, 2.5, 0.5), (45, 3.5, 0.5),
            (42, 4, 0.5), (52, 5.5, 0.5), (50, 6, 0.75), (49, 7, 0.5), (42, 7.5, 0.5),
            (42, 8, 0.5), (42, 8.75, 0.25), (42, 9.5, 0.5), (54, 10.25, 0.25), (42, 10.5, 0.5), (45, 11.5, 0.5),
            (47, 12, 0.5), (45, 12.75, 0.5), (42, 13.5, 0.5), (49, 14.25, 0.25), (52, 14.5, 0.5), (54, 15, 1),
        ], vel: 0.9))

        // Rave stabs: F#m and E, hit on the one and pushed on the "and" of 3.
        var stabNotes: [Note] = []
        for (b, chord) in [[54, 57, 61], [54, 57, 61], [52, 56, 59], [52, 56, 59]].enumerated() {
            for t in [0.0, 2.5] { stabNotes += chord.map { Note(pitch: $0, start: Double(b) * bar + t, length: 0.45, velocity: 0.85) } }
        }
        let stabs = synthPattern("Rave Stabs", 10, "Hoover", gain: 2, stabNotes)

        // "Hey!" chops on the off-beats.
        let chops = synthPattern("Hey Chops", 7, "Vowel Lead", gain: 5, tweak: ["mode": 0, "r": 0.08, "cutoff": 1400], notes([
            (66, 1.5, 0.2), (66, 3.5, 0.2), (69, 5.5, 0.2), (66, 7.25, 0.15), (66, 7.5, 0.2),
            (66, 9.5, 0.2), (66, 11.5, 0.2), (71, 13.5, 0.2), (69, 15.25, 0.15), (66, 15.5, 0.2),
        ]))
        let screech = synthPattern("Screech", 5, "Screech Lead", length: 32, gain: 1, notes([(78, 15, 0.75), (73, 31, 0.75)]))

        // Switch-up basses: the same sound with different movement, traded every two bars.
        let growl = synthPattern("Growl", 1, "Growl Bass", length: 8, gain: 2, notes([
            (42, 0, 0.75), (42, 1, 0.5), (45, 1.75, 0.75), (42, 3, 1),
            (40, 4, 0.75), (40, 5, 0.5), (37, 5.75, 0.75), (42, 7, 1),
        ], vel: 0.9))
        let riddim = synthPattern("Riddim", 3, "Riddim Bass", length: 8, gain: 2, notes([
            (42, 0, 0.5), (42, 0.75, 0.5), (42, 1.5, 0.5), (42, 2.5, 1),
            (45, 4, 0.5), (45, 4.75, 0.5), (40, 5.5, 0.5), (42, 6.5, 1.5),
        ], vel: 0.9))

        let riser = synthPattern("Riser", 9, "Noise Riser", [Note(pitch: 60, start: 0, length: 16, velocity: 1)])
        let boom = synthPattern("Impact", 3, "Impact Boom", length: 4, [Note(pitch: 30, start: 0, length: 3, velocity: 1)])
        let zaps = synthPattern("Zaps", 5, "Laser Zap", length: 16, [Note(pitch: 78, start: 7.5, length: 0.25), Note(pitch: 85, start: 15.5, length: 0.3)])

        // Beats
        let bangers = Asset(name: "Four on the Floor", colorIndex: 2, content: .drums(beat("house",
            ["kick": [0, 4, 8, 12], "clap": [4, 12], "chat": [2, 6, 10, 14, 3, 11], "ohat": [2, 6, 10, 14], "perc": [7, 15]],
            velocities: ["chat": [3: 0.3, 11: 0.3, 2: 0.5, 6: 0.5, 10: 0.5, 14: 0.5], "ohat": [2: 0.45, 6: 0.45, 10: 0.45, 14: 0.45],
                         "perc": [7: 0.4, 15: 0.5]], swing: 0.15)))
        var trapBeat = beat("trap", steps: 32,
            ["kick": [0, 10, 16, 23, 26], "snare": [8, 24], "clap": [8, 24], "chat": [0, 2, 4, 6, 8, 10, 12, 16, 18, 20, 22, 24, 26],
             "ohat": [14]],
            velocities: ["chat": Dictionary(uniqueKeysWithValues: [0, 2, 4, 6, 8, 10, 12, 16, 18, 20, 22, 24, 26].map { ($0, 0.5) })])
        // Hat rolls into each bar: 1/32 and 1/48 bursts.
        for i in trapBeat.rows.indices where trapBeat.rows[i].sound == "chat" {
            for st in [13, 14, 15, 28, 29, 30, 31] { trapBeat.rows[i].steps[st] = 0.35 + Double(st % 16) * 0.03 }
        }
        let trap = Asset(name: "Trap Switch", colorIndex: 8, content: .drums(trapBeat))
        let roll = Asset(name: "Snare Roll", colorIndex: 5, content: .drums(snareRoll("house", bars: 2)))
        let crash = Asset(name: "Crash", colorIndex: 9, content: .drums(beat("house", ["crash": [0]], velocities: ["crash": [0: 0.8]])))

        // Intro: the beat is filtered down to a thump and opens up while the riser climbs.
        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Four on the Floor", 2, volume: -12, [clip(bangers, at: 0, length: 24)],
                  effects: [keyframed("filter", ["resonance": 0.3], "cutoff", [(0, 250), (24, 3500)])]),
            track("Rave Stabs", 10, volume: -13, [clip(stabs, at: 0, length: 32)],
                  effects: [keyframed("filter", ["resonance": 0.2], "cutoff", [(0, 600), (32, 9000)]), effect("reverb", ["mix": 0.3])]),
            track("Hey Chops", 7, volume: -11, [clip(chops, at: 16, length: 16)], effects: [effect("delay", ["time": 5, "mix": 0.25])]),
            track("Snare Roll", 5, volume: -12, [clip(roll, at: 24, length: 8)]),
            track("Riser", 9, volume: -10, [clip(riser, at: 16, length: 16)], effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ])))

        let drop = Asset(name: "Drop", colorIndex: 0, content: .composition(Composition(length: 64, tracks: [
            track("Four on the Floor", 2, volume: -3, [clip(bangers, at: 0, length: 64)]),
            track("Crash", 9, volume: -8, [clip(crash, at: 0, length: 4), clip(crash, at: 32, length: 4)]),
            track("Bass Riff", 1, volume: 1, [clip(riff, at: 0, length: 64)],
                  effects: [effect("eq", ["lowgain": -4, "lowfreq": 90, "midgain": -4, "midfreq": 320, "midq": 1.2]),
                            effect("saturator", ["drive": 8, "type": 2, "mix": 0.5]), effect("pump", ["depth": 0.55])]),
            track("Hey Chops", 7, volume: 0, [clip(chops, at: 0, length: 64)],
                  effects: [effect("chorus", ["mix": 0.35, "depth": 0.4]), effect("delay", ["time": 5, "mix": 0.22, "pingpong": 1]),
                            effect("reverb", ["mix": 0.2, "width": 1])]),
            track("Rave Stabs", 10, volume: -5, [clip(stabs, at: 0, length: 64)],
                  effects: [effect("eq", ["lowgain": -10, "lowfreq": 200]), effect("chorus", ["mix": 0.45, "depth": 0.6]),
                            effect("utility", ["width": 1.6]), effect("pump", ["depth": 0.6]), effect("reverb", ["mix": 0.22])]),
            track("Screech", 5, volume: -4, [clip(screech, at: 0, length: 64)], effects: [effect("reverb", ["mix": 0.25])]),
            track("Zaps", 5, volume: -10, [clip(zaps, at: 0, length: 64)], effects: [effect("delay", ["mix": 0.3])]),
        ])))

        // Switch-up: half-time trap drums, growl and riddim trading every two bars.
        let switchUp = Asset(name: "Switch-Up", colorIndex: 6, content: .composition(Composition(length: 32, tracks: [
            track("Trap Switch", 8, [clip(trap, at: 0, length: 32)], effects: [effect("compressor", ["threshold": -14, "ratio": 4])]),
            track("Growl", 1, volume: 1, [clip(growl, at: 0, length: 8), clip(growl, at: 16, length: 8)],
                  effects: [effect("saturator", ["drive": 6, "mix": 0.5])]),
            track("Riddim", 3, volume: 1, [clip(riddim, at: 8, length: 8), clip(riddim, at: 24, length: 8)],
                  effects: [effect("saturator", ["drive": 6, "type": 3, "mix": 0.35])]),
            track("Hey Chops", 7, volume: -6, [clip(chops, at: 0, length: 32)],
                  effects: [keyframed("bitcrusher", ["downsample": 3], "mix", [(0, 0), (24, 0), (32, 0.6)])]),
            track("Riser", 9, volume: -9, [clip(riser, at: 16, length: 16)]),
        ])))

        // Last drop: the Drop (linked), with the stabs doubled for the whole run.
        let lastDrop = Asset(name: "Last Drop", colorIndex: 4, content: .composition(Composition(length: 32, tracks: [
            track("Drop", 0, [clip(drop, at: 0, length: 32)]),
            track("Rave Stabs", 10, volume: -3, [clip(stabs, at: 0, length: 32)], effects: [effect("pump", ["depth": 0.6]), effect("reverb", ["mix": 0.2])]),
        ])))

        var main = Composition(length: 41 * bar)
        main.tracks = [
            track("Intro", 11, [clip(intro, at: 0, length: 32)]),
            track("Drops", 0, [clip(drop, at: 8 * bar, length: 64), clip(lastDrop, at: 32 * bar, length: 32)]),
            track("Switch-Up", 6, [clip(switchUp, at: 24 * bar, length: 32)]),
            track("FX", 3, volume: -4, [clip(boom, at: 8 * bar, length: 4), clip(boom, at: 24 * bar, length: 4),
                                        clip(boom, at: 32 * bar, length: 4), clip(boom, at: 40 * bar, length: 4)],
                  effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ]
        // A simple master: gentle glue, then the limiter.
        main.effects = [effect("compressor", ["threshold": -10, "ratio": 2, "attack": 30, "release": 200]),
                        effect("limiter", ["gain": 1.5, "ceiling": -1])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, drop, switchUp, lastDrop], patterns: [riff, stabs, chops, screech, growl, riddim],
              beats: [bangers, trap, roll, crash], fx: [riser, boom, zaps])
        return p
    }

    // MARK: - Lanterns

    /// Drum pattern written as hits: (sound, beat, velocity). Exact timing, ghost notes, and rolls.
    static func kitPattern(_ name: String, _ color: Int, _ kit: String, length: Double, _ hits: [(String, Double, Double)]) -> Asset {
        let notes = hits.map { Note(pitch: DrumKits.pitch(of: $0.0), start: $0.1, length: 0.25, velocity: $0.2) }
        return Asset(name: name, colorIndex: color, content: .notes(NotePattern(length: length, notes: notes, instrument: .kit(kit))))
    }

    /// "Lanterns": E major melodic dubstep in the style of Porter Robinson's Worlds, 140 BPM half-time, 40 bars (about 69 seconds).
    /// Intro (8) · Build (4) · Drop (8) · Drop B (8) · Glitch Bridge (4) · Last Drop (8)
    static func lanterns() -> Project {
        var p = Project(name: "Lanterns", bpm: 140)
        let bar = 4.0

        // C#m7 – Amaj9 – E/G# – Bsus4 → B. The pad's top voices barely move while the bass walks
        // down under them, which is what makes it sound lush instead of blocky.
        let pads: [[Int]] = [[56, 59, 61, 64], [56, 59, 61, 64], [56, 59, 64, 66], [54, 59, 64, 66]]
        let bassRoots = [37, 33, 32, 35]
        func padNotes(_ octave: Int, vel: Double, len: Double = 4) -> [Note] {
            var n: [Note] = []
            for (b, v) in pads.enumerated() {
                if b == 3 {
                    // Bsus4 for two beats, then the 4th (E) falls to the 3rd (D#).
                    n += v.map { Note(pitch: $0 + octave, start: 12, length: 2, velocity: vel) }
                    n += [54, 59, 63, 66].map { Note(pitch: $0 + octave, start: 14, length: min(2, len), velocity: vel) }
                } else {
                    n += v.map { Note(pitch: $0 + octave, start: Double(b) * bar, length: len, velocity: vel) }
                }
            }
            return n
        }

        // The hook: a 2-bar idea, answered, then repeated higher with a different ending.
        // Chord tones land on the beats; the passing notes sit between them.
        let hook: [(Int, Double, Double)] = [
            (80, 0, 1), (76, 1, 0.5), (78, 1.5, 0.5), (80, 2, 1), (83, 3, 0.5), (80, 3.5, 0.5),
            (83, 4, 1.5), (80, 5.5, 0.5), (76, 6, 1.5), (78, 7.5, 0.5),
            (80, 8, 1), (78, 9, 0.5), (76, 9.5, 0.5), (71, 10, 1), (76, 11, 0.5), (78, 11.5, 0.5),
            (78, 12, 2), (75, 14, 0.5), (73, 14.5, 0.5), (75, 15, 1),
            (80, 16, 1), (76, 17, 0.5), (78, 17.5, 0.5), (80, 18, 1), (83, 19, 0.5), (85, 19.5, 0.5),
            (88, 20, 1.5), (85, 21.5, 0.5), (83, 22, 1.5), (80, 23.5, 0.5),
            (83, 24, 1), (80, 25, 0.5), (78, 25.5, 0.5), (76, 26, 1), (80, 27, 0.5), (83, 27.5, 0.5),
            (78, 28, 2), (75, 30, 1), (78, 31, 1),
        ]

        // Rolled chords: each note a little later than the one under it, like a hand on keys.
        func rolled(_ chord: [Int], at start: Double, length: Double) -> [Note] {
            chord.enumerated().map { i, pitch in
                Note(pitch: pitch, start: start + Double(i) * 0.06, length: length - Double(i) * 0.06, velocity: 0.62 + Double(i) * 0.04)
            }
        }
        var pianoNotes: [Note] = []
        for (b, v) in pads.enumerated() {
            if b == 3 {
                pianoNotes += rolled(v, at: 12, length: 1.9) + rolled([54, 59, 63, 66], at: 14, length: 1.9)
            } else {
                pianoNotes += rolled(v, at: Double(b) * bar, length: 3.8)
            }
            pianoNotes.append(Note(pitch: bassRoots[b] + 12, start: Double(b) * bar, length: 3.9, velocity: 0.6))
        }
        let keys = synthPattern("Keys", 4, "Electric Piano", gain: 2, pianoNotes)
        let strings = synthPattern("Strings", 10, "Strings", gain: 2, padNotes(0, vel: 0.6))
        let musicBox = synthPattern("Music Box", 6, "Music Box", length: 32, gain: 1, notes(hook, vel: 0.7))
        let lead = synthPattern("Lead", 7, "Shimmer Lead", length: 32, gain: 3, notes(hook, vel: 0.85))
        // An octave-up shimmer that doubles the lead's long notes only.
        let shimmer = synthPattern("Shimmer", 9, "Glass Pad", length: 32, gain: 2,
                                   notes(hook.filter { $0.2 >= 1 }.map { ($0.0 + 12, $0.1, $0.2) }, vel: 0.6))

        // Build arp: chord tones in 16ths, rising each bar.
        var arpNotes: [Note] = []
        for (b, v) in pads.enumerated() {
            let shape = [v[0], v[1], v[2], v[3], v[2] + 12, v[3], v[2], v[1]].map { $0 + 12 + (b == 3 ? 0 : 0) }
            for i in 0..<16 {
                var pitch = shape[i % 8]
                if b == 3 && i >= 8 && pitch % 12 == 4 { pitch -= 1 } // E falls to D# with the chord
                arpNotes.append(Note(pitch: pitch, start: Double(b) * bar + Double(i) * 0.25, length: 0.2, velocity: i % 4 == 0 ? 0.85 : 0.55))
            }
        }
        let arp = synthPattern("Arp", 4, "Pluck", gain: 1, arpNotes)

        // Drop: wide supersaws on the chords, ducked on every half note; sub and growl split the low end.
        let saws = synthPattern("Supersaws", 0, "Hyper Saw", gain: 2, padNotes(12, vel: 0.8, len: 3.9))
        let sub = synthPattern("Sub", 1, "Sub Bass", gain: 1, bassRoots.enumerated().map { b, r in
            Note(pitch: r - 12, start: Double(b) * bar, length: 3.9, velocity: 0.9)
        })
        // Growl: a rhythmic phrase per bar, so the wobble talks instead of droning.
        func growl(_ name: String, sync: Double, shape: Double, _ color: Int) -> Asset {
            let rhythm: [(Double, Double, Int)] = [(0, 1.5, 0), (1.75, 0.25, 12), (2, 0.75, 0), (3, 1, 7)]
            return synthPattern(name, color, "Growl Bass", gain: 3, tweak: ["lfosync": sync, "lfoshape": shape],
                                bassRoots.enumerated().flatMap { b, r in
                                    rhythm.map { Note(pitch: r + $0.2, start: Double(b) * bar + $0.0, length: $0.1, velocity: 0.9) }
                                })
        }
        let growlA = growl("Growl 1/8", sync: 2, shape: 1, 1)
        let growlB = growl("Growl 1/16", sync: 1, shape: 0, 3)
        let growlC = growl("Growl 1/8T", sync: 3, shape: 2, 5)

        let riser = synthPattern("Riser", 9, "Noise Riser", [Note(pitch: 60, start: 0, length: 15, velocity: 1)])
        let downlifter = synthPattern("Downlifter", 9, "Downlifter", length: 8, [Note(pitch: 60, start: 0, length: 6, velocity: 1)])
        let boom = synthPattern("Impact", 3, "Impact Boom", length: 4, [Note(pitch: 28, start: 0, length: 3, velocity: 1)])

        // Drums, half-time: kick on 1, snare on 3, ghost notes and hat accents so it grooves.
        var dropHits: [(String, Double, Double)] = []
        for b in 0..<2 {
            let o = Double(b) * 4
            dropHits += [("kick", o, 1), ("kick", o + 1.75, 0.6), ("snare", o + 2, 1), ("clap", o + 2, 0.7)]
            for h in stride(from: 0.0, to: 4, by: 0.5) { dropHits.append(("chat", o + h, h.truncatingRemainder(dividingBy: 1) == 0 ? 0.55 : 0.35)) }
            dropHits.append(("snare", o + 3.75, 0.25)) // ghost
        }
        dropHits += [("kick", 6.5, 0.7), ("ohat", 7.5, 0.4)]
        let drums = kitPattern("Half-Time", 2, "electro", length: 8, dropHits)
        // Fill for the end of every 4 bars: snare and toms.
        let fill = kitPattern("Fill", 8, "electro", length: 4, [
            ("kick", 0, 1), ("snare", 2, 1), ("clap", 2, 0.7), ("tomhi", 3, 0.7), ("tomhi", 3.25, 0.7), ("tomlo", 3.5, 0.8), ("snare", 3.75, 0.9),
        ])
        var rollHits: [(String, Double, Double)] = []
        for i in 0..<16 { rollHits.append(("snare", Double(i) * 0.5, 0.3 + Double(i) * 0.02)) }
        for i in 0..<24 { rollHits.append(("snare", 8 + Double(i) * (7.5 / 24), 0.6 + Double(i) * 0.015)) }
        let roll = kitPattern("Snare Roll", 5, "electro", length: 16, rollHits)
        let crash = kitPattern("Crash", 9, "electro", length: 4, [("crash", 0, 0.8)])

        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Keys", 4, volume: -7, [clip(keys, at: 0, length: 32)], effects: [effect("reverb", ["mix": 0.3, "size": 0.75])]),
            track("Strings", 10, volume: -10, [clip(strings, at: 0, length: 32)],
                  effects: [keyframed("volume", [:], "volume", [(0, -30), (16, -6), (32, 0)])]),
            track("Music Box", 6, volume: -7, [clip(musicBox, at: 16, length: 16)],
                  effects: [effect("delay", ["time": 6, "feedback": 0.35, "mix": 0.2]), effect("reverb", ["mix": 0.4, "size": 0.9])]),
            track("Sub", 1, volume: -12, [clip(sub, at: 16, length: 16)]),
        ])))

        let build = Asset(name: "Build", colorIndex: 5, content: .composition(Composition(length: 16, tracks: [
            track("Arp", 4, volume: -6, [clip(arp, at: 0, length: 15)], effects: [effect("delay", ["time": 4, "mix": 0.15]), effect("reverb", ["mix": 0.2])]),
            track("Keys", 4, volume: -8, [clip(keys, at: 0, length: 15)]),
            track("Snare Roll", 5, volume: -8, [clip(roll, at: 0, length: 15)]),
            track("Riser", 9, volume: -9, [clip(riser, at: 0, length: 16)]),
        ], effects: [keyframed("filter", ["type": 1, "resonance": 0.15], "cutoff", [(0, 60), (15, 500)])])))

        func dropSection(_ name: String, _ color: Int, lead leadClip: Bool, growls: [Asset]) -> Asset {
            Asset(name: name, colorIndex: color, content: .composition(Composition(length: 32, tracks: [
                track("Drums", 2, [clip(drums, at: 0, length: 12), clip(fill, at: 12, length: 4), clip(drums, at: 16, length: 12), clip(fill, at: 28, length: 4)]),
                track("Supersaws", 0, volume: -6, [clip(saws, at: 0, length: 32)],
                      effects: [effect("pump", ["rate": 3, "depth": 0.7, "release": 0.45]), effect("reverb", ["mix": 0.2, "size": 0.8])]),
                track("Sub", 1, volume: -6, [clip(sub, at: 0, length: 32)], effects: [effect("pump", ["rate": 3, "depth": 0.5])]),
                track("Growl", 3, volume: -3, growls.enumerated().map { i, g in clip(g, at: Double(i) * 8, length: 8) },
                      effects: [effect("eq", ["lowgain": -12, "lowfreq": 120]), effect("saturator", ["drive": 4, "mix": 0.4])]),
                track("Lead", 7, volume: leadClip ? -4 : -60, [clip(lead, at: 0, length: 32)],
                      effects: [effect("delay", ["time": 6, "feedback": 0.3, "mix": 0.18]), effect("reverb", ["mix": 0.25, "size": 0.8])]),
                track("Shimmer", 9, volume: leadClip ? -12 : -60, [clip(shimmer, at: 0, length: 32)], effects: [effect("reverb", ["mix": 0.5, "size": 0.9])]),
            ])))
        }
        let dropA = dropSection("Drop", 0, lead: false, growls: [growlA, growlA, growlB, growlA])
        let dropB = dropSection("Drop B", 0, lead: true, growls: [growlA, growlC, growlA, growlB])

        let bridge = Asset(name: "Glitch Bridge", colorIndex: 7, content: .composition(Composition(length: 16, tracks: [
            track("Supersaws", 0, volume: -10, [clip(saws, at: 0, length: 16)],
                  effects: [effect("autopan", ["rate": 0, "amount": 1, "shape": 2, "mode": 1]),
                            keyframed("bitcrusher", ["downsample": 4], "bits", [(0, 12), (12, 6), (16, 4)]),
                            keyframed("filter", ["resonance": 0.3], "cutoff", [(0, 8000), (16, 1200)])]),
            track("Music Box", 6, volume: -6, [clip(musicBox, at: 0, length: 16)], effects: [effect("reverb", ["mix": 0.45, "size": 0.9])]),
            track("Snare Roll", 5, volume: -9, [clip(roll, at: 0, length: 15)]),
        ])))

        var main = Composition(length: 41 * bar)
        main.tracks = [
            track("Intro", 11, [clip(intro, at: 0, length: 32)]),
            track("Build", 5, [clip(build, at: 8 * bar, length: 16)]),
            track("Drops", 0, [clip(dropA, at: 12 * bar, length: 32), clip(dropB, at: 20 * bar, length: 32), clip(dropB, at: 32 * bar, length: 32)]),
            track("Bridge", 7, [clip(bridge, at: 28 * bar, length: 16)]),
            track("Crash", 9, volume: -6, [clip(crash, at: 12 * bar, length: 4), clip(crash, at: 20 * bar, length: 4), clip(crash, at: 32 * bar, length: 4)]),
            track("FX", 3, volume: -6, [clip(boom, at: 12 * bar, length: 4), clip(boom, at: 32 * bar, length: 4),
                                        clip(downlifter, at: 28 * bar, length: 8), clip(boom, at: 40 * bar, length: 4)],
                  effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ]
        // A simple master: gentle glue, then the limiter. No compressors stacked on every section.
        main.effects = [effect("compressor", ["threshold": -10, "ratio": 2, "attack": 30, "release": 200]),
                        effect("limiter", ["gain": 3.5, "ceiling": -1])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, build, dropA, dropB, bridge],
              patterns: [keys, strings, musicBox, lead, shimmer, arp, saws, sub, growlA, growlB, growlC],
              beats: [drums, fill, roll, crash], fx: [riser, downlifter, boom])
        return p
    }
}
