import ShawCore

extension DemoProject {
    // MARK: - Starlight FM

    /// "Starlight FM": filtered French-house disco in C minor, 124 BPM, 44 bars (about 85 seconds),
    /// after starjunk 95. One disco loop (strings, funk guitar, electric piano, and horns) is used
    /// like a sample: low-passed and pumping in the intro, swept open for the drop, and chopped up
    /// for the second drop, over a four-on-the-floor kit, an octave disco bass, and vocal chops.
    /// Intro (8) · Drop (16) · Break (8) · Drop 2 (8) · Outro (4)
    static func starlightFM() -> Project {
        var p = Project(name: "Starlight FM", bpm: 124)
        let bar = 4.0
        let kit = "house"
        // The sounds the loop is made of, in one place so they're easy to swap.
        let stringSound = "String Section", stabSound = "Brass Stabs"

        // MARK: Harmony
        // The drops vamp on two chords, Cm7 and F9: C dorian, the disco pair. Nothing resolves; the
        // groove, the filter, and the chops carry it. The break goes somewhere lusher (A♭maj9, Gm7,
        // Fm7, B♭11) and lands back on the vamp like coming home.
        struct Chord { let keys: [Int]; let root: Int }
        let cm7 = Chord(keys: [51, 55, 58, 60], root: 36), f9 = Chord(keys: [51, 55, 57, 60], root: 41)
        let abmaj9 = Chord(keys: [55, 58, 60, 63], root: 44), gm7 = Chord(keys: [50, 53, 55, 58], root: 43)
        let fm9 = Chord(keys: [51, 56, 60, 63], root: 41), bb9sus = Chord(keys: [51, 56, 60, 65], root: 46)
        let vamp = [cm7, cm7, f9, f9]
        let lush = [abmaj9, gm7, fm9, bb9sus]

        // A band, not a grid.
        var seed: UInt64 = 0x7374_6172_6c69_6768
        func rand() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53) * 2 - 1
        }
        func human(_ ns: [Note], time: Double = 0.006, vel: Double = 0.05) -> [Note] {
            ns.map { n in
                var n = n
                n.start = max(0, n.start + rand() * time)
                n.velocity = min(1, max(0.1, n.velocity + rand() * vel))
                return n
            }
        }
        func each(_ prog: [Chord], _ body: (Chord, Double) -> [Note]) -> [Note] {
            prog.enumerated().flatMap { body($0.element, Double($0.offset) * bar) }
        }

        // MARK: The disco loop
        // Strings: the chord held and swelling, then a quick run up into the top of the loop.
        let strings = synthPattern("Disco Strings", 10, stringSound, human([
            cm7.keys.map { Note(pitch: $0 + 12, start: 0, length: 7.8, velocity: 0.62) },
            f9.keys.map { Note(pitch: $0 + 12, start: 8, length: 6.9, velocity: 0.62) },
            [(72, 15.0), (74, 15.25), (75, 15.5), (77, 15.75)].map { Note(pitch: $0.0, start: $0.1, length: 0.24, velocity: 0.7) },
        ].flatMap { $0 }, time: 0.01))
        // Funk guitar: muted sixteenths, the accents on the off-beats.
        let accents: [(Int, Double)] = [(0, 0.5), (2, 0.82), (3, 0.42), (6, 0.82), (7, 0.4), (8, 0.5), (10, 0.82), (11, 0.42), (14, 0.82), (15, 0.4)]
        let guitar = synthPattern("Funk Guitar", 7, "Clean Electric Guitar", human(each(vamp) { c, t in
            accents.flatMap { step, v in
                c.keys.suffix(3).enumerated().map { i, k in
                    Note(pitch: k + 12, start: t + Double(step) * 0.25 + Double(i) * 0.006, length: 0.12, velocity: v - Double(i) * 0.03)
                }
            }
        }))
        // Electric piano on the off-beats.
        let keys = synthPattern("Keys", 4, "FM Piano", human(each(vamp) { c, t in
            [0.5, 1.5, 2.5, 3.5].flatMap { at in c.keys.map { Note(pitch: $0, start: t + at, length: 0.3, velocity: 0.55) } }
        }))
        // Horn stabs, answering each other across the loop.
        let horns = synthPattern("Horn Stabs", 5, stabSound, human([(3.5, cm7), (7.0, cm7), (11.5, f9), (15.0, f9)].flatMap { at, c in
            c.keys.suffix(3).map { Note(pitch: $0 + 12, start: at, length: 0.3, velocity: 0.8) }
        }))
        // The loop leaves everything below the low mids to the kick and bass, so they don't muddy.
        let clearLows = effect("eq", ["lowgain": -14, "lowfreq": 280, "midgain": -2, "midfreq": 450, "midq": 0.9])
        let loop = Asset(name: "Disco Loop", colorIndex: 6, content: .composition(Composition(length: 16, tracks: [
            track("Strings", 10, volume: -9, [clip(strings, at: 0, length: 16)], effects: [clearLows, effect("reverb", ["mix": 0.25, "size": 0.75])]),
            track("Funk Guitar", 7, volume: -12, pan: -0.35, [clip(guitar, at: 0, length: 16)],
                  effects: [effect("eq", ["lowgain": -8, "lowfreq": 300, "highgain": 3, "highfreq": 5000]), effect("phaser", ["rate": 0.3, "depth": 0.4, "mix": 0.3])]),
            track("Keys", 4, volume: -12, pan: 0.3, [clip(keys, at: 0, length: 16)], effects: [clearLows, effect("chorus", ["depth": 0.3, "mix": 0.3])]),
            track("Horns", 5, volume: -10, [clip(horns, at: 0, length: 16)], effects: [clearLows, effect("reverb", ["mix": 0.2, "size": 0.6])]),
        ])))

        // MARK: Bass
        // The disco octave: low on the beat, an octave up on the "and", with a pickup into each bar.
        func octaves(_ prog: [Chord], vel: Double = 0.85) -> [Note] {
            human(each(prog) { c, t in
                var ns: [Note] = []
                for b in 0..<4 {
                    ns.append(Note(pitch: c.root, start: t + Double(b), length: 0.4, velocity: vel))
                    ns.append(Note(pitch: c.root + 12, start: t + Double(b) + 0.5, length: 0.3, velocity: vel - 0.12))
                }
                // A pickup on the chord's seventh (B♭ under C, C under F) leans into the next bar.
                ns.append(Note(pitch: c.root + (c.root == 41 ? 7 : 10), start: t + 3.75, length: 0.2, velocity: vel - 0.2))
                return ns
            })
        }
        let bass = synthPattern("Disco Bass", 1, "Pluck Bass", length: 16, gain: 1, octaves(vamp))
        // Under the lush chords the bass stays low, on the beat and its "and", so it never meets the keys.
        let bassBreak = synthPattern("Bass Break", 1, "Pluck Bass", length: 16, gain: 1, human(each(lush) { c, t in
            (0..<8).map { Note(pitch: c.root - 12, start: t + Double($0) * 0.5, length: 0.4, velocity: $0 % 2 == 0 ? 0.78 : 0.6) }
        }))

        // MARK: Voices
        // The hook: a singer's "ah" chopped into a funky two-bar phrase and its answer.
        let hookA: [(Int, Double, Double)] = [
            (75, 0.5, 0.25), (77, 0.75, 0.25), (79, 1.0, 0.5), (77, 1.75, 0.25), (75, 2.5, 0.5), (72, 3.0, 0.75),
            (70, 4.5, 0.25), (72, 4.75, 0.25), (75, 5.0, 0.5), (72, 5.75, 0.25), (70, 6.5, 0.5), (67, 7.0, 0.75),
            (75, 8.5, 0.25), (77, 8.75, 0.25), (79, 9.0, 0.5), (77, 9.75, 0.25), (75, 10.5, 0.5), (72, 11.0, 0.75),
            (69, 12.5, 0.25), (72, 12.75, 0.25), (74, 13.0, 0.5), (72, 13.75, 0.25), (69, 14.5, 0.5), (65, 15.0, 0.75),
        ]
        func chops(_ list: [(Int, Double, Double)]) -> [Note] {
            human(list.map { Note(pitch: $0.0, start: $0.1, length: $0.2, velocity: $0.2 >= 0.5 ? 0.85 : 0.7) }, time: 0.003, vel: 0.03)
        }
        // The second drop sings it higher on the long notes.
        let hookHigh = synthPattern("Vocal Hook (High)", 3, "Vocal Chops", chops(hookA.map { $0.2 >= 0.5 ? ($0.0 + 12, $0.1, $0.2) : $0 }))
        // Her voice as percussion: one short "ah" on G, repeated between the kicks like in Groove District.
        let stabTimes: [(Double, Double)] = [(0.5, 0.8), (1.5, 0.7), (1.75, 0.55), (2.5, 0.8), (3.5, 0.7), (3.75, 0.55),
                                             (4.5, 0.8), (5.5, 0.7), (6.5, 0.8), (6.75, 0.6), (7.25, 0.65), (7.5, 0.75)]
        let vocalStabs = synthPattern("Vocal Stabs", 3, "Vocal Chops", length: 8,
                                      human(stabTimes.map { Note(pitch: 79, start: $0.0, length: 0.14, velocity: $0.1) }, time: 0.003, vel: 0.03))
        // The chopped line answers in the break's first two bars; "Take me away" sings the other two.
        let breakLine = synthPattern("Vocal Break", 3, "Vocal Chops", chops([
            (75, 0.5, 0.5), (74, 1.0, 0.5), (72, 1.5, 1.0), (70, 3.0, 0.5),
            (74, 4.5, 0.5), (72, 5.0, 0.5), (70, 5.5, 1.0), (67, 7.0, 0.5),
        ]))
        // Lines she says or sings, from the Vocals folder (Freesound, CC0). Each plays whole where it
        // lands, unless `cut` ends it on the beat (and the sung ones were tuned to sit in C minor).
        func line(_ name: String, _ file: String, length: Double, at times: [Double], cut: Double? = nil, gain: Double = 0) -> Asset {
            var inst = Instrument.sampler(SampleLibrary.bundledPrefix + "Vocals/\(file).caf")
            for (k, v) in ["volume": gain, "playmode": cut == nil ? 1 : 0, "r": 0.4] { inst.params[k] = v }
            return Asset(name: name, colorIndex: 3, content: .notes(NotePattern(length: length,
                notes: times.map { Note(pitch: 60, start: $0, length: cut ?? 1, velocity: 0.9) }, instrument: inst)))
        }
        // The station: a host comes on the mic over the muffled record, and dedicates the drop,
        // finishing her line just as it hits.
        let radioID = line("Late Night Radio", "Late Night Radio", length: 32, at: [8], gain: -2)
        let dedication = line("Lovers Out There", "Lovers Out There", length: 32, at: [26.6], gain: -2)
        // A sung chorus, two eight-bar phrases sung twice, at the song's tempo (moved to C minor):
        // the drop's hook. Its ad-libs answer the chopped hook in the second drop.
        let chorus = line("Chorus", "Should Have Known Better", length: 64, at: [0], cut: 63, gain: 0)
        let adLibs = line("Ad-Libs", "Should Have Known Better Ad-Libs", length: 32, at: [0], cut: 31.5, gain: -3)
        // "Take me away", tuned to B♭, sung whole: its long B♭ sits in every chord of the break.
        let takeMeAway = line("Take Me Away", "Take Me Away", length: 32, at: [8], gain: -6)
        let oohs = synthPattern("Oohs", 3, "Ooh Pad", each(lush) { c, t in c.keys.suffix(3).map { Note(pitch: $0, start: t, length: 3.9, velocity: 0.66) } })
        // The break's chords: strings and electric piano, held.
        let lushStrings = synthPattern("Break Strings", 10, stringSound, human(each(lush) { c, t in
            c.keys.map { Note(pitch: $0, start: t, length: 3.9, velocity: 0.6) }
        }, time: 0.01))
        let lushKeys = synthPattern("Break Keys", 4, "FM Piano", human(each(lush) { c, t in
            c.keys.enumerated().map { i, k in Note(pitch: k, start: t + Double(i) * 0.05, length: 3.8, velocity: 0.55) }
        }, time: 0.01))

        // MARK: Drums
        func hitsOf(_ hits: [(String, Double, Double)]) -> [(String, Double, Double)] {
            hits.map { ($0.0, max(0, $0.1 + rand() * 0.004), min(1, max(0.1, $0.2 + rand() * 0.04))) }
        }
        func house(_ o: Double, openLast: Bool = true) -> [(String, Double, Double)] {
            var h: [(String, Double, Double)] = []
            for b in 0..<4 {
                let t = o + Double(b)
                h.append(("kick", t, b == 0 ? 0.85 : 0.78))
                if b % 2 == 1 { h.append(("clap", t, 0.85)) }
                if openLast || b < 3 { h.append(("ohat", t + 0.5, 0.58)) }
                h += [("chat", t + 0.25, 0.3), ("chat", t + 0.75, 0.34)]
            }
            return h
        }
        let beat = kitPattern("House Beat", 2, kit, length: 16, hitsOf((0..<4).flatMap { house(Double($0) * 4) }))
        // Every eighth bar: the last beat drops out but for a snare run, a breath before the next phrase.
        let fill = kitPattern("Fill", 8, kit, length: 4, hitsOf(house(0, openLast: false).filter { $0.1 < 3 }
            + (0..<4).map { ("snare", 3 + Double($0) * 0.25, 0.5 + Double($0) * 0.12) }))
        let kickOnly = kitPattern("Kick", 2, kit, length: 4, hitsOf((0..<4).map { ("kick", Double($0), 0.85) }))
        let crash = kitPattern("Crash", 9, kit, length: 4, [("crash", 0, 0.7)])
        func percussion(_ name: String, _ file: String, gain: Double, _ times: [(Double, Double)]) -> Asset {
            var inst = Instrument.sampler(SampleLibrary.bundledPrefix + "Percussion/\(file).caf")
            inst.params["volume"] = gain
            return Asset(name: name, colorIndex: 3, content: .notes(NotePattern(length: 4,
                notes: times.map { Note(pitch: 60, start: max(0, $0.0 + rand() * 0.005), length: 0.25, velocity: $0.1) }, instrument: inst)))
        }
        let shaker = percussion("Shaker", "Shaker", gain: -9, (0..<16).map { (Double($0) * 0.25, $0 % 2 == 0 ? 0.45 : 0.32) })
        let tambourine = percussion("Tambourine", "Tambourine", gain: -7, [(1, 0.75), (3, 0.75), (1.5, 0.4), (3.5, 0.4)])
        let riser = synthPattern("Riser", 9, "Noise Riser", [Note(pitch: 60, start: 0, length: 15.5, velocity: 0.9)])
        let boom = synthPattern("Impact", 3, "Impact Boom", length: 4, [Note(pitch: 30, start: 0, length: 3, velocity: 0.9)])

        // MARK: Effects
        // The French-house pump: everything but the kick ducks on each beat and swells back.
        func pump(_ depth: Double) -> Effect { effect("pump", ["rate": 2, "depth": depth, "release": 0.55]) }
        let room = effect("reverb", ["mix": 0.16, "size": 0.45])
        let drumsFX = [effect("eq", ["lowgain": -3, "lowfreq": 70, "highgain": 2, "highfreq": 8000]),
                       effect("compressor", ["threshold": -14, "ratio": 3, "attack": 10, "release": 120])]
        let bassFX = [effect("filter", ["type": 1, "cutoff": 35, "resonance": 0]),
                      effect("eq", ["lowgain": 0, "lowfreq": 80, "midgain": -5, "midfreq": 250, "midq": 1.1]),
                      effect("saturator", ["drive": 5, "mix": 0.35]), pump(0.5)]
        let voxFX = [effect("eq", ["lowgain": -10, "lowfreq": 350, "highgain": 3, "highfreq": 6000]),
                     effect("delay", ["time": 6, "feedback": 0.3, "pingpong": 1, "mix": 0.2]),
                     effect("reverb", ["mix": 0.28, "size": 0.75]), pump(0.35)]
        let lineFX = [effect("eq", ["lowgain": -8, "lowfreq": 200, "midgain": 3, "midfreq": 3000, "midq": 0.8]),
                      effect("compressor", ["threshold": -18, "ratio": 3, "attack": 5, "release": 120]),
                      effect("delay", ["time": 6, "feedback": 0.25, "pingpong": 1, "mix": 0.15]), effect("reverb", ["mix": 0.2, "size": 0.6])]
        /// The loop, through a low-pass whose cutoff follows `cutoff` (beats in the section, Hz).
        func filtered(_ cutoff: [(Double, Double)], depth: Double = 0.6) -> [Effect] {
            [keyframed("filter", ["resonance": 0.25], "cutoff", cutoff), pump(depth)]
        }
        /// A clip of the loop starting `from` beats into it: the way a producer chops a sample.
        func chop(at start: Double, _ length: Double, from offset: Double) -> Clip {
            var c = clip(loop, at: start, length: length, loops: false)
            c.offset = offset
            return c
        }

        // MARK: Sections
        // Intro: the loop as if heard through a wall, opening a little at a time, the kick joining halfway.
        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Disco Loop", 6, volume: -2, [clip(loop, at: 0, length: 31)],
                  effects: filtered([(0, 380), (16, 700), (28, 1600), (31, 2600)], depth: 0.7)),
            track("Kick", 2, volume: -6, [clip(kickOnly, at: 16, length: 15)],
                  effects: drumsFX + [effect("filter", ["cutoff": 900, "resonance": 0.1])]),
            track("Shaker", 3, volume: -16, [clip(shaker, at: 16, length: 15)],
                  effects: [effect("filter", ["cutoff": 5000, "resonance": 0.1]), room]),
            track("Riser", 9, volume: -14, [clip(riser, at: 16, length: 16)], effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
            // Clear and close, in front of the muffled record, like a host on the mic.
            // The welcome is soft, over the quiet start; the dedication has to cut through the build.
            track("Radio", 3, volume: -7, [clip(radioID, at: 0, length: 32)], effects: lineFX),
            track("Dedication", 3, volume: 0, [clip(dedication, at: 0, length: 32)], effects: lineFX),
        ])))

        let drop = Asset(name: "Drop", colorIndex: 0, content: .composition(Composition(length: 64, tracks: [
            track("Drums", 2, [clip(beat, at: 0, length: 28), clip(fill, at: 28, length: 4), clip(beat, at: 32, length: 28), clip(fill, at: 60, length: 4)],
                  effects: drumsFX),
            track("Tambourine", 3, volume: -6, [clip(tambourine, at: 0, length: 63)], effects: [room]),
            track("Shaker", 3, volume: -10, [clip(shaker, at: 0, length: 63)], effects: [room]),
            track("Bass", 1, volume: -1, [clip(bass, at: 0, length: 63)], effects: bassFX),
            track("Disco Loop", 6, volume: -3, [clip(loop, at: 0, length: 63)], effects: [pump(0.55)]),
            // She sings the whole drop; the chopped "ah" waits for the second one.
            track("Chorus", 3, volume: 1, [clip(chorus, at: 0, length: 64)],
                  effects: lineFX + [effect("reverb", ["mix": 0.18, "size": 0.7]), pump(0.25)]),
        ])))

        // Break: the floor drops away to the lush chords; the kick creeps back in, muffled, under a riser.
        let breakdown = Asset(name: "Break", colorIndex: 7, content: .composition(Composition(length: 32, tracks: [
            track("Strings", 10, volume: -9, [clip(lushStrings, at: 0, length: 32)], effects: [clearLows, effect("reverb", ["mix": 0.35, "size": 0.85]), pump(0.35)]),
            track("Keys", 4, volume: -10, [clip(lushKeys, at: 0, length: 32)], effects: [clearLows, effect("chorus", ["depth": 0.35, "mix": 0.35]), pump(0.35)]),
            track("Oohs", 3, volume: -10, [clip(oohs, at: 0, length: 32)],
                  effects: [effect("eq", ["lowgain": -10, "lowfreq": 300]), effect("reverb", ["mix": 0.45, "size": 0.9])]),
            track("Vocal", 3, volume: -4, [clip(breakLine, at: 0, length: 8), clip(breakLine, at: 16, length: 8)], effects: voxFX),
            track("Take Me Away", 3, volume: -2, [clip(takeMeAway, at: 0, length: 32)],
                  effects: lineFX + [effect("reverb", ["mix": 0.35, "size": 0.9])]),
            track("Bass", 1, volume: -6, [clip(bassBreak, at: 16, length: 15)], effects: bassFX),
            track("Kick", 2, volume: -7, [clip(kickOnly, at: 16, length: 15)],
                  effects: drumsFX + [keyframed("filter", ["resonance": 0.1], "cutoff", [(16, 300), (31, 4000)])]),
            track("Riser", 9, volume: -12, [clip(riser, at: 16, length: 16)], effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ])))

        // Drop 2: the loop cut up and re-played, stutters and all, with the hook up an octave.
        let chopBar: [(Double, Double, Double)] = [
            (0, 2, 0), (2, 1, 0), (3, 1, 1),
            (4, 4, 4),
            (8, 1, 8), (9, 1, 8), (10, 0.5, 10), (10.5, 0.5, 10), (11, 1, 11),
            (12, 2, 12), (14, 0.5, 14), (14.5, 0.5, 14), (15, 0.25, 15), (15.25, 0.25, 15), (15.5, 0.25, 15), (15.75, 0.25, 15),
        ]
        let chopped = (0..<2).flatMap { k in chopBar.map { chop(at: Double(k) * 16 + $0.0, $0.1, from: $0.2) } }
        let drop2 = Asset(name: "Drop 2", colorIndex: 1, content: .composition(Composition(length: 32, tracks: [
            track("Drums", 2, [clip(beat, at: 0, length: 28), clip(fill, at: 28, length: 4)], effects: drumsFX),
            track("Tambourine", 3, volume: -6, [clip(tambourine, at: 0, length: 32)], effects: [room]),
            track("Shaker", 3, volume: -10, [clip(shaker, at: 0, length: 32)], effects: [room]),
            track("Bass", 1, volume: -1, [clip(bass, at: 0, length: 32)], effects: bassFX),
            track("Chopped Loop", 6, volume: -3, chopped, effects: [pump(0.55)]),
            track("Vocal Hook", 3, volume: -3, [clip(hookHigh, at: 0, length: 32)], effects: voxFX),
            track("Vocal Stabs", 3, volume: -8, [clip(vocalStabs, at: 0, length: 32)], effects: voxFX),
            track("Ad-Libs", 3, volume: -2, [clip(adLibs, at: 0, length: 32)], effects: lineFX + [pump(0.3)]),
        ])))

        // Outro: back through the wall.
        let outro = Asset(name: "Outro", colorIndex: 11, content: .composition(Composition(length: 16, tracks: [
            track("Disco Loop", 6, volume: -2, [clip(loop, at: 0, length: 16)], effects: filtered([(0, 6000), (8, 1200), (16, 250)], depth: 0.7)),
            track("Kick", 2, volume: -6, [clip(kickOnly, at: 0, length: 8)], effects: drumsFX + [effect("filter", ["cutoff": 900, "resonance": 0.1])]),
        ])))

        var main = Composition(length: 44 * bar)
        main.tracks = [
            track("Intro / Outro", 11, [clip(intro, at: 0, length: 32), clip(outro, at: 40 * bar, length: 16)]),
            track("Drops", 0, [clip(drop, at: 8 * bar, length: 64), clip(drop2, at: 32 * bar, length: 32)]),
            track("Break", 7, [clip(breakdown, at: 24 * bar, length: 32)]),
            track("Crash", 9, volume: -8, [8, 32].map { clip(crash, at: Double($0) * bar, length: 4) }, effects: [room]),
            track("FX", 3, volume: -8, [8, 32].map { clip(boom, at: Double($0) * bar, length: 4) }, effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ]
        // Less weight below than the reference, a little room cleared in the mud zone, a gentle lift on top.
        main.effects = [effect("eq", ["lowgain": -1.5, "lowfreq": 100, "midgain": -2, "midfreq": 320, "midq": 0.8, "highgain": 3, "highfreq": 4000]),
                        effect("compressor", ["threshold": -12, "ratio": 2, "attack": 30, "release": 200]),
                        effect("limiter", ["gain": 7, "ceiling": -1])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, drop, breakdown, drop2, outro, loop],
              patterns: [strings, guitar, keys, horns, bass, bassBreak, lushStrings, lushKeys],
              beats: [beat, fill, kickOnly, crash],
              fx: [radioID, dedication, chorus, adLibs, takeMeAway, hookHigh, vocalStabs, breakLine, oohs, shaker, tambourine, riser, boom])
        return p
    }
}
