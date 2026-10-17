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
        let riff = synthPattern("Bass Riff", 1, "Bass House", gain: 2, notes([
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
        let bangers = Asset(name: "Four on the Floor", colorIndex: 2, content: .drums(beat("techno",
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
        let roll = Asset(name: "Snare Roll", colorIndex: 5, content: .drums(snareRoll("techno", bars: 2)))
        let crash = Asset(name: "Crash", colorIndex: 9, content: .drums(beat("techno", ["crash": [0]], velocities: ["crash": [0: 0.8]])))

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
            track("Four on the Floor", 2, [clip(bangers, at: 0, length: 64)], effects: [effect("compressor", ["threshold": -14, "ratio": 4, "attack": 10])]),
            track("Crash", 9, volume: -8, [clip(crash, at: 0, length: 4), clip(crash, at: 32, length: 4)]),
            track("Bass Riff", 1, volume: 3, [clip(riff, at: 0, length: 64)],
                  effects: [effect("saturator", ["drive": 10, "type": 2, "mix": 0.7]), effect("pump", ["depth": 0.5]),
                            effect("compressor", ["threshold": -18, "ratio": 4, "attack": 5])]),
            track("Hey Chops", 7, volume: 0, [clip(chops, at: 0, length: 64)], effects: [effect("delay", ["time": 5, "mix": 0.15]), effect("reverb", ["mix": 0.15])]),
            track("Rave Stabs", 10, volume: -3, [clip(stabs, at: 32, length: 32)], effects: [effect("pump", ["depth": 0.6]), effect("reverb", ["mix": 0.2])]),
            track("Screech", 5, volume: -4, [clip(screech, at: 0, length: 64)], effects: [effect("reverb", ["mix": 0.25])]),
            track("Zaps", 5, volume: -10, [clip(zaps, at: 0, length: 64)], effects: [effect("delay", ["mix": 0.3])]),
        ], effects: [effect("compressor", ["threshold": -12, "ratio": 2.5, "attack": 20])])))

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
        main.effects = [effect("eq", ["lowgain": 2, "highgain": 1]),
                        effect("compressor", ["threshold": -14, "ratio": 2, "attack": 30, "release": 150, "makeup": 1]),
                        effect("limiter", ["gain": 3, "ceiling": -0.5])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, drop, switchUp, lastDrop], patterns: [riff, stabs, chops, screech, growl, riddim],
              beats: [bangers, trap, roll, crash], fx: [riser, boom, zaps])
        return p
    }

    // MARK: - Lanterns

    /// "Lanterns": E major melodic dubstep in the style of Porter Robinson's Worlds, 140 BPM half-time, 40 bars (about 69 seconds).
    /// Orchestral strings and a music-box melody, a chiptune build, then a half-time drop with huge pumping
    /// supersaws and a growl bass that switches wobble speed, a glitchy gated bridge, and a last drop.
    /// Intro (8) · Build (4) · Drop (16) · Glitch Bridge (4) · Last Drop (8)
    static func lanterns() -> Project {
        var p = Project(name: "Lanterns", bpm: 140)
        let bar = 4.0

        // C#m – A – E – B (vi – IV – I – V): the bittersweet one.
        let voicings: [[Int]] = [[56, 61, 64, 68], [57, 61, 64, 69], [56, 59, 64, 68], [54, 59, 63, 66]]
        let roots = [37, 33, 40, 35]

        var stringNotes: [Note] = []
        for (b, v) in voicings.enumerated() {
            stringNotes += (v + [v[0] - 12]).map { Note(pitch: $0, start: Double(b) * bar, length: 4, velocity: 0.65) }
        }
        let strings = synthPattern("Strings", 10, "Strings", gain: 3, stringNotes)

        let melody: [(Int, Double, Double)] = [
            (68, 0, 0.5), (71, 0.5, 0.5), (73, 1, 1), (71, 2, 0.5), (68, 2.5, 0.5), (66, 3, 1),
            (64, 4, 0.5), (66, 4.5, 0.5), (68, 5, 1.5), (71, 6.5, 0.5), (73, 7, 1),
            (76, 8, 1), (75, 9, 0.5), (73, 9.5, 0.5), (71, 10, 1), (68, 11, 1),
            (66, 12, 0.5), (68, 12.5, 0.5), (71, 13, 0.5), (75, 13.5, 0.5), (73, 14, 2),
        ]
        let musicBox = synthPattern("Music Box", 6, "Music Box", gain: 2, notes(melody.map { ($0.0 + 12, $0.1, $0.2) }, vel: 0.75))
        let lead = synthPattern("Lead", 7, "Shimmer Lead", gain: 3, notes(melody.map { ($0.0 + 12, $0.1, $0.2) }, vel: 0.85))
        // A "synthesized voice" answering the lead, like Worlds' vocal synths.
        let voice = synthPattern("Voice", 9, "Vowel Lead", gain: 5, notes([
            (80, 2, 0.5), (78, 2.5, 0.5), (76, 3, 0.75), (80, 10, 0.5), (83, 10.5, 0.5), (80, 11, 0.75),
            (78, 14.5, 0.5), (76, 15, 0.75),
        ], vel: 0.8))

        // Chiptune arp for the build: General MIDI-toy energy.
        var arpNotes: [Note] = []
        for (b, v) in voicings.enumerated() {
            let shape = [v[0], v[1], v[2], v[3], v[2] + 12, v[3], v[2], v[1]]
            for i in 0..<16 { arpNotes.append(Note(pitch: shape[i % 8] + 12, start: Double(b) * bar + Double(i) * 0.25, length: 0.2, velocity: i % 4 == 0 ? 0.85 : 0.55)) }
        }
        let arp = synthPattern("Chip Arp", 4, "Chip Arp", gain: 1, arpNotes)

        // Drop chords: big supersaws, held through each bar so the pump does the rhythm.
        var chordNotes: [Note] = []
        for (b, v) in voicings.enumerated() {
            chordNotes += (v + [v[1] + 12]).map { Note(pitch: $0 + 12, start: Double(b) * bar, length: 3.9, velocity: 0.8) }
        }
        let chords = synthPattern("Supersaws", 0, "Hyper Saw", gain: 3, chordNotes)
        let sub = synthPattern("Sub", 1, "Sub Bass", gain: 1, roots.enumerated().map { b, r in
            Note(pitch: r - 12, start: Double(b) * bar, length: 3.9, velocity: 0.9)
        })

        // Dubstep basses: one growl sound, three ways of moving. Each pattern carries its own LFO rate.
        func wobble(_ name: String, sync: Double, shape: Double, _ color: Int) -> Asset {
            synthPattern(name, color, "Growl Bass", gain: 3, tweak: ["lfosync": sync, "lfoshape": shape], roots.enumerated().flatMap { b, r -> [Note] in
                [Note(pitch: r, start: Double(b) * bar, length: 1.75, velocity: 0.9),
                 Note(pitch: r, start: Double(b) * bar + 2, length: 0.75, velocity: 0.85),
                 Note(pitch: r + 12, start: Double(b) * bar + 3, length: 0.9, velocity: 0.85)]
            })
        }
        let wobQuarter = wobble("Wobble 1/4", sync: 4, shape: 1, 1)
        let wobEighth = wobble("Wobble 1/8", sync: 2, shape: 2, 3)
        let wobFast = wobble("Wobble 1/16", sync: 1, shape: 4, 5)

        let riser = synthPattern("Riser", 9, "Noise Riser", [Note(pitch: 60, start: 0, length: 16, velocity: 1)])
        let downlifter = synthPattern("Downlifter", 9, "Downlifter", length: 8, [Note(pitch: 60, start: 0, length: 6, velocity: 1)])
        let boom = synthPattern("Impact", 3, "Impact Boom", length: 4, [Note(pitch: 28, start: 0, length: 3, velocity: 1)])

        // Half-time: kick on 1, snare on 3, with a pickup kick.
        let halfTime = Asset(name: "Half-Time", colorIndex: 2, content: .drums(beat("electro", steps: 32,
            ["kick": [0, 14, 16, 26], "snare": [8, 24], "clap": [8, 24], "chat": [0, 4, 8, 12, 16, 20, 24, 28, 30], "ohat": [12, 28]],
            velocities: ["chat": [30: 0.35], "ohat": [12: 0.45, 28: 0.45], "kick": [14: 0.7, 26: 0.75]])))
        let roll = Asset(name: "Snare Roll", colorIndex: 5, content: .drums(snareRoll("electro", bars: 2)))
        let crash = Asset(name: "Crash", colorIndex: 9, content: .drums(beat("electro", ["crash": [0]], velocities: ["crash": [0: 0.8]])))

        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Strings", 10, volume: -8, [clip(strings, at: 0, length: 32)],
                  effects: [keyframed("volume", [:], "volume", [(0, -30), (8, -4), (32, 0)]), effect("reverb", ["mix": 0.3, "size": 0.85])]),
            track("Music Box", 6, volume: -10, [clip(musicBox, at: 0, length: 32)],
                  effects: [effect("delay", ["time": 6, "feedback": 0.4, "mix": 0.25]), effect("reverb", ["mix": 0.35, "size": 0.9])]),
            track("Sub", 1, volume: -14, [clip(sub, at: 16, length: 16)],
                  effects: [keyframed("volume", [:], "volume", [(16, -40), (32, 0)])]),
        ])))

        let build = Asset(name: "Build", colorIndex: 5, content: .composition(Composition(length: 16, tracks: [
            track("Chip Arp", 4, volume: -9, [clip(arp, at: 0, length: 16)], effects: [effect("delay", ["time": 4, "mix": 0.2])]),
            track("Strings", 10, volume: -8, [clip(strings, at: 0, length: 16)]),
            track("Snare Roll", 5, volume: -7, [clip(roll, at: 8, length: 8)], effects: [effect("reverb", ["mix": 0.2])]),
            track("Riser", 9, volume: -6, [clip(riser, at: 0, length: 16)]),
        ], effects: [keyframed("filter", ["type": 1, "resonance": 0.2], "cutoff", [(0, 40), (16, 400)])])))

        // Drop: chords and sub stay; the growl switches its wobble speed every two bars.
        let drop = Asset(name: "Drop", colorIndex: 0, content: .composition(Composition(length: 64, tracks: [
            track("Half-Time", 2, [clip(halfTime, at: 0, length: 64)], effects: [effect("compressor", ["threshold": -14, "ratio": 4, "attack": 10])]),
            track("Crash", 9, volume: -8, [clip(crash, at: 0, length: 4), clip(crash, at: 32, length: 4)]),
            track("Supersaws", 0, volume: -4, [clip(chords, at: 0, length: 64)],
                  effects: [effect("pump", ["rate": 3, "depth": 0.75, "release": 0.4]), effect("reverb", ["mix": 0.25, "size": 0.8])]),
            track("Sub", 1, volume: -5, [clip(sub, at: 0, length: 64)], effects: [effect("pump", ["rate": 3, "depth": 0.6])]),
            track("Wobble", 3, volume: 1, [
                clip(wobQuarter, at: 0, length: 8), clip(wobEighth, at: 8, length: 8), clip(wobQuarter, at: 16, length: 8), clip(wobFast, at: 24, length: 8),
                clip(wobEighth, at: 32, length: 8), clip(wobFast, at: 40, length: 8), clip(wobEighth, at: 48, length: 8), clip(wobFast, at: 56, length: 8),
            ], effects: [effect("saturator", ["drive": 6, "mix": 0.5]), effect("compressor", ["threshold": -18, "ratio": 4, "attack": 5])]),
            track("Lead", 7, volume: -2, [clip(lead, at: 32, length: 32)],
                  effects: [effect("delay", ["time": 6, "feedback": 0.35, "mix": 0.2]), effect("reverb", ["mix": 0.3])]),
        ], effects: [effect("compressor", ["threshold": -12, "ratio": 2.5, "attack": 20])])))

        // Glitch bridge: the chords stutter through a 1/16 gate and crush down to almost nothing.
        let bridge = Asset(name: "Glitch Bridge", colorIndex: 7, content: .composition(Composition(length: 16, tracks: [
            track("Supersaws", 0, volume: -12, [clip(chords, at: 0, length: 16)],
                  effects: [effect("autopan", ["rate": 0, "amount": 1, "shape": 2, "mode": 1]),
                            keyframed("bitcrusher", ["downsample": 6], "bits", [(0, 12), (12, 5), (16, 3)])]),
            track("Music Box", 6, volume: -10, [clip(musicBox, at: 0, length: 16)], effects: [effect("reverb", ["mix": 0.4, "size": 0.9])]),
            track("Voice", 9, volume: -10, [clip(voice, at: 0, length: 16)], effects: [effect("delay", ["time": 6, "feedback": 0.5, "mix": 0.35])]),
            track("Snare Roll", 5, volume: -8, [clip(roll, at: 8, length: 8)]),
        ])))

        let lastDrop = Asset(name: "Last Drop", colorIndex: 4, content: .composition(Composition(length: 32, tracks: [
            // The second half of the Drop, where the lead comes in.
            track("Drop", 0, [{ var c = clip(drop, at: 0, length: 32); c.offset = 32; return c }()]),
            track("Voice", 9, volume: -6, [clip(voice, at: 0, length: 32)], effects: [effect("reverb", ["mix": 0.3])]),
        ])))

        var main = Composition(length: 41 * bar)
        main.tracks = [
            track("Intro", 11, [clip(intro, at: 0, length: 32)]),
            track("Build", 5, [clip(build, at: 8 * bar, length: 16)]),
            track("Drops", 0, [clip(drop, at: 12 * bar, length: 64), clip(lastDrop, at: 32 * bar, length: 32)]),
            track("Bridge", 7, [clip(bridge, at: 28 * bar, length: 16)]),
            track("FX", 3, volume: -4, [clip(boom, at: 12 * bar, length: 4), clip(boom, at: 32 * bar, length: 4),
                                        clip(downlifter, at: 28 * bar, length: 8), clip(boom, at: 40 * bar, length: 4)],
                  effects: [effect("reverb", ["mix": 0.4, "size": 0.9])]),
        ]
        main.effects = [effect("eq", ["lowgain": 1.5, "highgain": 1.5]),
                        effect("compressor", ["threshold": -14, "ratio": 2, "attack": 30, "release": 150, "makeup": 1]),
                        effect("limiter", ["gain": 3, "ceiling": -0.5])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, build, drop, bridge, lastDrop],
              patterns: [strings, musicBox, lead, voice, arp, chords, sub, wobQuarter, wobEighth, wobFast],
              beats: [halfTime, roll, crash], fx: [riser, downlifter, boom])
        return p
    }
}
