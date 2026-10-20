import ShawCore

extension DemoProject {
    // MARK: - Sunroom

    /// "Sunroom": psychedelic indie rock in A major, 113 BPM, 40 bars (about 85 seconds), played
    /// almost entirely on recorded instruments: the Acoustic Kit, a bass guitar, four guitars, an
    /// FM electric piano, hand percussion, and a singer's "ooh" and "ah".
    /// Intro (8) · Verse (8) · Chorus (8) · Breakdown (4) · Last Chorus (8) · Outro (4)
    ///
    /// It opens like a sample: the loop muffled and wobbling as if from an old record, until the
    /// filter opens and the band is in the room. At the end it goes back into the record.
    static func sunroom() -> Project {
        var p = Project(name: "Sunroom", bpm: 113)
        let bar = 4.0
        let kit = "acoustic"

        // MARK: Harmony
        // Lush sevenths and ninths that never resolve all the way, with two chords borrowed from
        // outside the key: D minor 6 (the sigh at the end of every verse line) and F major 9 (the
        // surprise at the end of the chorus that pulls back home to A).
        struct Chord { let keys: [Int]; let root: Int }
        let amaj9 = Chord(keys: [56, 59, 61, 64], root: 33), fsm9 = Chord(keys: [57, 61, 64, 68], root: 30)
        let dmaj9 = Chord(keys: [54, 57, 61, 64], root: 38), dm6 = Chord(keys: [53, 57, 59, 62], root: 38)
        let csm7 = Chord(keys: [59, 61, 64, 68], root: 37), bm11 = Chord(keys: [57, 62, 64, 66], root: 35)
        let e6 = Chord(keys: [56, 59, 61, 66], root: 40), fmaj9 = Chord(keys: [57, 60, 64, 67], root: 41)
        let verse = [amaj9, fsm9, dmaj9, dm6]
        let chorus = [dmaj9, csm7, bm11, e6, dmaj9, csm7, fsm9, fmaj9]
        let breakdown = [dm6, fmaj9, dm6, e6]

        // A band, not a grid: everything a few milliseconds off and a little softer or harder.
        var seed: UInt64 = 0x7375_6e72_6f6f_6d21
        func rand() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53) * 2 - 1
        }
        func human(_ ns: [Note], time: Double, vel: Double, late: Double = 0) -> [Note] {
            ns.map { n in
                var n = n
                n.start = max(0, n.start + late + rand() * time)
                n.velocity = min(1, max(0.1, n.velocity + rand() * vel))
                return n
            }
        }
        func each(_ prog: [Chord], _ body: (Chord, Double) -> [Note]) -> [Note] {
            prog.enumerated().flatMap { body($0.element, Double($0.offset) * bar) }
        }

        // MARK: Keys
        // The FM piano comps on the "and" of 2, like a player leaning back: long, short, long.
        func comp(_ prog: [Chord], vel: Double = 0.6) -> [Note] {
            human(each(prog) { c, t in
                [(0.0, 1.3, vel), (1.5, 0.4, vel - 0.1), (2.5, 1.4, vel - 0.04)].flatMap { at, len, v in
                    c.keys.enumerated().map { i, k in Note(pitch: k, start: t + at + Double(i) * 0.012, length: len, velocity: v + Double(i) * 0.02) }
                }
            }, time: 0.008, vel: 0.04)
        }
        // The intro takes its time: each chord rolled once and left to ring for the bar.
        let keysIntro = synthPattern("Keys Intro", 4, "FM Piano", human(each(verse) { c, t in
            c.keys.enumerated().map { i, k in
                Note(pitch: k, start: t + Double(i) * 0.07, length: 3.85 - Double(i) * 0.07, velocity: 0.52 + Double(i) * 0.04)
            }
        }, time: 0.01, vel: 0.03))
        let keysVerse = synthPattern("Keys Verse", 4, "FM Piano", length: 32, comp(verse + verse))
        let keysChorus = synthPattern("Keys Chorus", 4, "FM Piano", length: 32, comp(chorus, vel: 0.66))
        let keysBreak = synthPattern("Keys Breakdown", 4, "FM Piano", human(each(breakdown) { c, t in
            c.keys.enumerated().map { i, k in Note(pitch: k, start: t + Double(i) * 0.06, length: 3.8 - Double(i) * 0.06, velocity: 0.55) }
        }, time: 0.01, vel: 0.03))
        let keysEnd = synthPattern("Last Chord", 4, "FM Piano", amaj9.keys.enumerated().map { i, k in
            Note(pitch: k, start: 8 + Double(i) * 0.08, length: 7.5, velocity: 0.55 + Double(i) * 0.03)
        } + comp([amaj9, amaj9]))

        // MARK: Bass
        // Fingered and busy: root, a ghost, the octave, and the fifth walking back down.
        func bassline(_ prog: [Chord], vel: Double = 0.85) -> [Note] {
            human(each(prog) { c, t in
                let r = c.root
                return [(0.0, r, 0.7, vel), (0.75, r, 0.2, vel - 0.3), (1.0, r + 12, 0.4, vel - 0.12), (1.5, r, 0.45, vel - 0.08),
                        (2.5, r, 0.4, vel - 0.05), (3.0, r + 7, 0.45, vel - 0.12), (3.5, r + 12, 0.4, vel - 0.15)]
                    .map { Note(pitch: $0.1, start: t + $0.0, length: $0.2, velocity: $0.3) }
            }, time: 0.01, vel: 0.04, late: 0.01)
        }
        let bassVerse = synthPattern("Bass Verse", 1, "Bass Guitar", length: 32, bassline(verse + verse))
        let bassChorus = synthPattern("Bass Chorus", 1, "Bass Guitar", length: 32, bassline(chorus, vel: 0.9))
        // In the breakdown the bass waits, then walks up into the last chorus.
        let bassBreak = synthPattern("Bass Breakdown", 1, "Bass Guitar", human([
            Note(pitch: 40, start: 12, length: 1.5, velocity: 0.8), Note(pitch: 40, start: 13.5, length: 0.5, velocity: 0.6),
            Note(pitch: 44, start: 14, length: 0.5, velocity: 0.7), Note(pitch: 47, start: 14.5, length: 0.5, velocity: 0.72),
            Note(pitch: 52, start: 15, length: 0.5, velocity: 0.75), Note(pitch: 47, start: 15.5, length: 0.5, velocity: 0.7),
        ], time: 0.01, vel: 0.03))
        let bassEnd = synthPattern("Bass Ending", 1, "Bass Guitar", bassline([amaj9, amaj9], vel: 0.75)
                                   + [Note(pitch: 33, start: 8, length: 6, velocity: 0.75)])

        // MARK: Guitars
        // Each chord voiced like a guitar: the root on a low string, the piano's shape above it,
        // and a chord tone an octave up for the top string, low enough to stay under the melody and
        // never a half step above another note of the chord.
        func shape(_ c: Chord) -> [Int] {
            let low = c.root + 12 >= 40 ? c.root + 12 : c.root + 24
            let top = c.keys.map { $0 + 12 }.first { t in !c.keys.contains { ($0 - t + 1) % 12 == 0 } } ?? c.keys[0] + 12
            return [low] + c.keys + [top]
        }
        // Jazz guitar: picked eighths through the chord, ringing into each other.
        func picked(_ prog: [Chord]) -> [Note] {
            human(each(prog) { c, t in
                let s = shape(c)
                return [0, 2, 3, 4, 5, 4, 3, 2].enumerated().map { i, k in
                    Note(pitch: s[k], start: t + Double(i) * 0.5, length: min(0.95, 4 - Double(i) * 0.5), velocity: i % 2 == 0 ? 0.66 : 0.52)
                }
            }, time: 0.01, vel: 0.05)
        }
        // Clean electric: short, choked stabs on the off-beats, the disco chop under the chorus.
        func chops(_ prog: [Chord]) -> [Note] {
            human(each(prog) { c, t in
                [0.5, 1.5, 2.5, 3.5].flatMap { at in
                    shape(c).suffix(4).enumerated().map { i, k in
                        Note(pitch: k, start: t + at + Double(i) * 0.01, length: 0.16, velocity: 0.7 - Double(i) * 0.03)
                    }
                }
            }, time: 0.006, vel: 0.05)
        }
        // Jangle guitar: down-up strums in the last chorus.
        func strummed(_ prog: [Chord]) -> [Note] {
            human(each(prog) { c, t in
                (0..<8).flatMap { e -> [Note] in
                    let down = e % 2 == 0
                    let strings = down ? shape(c) : Array(shape(c).reversed().prefix(4))
                    return strings.enumerated().map { i, k in
                        Note(pitch: k, start: t + Double(e) * 0.5 + Double(i) * 0.018, length: 0.46, velocity: (down ? 0.66 : 0.48) - Double(i) * 0.02)
                    }
                }
            }, time: 0.005, vel: 0.04)
        }
        let pickedVerse = synthPattern("Picked Guitar", 7, "Jazz Guitar", length: 32, picked(verse + verse))
        let chopsChorus = synthPattern("Guitar Chops", 7, "Clean Electric Guitar", length: 32, chops(chorus))
        let strumChorus = synthPattern("Strummed Guitar", 7, "Jangle Guitar", length: 32, strummed(chorus))
        // The breakdown's melody: a long note a chord, swelling in like a volume pedal, stepping
        // down A, G, F, E, each answered by two quick notes, then lifting to G♯ for the last chorus.
        let swells = synthPattern("Guitar Swells", 7, "Hollow-Body Guitar", tweak: ["a": 0.3, "r": 0.8], human(notes([
            (81, 0, 2.5), (77, 3, 0.5), (76, 3.5, 0.5),
            (79, 4, 2.5), (76, 7, 0.5), (74, 7.5, 0.5),
            (77, 8, 2.5), (76, 11, 0.5), (74, 11.5, 0.5),
            (76, 12, 1.5), (78, 13.5, 0.5), (80, 14, 2),
        ], vel: 0.72), time: 0.01, vel: 0.03))

        // MARK: The melody
        // The guitar sings the song: lazy, a little behind the beat, almost all on the five notes
        // that fit every chord here (B, C♯, E, F♯, G♯). The verse ends each line on the D minor sigh
        // (F to E to D), and the chorus reaches up to A, then lands on C, the borrowed note.
        let verseLine: [(Int, Double, Double)] = [
            (73, 0.5, 0.5), (71, 1, 0.5), (68, 1.5, 1), (66, 2.5, 0.5), (68, 3, 0.5), (71, 3.5, 1),
            (73, 4.5, 0.5), (76, 5, 1.5), (73, 6.5, 0.5), (71, 7, 1),
            (69, 8, 0.5), (71, 8.5, 0.5), (73, 9, 1), (71, 10, 0.5), (69, 10.5, 1), (66, 11.5, 0.5),
            (65, 12, 1.5), (64, 13.5, 0.5), (62, 14, 1.5),
            (73, 16.5, 0.5), (71, 17, 0.5), (68, 17.5, 1), (66, 18.5, 0.5), (68, 19, 0.5), (71, 19.5, 1),
            (73, 20.5, 0.5), (76, 21, 1), (78, 22, 1), (80, 23, 1),
            (78, 24, 1.5), (76, 25.5, 0.5), (73, 26, 1), (69, 27, 1),
            (71, 28, 1), (69, 29, 1), (65, 30, 1), (64, 31, 1),
        ]
        let chorusLine: [(Int, Double, Double)] = [
            (76, 0, 1.5), (78, 1.5, 0.5), (76, 2, 1), (73, 3, 1),
            (73, 4, 1.5), (71, 5.5, 0.5), (68, 6, 2),
            (69, 8, 0.5), (71, 8.5, 0.5), (73, 9, 0.5), (76, 9.5, 1.5), (73, 11, 1),
            (71, 12, 1.5), (68, 13.5, 0.5), (66, 14, 2),
            (76, 16, 1.5), (78, 17.5, 0.5), (81, 18, 1), (80, 19, 1),
            (76, 20, 1.5), (73, 21.5, 0.5), (78, 22, 2),
            (80, 24, 1), (78, 25, 0.5), (76, 25.5, 1), (73, 26.5, 1.5),
            (72, 28, 1), (74, 29, 1), (76, 30, 2),
        ]
        // Double-tracked: two takes of the same line, panned apart, never quite together.
        func take(_ line: [(Int, Double, Double)], _ vel: Double) -> [Note] {
            human(notes(line, vel: vel).map { var n = $0; n.velocity += n.length >= 1 ? 0.05 : 0; return n }, time: 0.012, vel: 0.05, late: 0.02)
        }
        let leadVerseL = synthPattern("Lead Verse", 5, "Hollow-Body Guitar", length: 32, take(verseLine, 0.75))
        let leadVerseR = synthPattern("Lead Verse (Double)", 5, "Hollow-Body Guitar", length: 32, take(verseLine, 0.72))
        let leadChorusL = synthPattern("Lead Chorus", 5, "Hollow-Body Guitar", length: 32, take(chorusLine, 0.8))
        let leadChorusR = synthPattern("Lead Chorus (Double)", 5, "Hollow-Body Guitar", length: 32, take(chorusLine, 0.77))
        // The last chorus adds the jangle an octave up, quietly, like a harmony you feel more than hear.
        let leadHigh = synthPattern("Lead Octave", 5, "Jangle Guitar", length: 32, take(chorusLine.map { ($0.0 + 12, $0.1, $0.2) }, 0.6))
        let leadEnd = synthPattern("Lead Ending", 5, "Hollow-Body Guitar", take([(73, 0.5, 0.5), (71, 1, 0.5), (68, 1.5, 1), (66, 2.5, 0.5), (68, 3, 0.5),
                                                                                 (71, 3.5, 1), (73, 4.5, 0.5), (68, 5, 3)], 0.7))

        // MARK: Voices
        // The "sample": a singer's "ah" chopped into a little riff that answers itself, the hook of
        // the intro and the breakdown.
        func chopped(_ list: [(Int, Double, Double)]) -> [Note] {
            human(list.map { Note(pitch: $0.0, start: $0.1, length: $0.2, velocity: $0.2 > 0.5 ? 0.8 : 0.68) }, time: 0.004, vel: 0.03)
        }
        let riff = synthPattern("Vocal Riff", 3, "Vocal Chops", chopped([
            (76, 0.5, 0.4), (73, 1, 0.4), (71, 1.75, 0.9),
            (73, 4.5, 0.4), (76, 5, 0.4), (80, 5.75, 0.9),
            (78, 8.5, 0.4), (76, 9, 0.4), (73, 9.75, 0.9),
            (74, 12.5, 0.4), (76, 13, 0.4), (77, 13.75, 1.4),
        ]))
        // The "ooh" sings the top of each chord behind the chorus, like backing vocals.
        func oohs(_ prog: [Chord]) -> [Note] {
            each(prog) { c, t in c.keys.suffix(3).map { Note(pitch: $0, start: t, length: 3.9, velocity: 0.68) } }
        }
        let oohChorus = synthPattern("Oohs", 3, "Ooh Pad", length: 32, oohs(chorus))
        let oohBreak = synthPattern("Oohs (Breakdown)", 3, "Ooh Pad", oohs(breakdown))
        let oohEnd = synthPattern("Ooh Ending", 3, "Ooh Pad", oohs([amaj9, amaj9]).filter { $0.start < 4 }
                                  + amaj9.keys.suffix(3).map { Note(pitch: $0, start: 4, length: 11.5, velocity: 0.66) })

        // MARK: Drums
        // A disco-rock pocket like the reference: kick on every beat, snare on 2 and 4, closed hats
        // on the eighths, a ghost snare before 4, and the hat opening on the last "and".
        func pocket(_ o: Double, open: Bool) -> [(String, Double, Double)] {
            var h: [(String, Double, Double)] = []
            for b in 0..<4 {
                let t = o + Double(b)
                h.append(("kick", t, b == 0 ? 0.92 : 0.82))
                if b % 2 == 1 { h.append(("snare", t, 0.88)) }
                if open { h += [("chat", t, 0.38), ("ohat", t + 0.5, b == 3 ? 0.55 : 0.42)] }
                else { h += [("chat", t, 0.5), (b == 3 ? "ohat" : "chat", t + 0.5, b == 3 ? 0.45 : 0.34)] }
            }
            return h + [("snare", o + 2.75, 0.22)]
        }
        func humanHits(_ hits: [(String, Double, Double)]) -> [(String, Double, Double)] {
            hits.map { ($0.0, max(0, $0.1 + rand() * 0.006), min(1, max(0.1, $0.2 + rand() * 0.05))) }
        }
        // Just a soft kick and hats, for the intro.
        let softBeat = kitPattern("Kick and Hats", 2, kit, length: 4, humanHits(pocket(0, open: false)
            .filter { $0.0 != "snare" }.map { ($0.0, $0.1, $0.2 * 0.75) }))
        let verseBeat = kitPattern("Verse Beat", 2, kit, length: 16, humanHits((0..<4).flatMap { pocket(Double($0) * 4, open: false) }))
        // The chorus opens the hats on every off-beat: the disco lift.
        let chorusBeat = kitPattern("Chorus Beat", 2, kit, length: 16, humanHits((0..<4).flatMap { pocket(Double($0) * 4, open: true) }))
        let fill = kitPattern("Fill", 8, kit, length: 4, humanHits(pocket(0, open: false).filter { $0.1 < 2 }
            + [("snare", 2, 0.7), ("snare", 2.5, 0.6), ("tomhi", 2.75, 0.7), ("tomhi", 3, 0.75), ("tomlo", 3.25, 0.8), ("tomlo", 3.5, 0.85), ("kick", 3.5, 0.7), ("tomlo", 3.75, 0.9)]))
        let breakFill = kitPattern("Breakdown Fill", 8, kit, length: 4, humanHits(
            (0..<8).map { ("snare", 2 + Double($0) * 0.25, 0.3 + Double($0) * 0.08) } + [("kick", 0, 0.8), ("kick", 1, 0.7)]))
        // Under the breakdown: a muffled kick on every beat, so the pulse never stops.
        let pulse = kitPattern("Pulse", 2, kit, length: 4, humanHits((0..<4).map { ("kick", Double($0), 0.75) }))
        let crash = kitPattern("Crash", 9, kit, length: 4, [("crash", 0, 0.55)])

        // Hand percussion from the Percussion folder, played by the sampler.
        func hits(_ name: String, _ file: String, length: Double = 4, gain: Double = 0, _ times: [(Double, Double)]) -> Asset {
            var inst = Instrument.sampler(SampleLibrary.bundledPrefix + "Percussion/\(file).caf")
            inst.params["volume"] = gain
            return Asset(name: name, colorIndex: 3, content: .notes(NotePattern(length: length,
                notes: times.map { Note(pitch: 60, start: max(0, $0.0 + rand() * 0.006), length: 0.25, velocity: $0.1) }, instrument: inst)))
        }
        let shaker = hits("Shaker", "Shaker", gain: -8, (0..<16).map { (Double($0) * 0.25, $0 % 2 == 0 ? 0.5 : 0.36) })
        let tambourine = hits("Tambourine", "Tambourine", gain: -6, (0..<8).map { (Double($0) * 0.5, $0 % 2 == 1 ? 0.7 : 0.4) })
        // Congas carry the breakdown while the kit sits out.
        let congaHigh = hits("Congas", "Conga Open", gain: -4, [(0, 0.75), (1.5, 0.6), (2.5, 0.65), (3.5, 0.5)])
        let congaLow = hits("Congas (Muted)", "Conga Muted", gain: -5, [(0.75, 0.5), (1, 0.6), (2, 0.55), (3, 0.6), (3.25, 0.45)])

        // MARK: Effects
        // The wobble: a chorus with nothing dry left in it bends the pitch slowly, like warped tape.
        let wobble = effect("chorus", ["rate": 0.45, "depth": 0.35, "delay": 7, "mix": 0.55])
        let room = effect("reverb", ["mix": 0.16, "size": 0.45])
        let hall = effect("reverb", ["mix": 0.3, "size": 0.8, "predelay": 20])
        let drumsFX = [effect("eq", ["lowgain": 5, "lowfreq": 65, "midgain": -3, "midfreq": 450, "midq": 0.8, "highgain": 2, "highfreq": 8000]),
                       effect("saturator", ["drive": 5, "type": 2, "mix": 0.35]),
                       effect("compressor", ["threshold": -16, "ratio": 3, "attack": 15, "release": 120]), room]
        // Round and warm: less finger click and boxiness, a little tube grit to fill it out.
        let bassFX = [effect("eq", ["lowgain": 5, "lowfreq": 80, "midgain": -3, "midfreq": 280, "midq": 1, "highgain": -3, "highfreq": 2500]),
                      effect("saturator", ["drive": 6, "type": 2, "tone": 3500, "mix": 0.45]),
                      effect("compressor", ["threshold": -18, "ratio": 4, "attack": 10, "release": 100])]
        let keysFX = [effect("eq", ["lowgain": -4, "lowfreq": 200]), wobble, effect("phaser", ["rate": 0.12, "depth": 0.5, "mix": 0.25]), hall]
        let guitarEQ = effect("eq", ["lowgain": -8, "lowfreq": 280, "highgain": 3, "highfreq": 5000])
        let leadFX = [guitarEQ, effect("chorus", ["rate": 0.6, "depth": 0.25, "mix": 0.25]),
                      effect("delay", ["time": 6, "feedback": 0.32, "mix": 0.17]), effect("reverb", ["mix": 0.28, "size": 0.75, "predelay": 25])]
        let voxFX = [effect("eq", ["lowgain": -10, "lowfreq": 350, "highgain": 2, "highfreq": 7000]),
                     effect("delay", ["time": 6, "feedback": 0.35, "pingpong": 1, "mix": 0.22]), effect("reverb", ["mix": 0.35, "size": 0.85])]
        let oohFX = [effect("eq", ["lowgain": -10, "lowfreq": 300]), effect("chorus", ["depth": 0.4, "mix": 0.4]), effect("utility", ["width": 1.4]),
                     effect("reverb", ["mix": 0.45, "size": 0.9])]
        // Like a record: only the middle of the sound gets through (a high-pass and a low-pass
        // together), in mono, a little crushed, and warbling. Opening both filters and the stereo
        // width is what turns it into the band in the room.
        func record(lows: [(Double, Double)], highs: [(Double, Double)], width: [(Double, Double)]) -> [Effect] {
            [effect("bitcrusher", ["bits": 11, "downsample": 2, "mix": 0.3]),
             effect("chorus", ["rate": 0.35, "depth": 0.3, "delay": 6, "mix": 0.5]),
             keyframed("filter", ["type": 1, "resonance": 0.1], "cutoff", lows),
             keyframed("filter", ["resonance": 0.15], "cutoff", highs),
             keyframed("utility", [:], "width", width)]
        }

        // A pump that starts at nothing on each chord and grows as it rings, peaking a little higher every bar.
        func swelling(bars: Int, from: Double, by: Double) -> Effect {
            keyframed("pump", ["rate": 2, "release": 0.6], "depth", (0..<bars).flatMap { b -> [(Double, Double)] in
                [(Double(b) * 4, 0), (Double(b) * 4 + 3.95, from + Double(b) * by)]
            })
        }

        // MARK: Sections
        // It fades in: the keys alone, then a shaker, then her voice, then a soft kick and hats,
        // until the filter opens and the band arrives on the verse.
        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            // The held chords duck on every beat and swell back, so they pulse like the kick is already
            // there. Each chord starts smooth and pumps harder as it rings, a little harder every bar.
            track("Keys", 4, volume: -2, [clip(keysIntro, at: 0, length: 32)],
                  effects: keysFX + [swelling(bars: 8, from: 0.45, by: 0.06)]),
            track("Shaker", 3, volume: -9, [clip(shaker, at: 8, length: 24)], effects: [room]),
            track("Vocal Riff", 3, volume: -4, [clip(riff, at: 16, length: 16)], effects: voxFX),
            track("Drums", 2, volume: -7, [clip(softBeat, at: 24, length: 8)], effects: drumsFX),
        ], effects: record(lows: [(0, 450), (24, 350), (31.5, 120), (32, 20)], highs: [(0, 700), (16, 1000), (28, 1500), (31.5, 5000), (32, 20000)],
                            width: [(0, 0), (28, 0.2), (31.5, 0.6), (32, 1)])
            + [keyframed("volume", [:], "volume", [(0, -4), (8, -3), (16, -1.5), (24, 0)])])))

        let verseComp = Asset(name: "Verse", colorIndex: 2, content: .composition(Composition(length: 32, tracks: [
            track("Drums", 2, volume: -4, [clip(verseBeat, at: 0, length: 28), clip(fill, at: 28, length: 4)], effects: drumsFX),
            track("Shaker", 3, volume: -6, [clip(shaker, at: 0, length: 32)], effects: [room]),
            track("Bass", 1, volume: 0, [clip(bassVerse, at: 0, length: 32)], effects: bassFX),
            track("Keys", 4, volume: -9, [clip(keysVerse, at: 0, length: 32)], effects: keysFX),
            track("Picked Guitar", 7, volume: -13, pan: 0.35, [clip(pickedVerse, at: 0, length: 32)], effects: [guitarEQ, hall]),
            track("Lead", 5, volume: -8, pan: -0.6, [clip(leadVerseL, at: 0, length: 32)], effects: leadFX),
            track("Lead (Double)", 5, volume: -8, pan: 0.6, [clip(leadVerseR, at: 0, length: 32)], effects: leadFX),
        ])))

        func chorusComp(_ name: String, _ color: Int, last: Bool) -> Asset {
            var tracks = [
                track("Drums", 2, volume: -3, [clip(chorusBeat, at: 0, length: 28), clip(fill, at: 28, length: 4)], effects: drumsFX),
                track("Tambourine", 3, volume: -5, [clip(tambourine, at: 0, length: 32)], effects: [room]),
                track("Bass", 1, volume: 1, [clip(bassChorus, at: 0, length: 32)], effects: bassFX),
                track("Keys", 4, volume: -10, [clip(keysChorus, at: 0, length: 32)], effects: keysFX),
                track("Guitar Chops", 7, volume: -14, pan: -0.4, [clip(chopsChorus, at: 0, length: 32)],
                      effects: [guitarEQ, effect("phaser", ["rate": 0.25, "depth": 0.6, "mix": 0.4]), room]),
                track("Oohs", 3, volume: -11, [clip(oohChorus, at: 0, length: 32)], effects: oohFX),
                track("Lead", 5, volume: -7, pan: -0.6, [clip(leadChorusL, at: 0, length: 32)], effects: leadFX),
                track("Lead (Double)", 5, volume: -7, pan: 0.6, [clip(leadChorusR, at: 0, length: 32)], effects: leadFX),
            ]
            if last {
                tracks += [
                    track("Strummed Guitar", 7, volume: -14, pan: 0.45, [clip(strumChorus, at: 0, length: 32)], effects: [guitarEQ, room]),
                    track("Lead Octave", 5, volume: -16, [clip(leadHigh, at: 0, length: 32)], effects: leadFX),
                ]
            }
            return Asset(name: name, colorIndex: color, content: .composition(Composition(length: 32, tracks: tracks)))
        }
        let chorus1 = chorusComp("Chorus", 0, last: false)
        let chorus2 = chorusComp("Last Chorus", 1, last: true)

        // The floor drops out to a muffled kick and congas, phased keys and oohs pumping under one guitar line.
        let breakComp = Asset(name: "Breakdown", colorIndex: 10, content: .composition(Composition(length: 16, tracks: [
            track("Congas", 3, volume: -6, pan: -0.3, [clip(congaHigh, at: 0, length: 16)], effects: [room]),
            track("Congas (Muted)", 3, volume: -6, pan: 0.3, [clip(congaLow, at: 0, length: 16)], effects: [room]),
            track("Drums", 2, volume: -6, [clip(breakFill, at: 12, length: 4)], effects: drumsFX),
            track("Kick", 2, volume: -9, [clip(pulse, at: 0, length: 12)],
                  effects: drumsFX + [effect("filter", ["cutoff": 400, "resonance": 0.1])]),
            track("Keys", 4, volume: -7, [clip(keysBreak, at: 0, length: 16)],
                  effects: keysFX + [effect("phaser", ["rate": 0.15, "depth": 0.5, "feedback": 0.3, "mix": 0.35]),
                                     swelling(bars: 4, from: 0.55, by: 0.1)]),
            track("Oohs", 3, volume: -9, [clip(oohBreak, at: 0, length: 16)], effects: oohFX + [swelling(bars: 4, from: 0.4, by: 0.1)]),
            track("Guitar Swells", 7, volume: -8, [clip(swells, at: 0, length: 16)],
                  effects: [guitarEQ, effect("chorus", ["rate": 0.6, "depth": 0.25, "mix": 0.25]),
                            effect("delay", ["time": 8, "feedback": 0.2, "pingpong": 1, "mix": 0.18]), hall]),
            track("Bass", 1, volume: -3, [clip(bassBreak, at: 0, length: 16)], effects: bassFX),
        // It sits well under the choruses, then swells back over its last bar so the last chorus lands.
        ], effects: [effect("utility", ["width": 1.35]), keyframed("volume", [:], "volume", [(0, -6), (13, -6), (16, -1)])])))

        // Back into the record: the band plays the verse's first line once more as the filter closes.
        let outro = Asset(name: "Outro", colorIndex: 11, content: .composition(Composition(length: 16, tracks: [
            track("Drums", 2, volume: -5, [clip(verseBeat, at: 0, length: 8)], effects: drumsFX),
            track("Keys", 4, volume: -7, [clip(keysEnd, at: 0, length: 16)], effects: keysFX),
            track("Bass", 1, volume: -4, [clip(bassEnd, at: 0, length: 16)], effects: bassFX),
            track("Lead", 5, volume: -8, pan: -0.3, [clip(leadEnd, at: 0, length: 16)], effects: leadFX),
            track("Vocal Riff", 3, volume: -5, [clip(riff, at: 0, length: 8)], effects: voxFX),
            track("Oohs", 3, volume: -11, [clip(oohEnd, at: 0, length: 16)], effects: oohFX),
        ], effects: record(lows: [(0, 20), (4, 80), (10, 250), (16, 400)], highs: [(0, 20000), (4, 6000), (10, 1500), (16, 700)],
                            width: [(0, 1), (6, 0.6), (12, 0.1), (16, 0)]))))

        var main = Composition(length: 40 * bar)
        main.tracks = [
            track("Intro", 11, [clip(intro, at: 0, length: 32)]),
            track("Verse", 2, [clip(verseComp, at: 8 * bar, length: 32)]),
            track("Chorus", 0, [clip(chorus1, at: 16 * bar, length: 32), clip(chorus2, at: 28 * bar, length: 32)]),
            track("Breakdown", 10, [clip(breakComp, at: 24 * bar, length: 16)]),
            track("Outro", 11, [clip(outro, at: 36 * bar, length: 16)]),
            track("Crash", 9, volume: -8, [16, 28].map { clip(crash, at: Double($0) * bar, length: 4) }, effects: [room]),
        ]
        // Warm and dark like a record, glued, and loud enough to sit next to the reference.
        main.effects = [effect("eq", ["lowgain": 3, "lowfreq": 90, "midgain": -3, "midfreq": 700, "midq": 0.7, "highgain": 4.5, "highfreq": 4500]),
                        effect("compressor", ["threshold": -12, "ratio": 2, "attack": 30, "release": 200]),
                        effect("limiter", ["gain": 10, "ceiling": -1])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, verseComp, chorus1, breakComp, chorus2, outro],
              patterns: [keysIntro, keysVerse, keysChorus, keysBreak, keysEnd, bassVerse, bassChorus, bassBreak, bassEnd,
                         pickedVerse, chopsChorus, strumChorus, swells, leadVerseL, leadVerseR, leadChorusL, leadChorusR, leadHigh, leadEnd],
              beats: [softBeat, pulse, verseBeat, chorusBeat, fill, breakFill, crash],
              fx: [riff, oohChorus, oohBreak, oohEnd, shaker, tambourine, congaHigh, congaLow])
        return p
    }
}
