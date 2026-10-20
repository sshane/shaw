import ShawCore

extension DemoProject {
    // MARK: - Postcards

    /// "Postcards": D major indie pop, 120 BPM, 38 bars (about 76 seconds), played on the real
    /// instruments: an upright piano, the Acoustic Kit, vibraphone, kalimba, glockenspiel, harp,
    /// pipe organ, a jangly electric guitar, a tenor sax hook, and a bass guitar.
    /// Intro (4) · Verse (8) · Pre-Chorus (4) · Chorus (8) · Bridge (4) · Last Chorus (8) · Outro (2)
    static func postcards() -> Project {
        var p = Project(name: "Postcards", bpm: 120)
        let bar = 4.0
        let kit = "acoustic"

        // Chords, voiced on the upright so no two notes sit a half step apart.
        let D = [50, 57, 62, 66], A = [45, 52, 57, 61, 64], Bm = [47, 54, 59, 62, 66], G = [43, 50, 55, 59, 62]
        let Em = [40, 52, 59, 64, 67]
        let roots: [[Int]: Int] = [D: 38, A: 33, Bm: 35, G: 31, Em: 40]
        let verse = [Bm, G, D, A], pre = [G, A, Bm, A], chorus = [D, A, Bm, G], bridge = [Em, G, D, A]

        func chords(_ prog: [[Int]], _ rhythm: [(Double, Double, Double)]) -> [Note] {
            var n: [Note] = []
            for (b, chord) in prog.enumerated() {
                for (t, len, vel) in rhythm { n += chord.map { Note(pitch: $0, start: Double(b) * bar + t, length: len, velocity: vel) } }
            }
            return n
        }
        func bass(_ prog: [[Int]], _ rhythm: [(Double, Double, Double)]) -> [Note] {
            var n: [Note] = []
            for (b, chord) in prog.enumerated() {
                let r = roots[chord] ?? 38
                for (t, len, vel) in rhythm { n.append(Note(pitch: r, start: Double(b) * bar + t, length: len, velocity: vel)) }
            }
            return n
        }
        /// One chord tone after another (`tones` index into the chord, high voices first).
        func arp(_ prog: [[Int]], up: Int, step: Double, _ tones: [Int], vel: Double) -> [Note] {
            var n: [Note] = []
            for (b, chord) in prog.enumerated() {
                let top = Array(chord.suffix(3)).map { $0 + up }
                for (i, k) in tones.enumerated() {
                    // Rings a little past the next note, but never into the next chord.
                    let at = Double(i) * step
                    n.append(Note(pitch: top[k % top.count] + (k / top.count) * 12, start: Double(b) * bar + at,
                                  length: min(step * 1.5, bar - at), velocity: vel - (i % 2 == 0 ? 0 : 0.12)))
                }
            }
            return n
        }

        // Upright piano: soft half notes in the verse, pushing eighths into and through the chorus.
        let pianoVerse = synthPattern("Piano Verse", 6, "Upright Piano", gain: 0, chords(verse, [(0, 1.9, 0.62), (2, 1.9, 0.52)]))
        let eighths = (0..<8).map { (Double($0) * 0.5, 0.45, $0 % 2 == 0 ? 0.78 : 0.6) }
        // Driving eighths leave the root to the bass, so the low end stays clear.
        func upper(_ prog: [[Int]]) -> [[Int]] { prog.map { Array($0.dropFirst()) } }
        let pianoPre = synthPattern("Piano Build", 6, "Upright Piano", chords(upper(pre), eighths))
        let pianoChorus = synthPattern("Piano Chorus", 6, "Upright Piano", chords(upper(chorus), eighths))
        let pianoIntro = synthPattern("Piano Intro", 6, "Upright Piano", chords(chorus, [(0, 3.9, 0.55)]))
        let pianoBridge = synthPattern("Piano Bridge", 6, "Upright Piano", chords(bridge, [(0, 3.9, 0.5)]))
        let pianoEnd = synthPattern("Last Chord", 6, "Upright Piano", length: 8, chords([D], [(0, 7.5, 0.7)]))

        // Bass guitar: holding back in the verse, driving eighths in the chorus.
        let bassVerse = synthPattern("Bass Verse", 1, "Bass Guitar", gain: -1, bass(verse, [(0, 1.4, 0.8), (1.5, 0.45, 0.6), (2.5, 1.4, 0.7)]))
        let bassPre = synthPattern("Bass Build", 1, "Bass Guitar", gain: -1, bass(pre, (0..<8).map { (Double($0) * 0.5, 0.42, 0.72) }))
        let bassChorus = synthPattern("Bass Chorus", 1, "Bass Guitar", gain: 0,
                                      bass(chorus, (0..<8).map { (Double($0) * 0.5, 0.42, $0 % 2 == 0 ? 0.88 : 0.68) }))
        let bassBridge = synthPattern("Bass Bridge", 1, "Bass Guitar", gain: -2, bass(bridge, [(0, 3.5, 0.75)]))

        // Kalimba in the intro and bridge, vibraphone answering the piano in the verse.
        let kalimba = synthPattern("Kalimba", 4, "Kenyan Kalimba", arp(chorus, up: 12, step: 0.5, [2, 1, 0, 1, 2, 3, 2, 1], vel: 0.75))
        let kalimbaBridge = synthPattern("Kalimba Bridge", 4, "Kenyan Kalimba", arp(bridge, up: 12, step: 0.5, [0, 1, 2, 3, 2, 1, 0, 1], vel: 0.7))
        let vibes = synthPattern("Vibes", 9, "Vibraphone", gain: -2, arp(verse, up: 12, step: 1, [0, 1, 2, 1], vel: 0.65))
        let harp = synthPattern("Harp", 10, "Harp", gain: 2, arp(bridge, up: 0, step: 0.25,
                                                                [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5], vel: 0.7))

        // Jangle guitar: picked chord tones in the verse, strummed eighths in the chorus. Same chords
        // as the piano, voiced like a guitar; each strum's strings a few milliseconds apart.
        let shapes: [[Int]: [Int]] = [D: [50, 57, 62, 66], A: [45, 52, 57, 61, 64], Bm: [47, 54, 59, 62, 66],
                                      G: [43, 47, 50, 55, 59, 67], Em: [40, 47, 52, 55, 59, 64]]
        func picked(_ prog: [[Int]]) -> [Note] {
            var n: [Note] = []
            for (b, chord) in prog.enumerated() {
                let s = shapes[chord] ?? chord
                for (i, k) in [0, 2, 1, 3, 2, 4, 3, 2].enumerated() {
                    let at = Double(i) * 0.5
                    n.append(Note(pitch: s[min(k, s.count - 1)], start: Double(b) * bar + at, length: min(0.9, bar - at),
                                  velocity: i % 2 == 0 ? 0.7 : 0.55))
                }
            }
            return n
        }
        func strummed(_ prog: [[Int]]) -> [Note] {
            var n: [Note] = []
            for (b, chord) in prog.enumerated() {
                let s = shapes[chord] ?? chord
                for e in 0..<8 {
                    let down = e % 2 == 0
                    let strings = down ? s : Array(s.reversed().prefix(4))
                    for (i, pitch) in strings.enumerated() {
                        let at = Double(e) * 0.5 + Double(i) * 0.02
                        n.append(Note(pitch: pitch, start: Double(b) * bar + at, length: min(0.46, bar - at),
                                      velocity: (down ? 0.75 : 0.55) - Double(i) * 0.02))
                    }
                }
            }
            return n
        }
        let guitarVerse = synthPattern("Guitar Verse", 7, "Jangle Guitar", picked(verse))
        let guitarChorus = synthPattern("Guitar Chorus", 7, "Jangle Guitar", strummed(chorus))

        // Pipe organ over the build and the chorus: the top of each chord an octave up, held, above the piano.
        func organ(_ prog: [[Int]]) -> [Note] { chords(prog.map { $0.suffix(3).map { $0 + 12 } }, [(0, 3.95, 0.6)]) }
        let organPre = synthPattern("Organ Build", 8, "Pipe Organ", gain: -4, organ(pre))
        let organChorus = synthPattern("Organ", 8, "Pipe Organ", gain: -5, organ(chorus))

        // The hook: tenor sax, with the glockenspiel two octaves up on the big notes.
        let hook: [(Int, Double, Double)] = [
            (66, 0, 1), (69, 1, 1), (74, 2, 1.5), (71, 3.5, 0.5),
            (69, 4, 2), (64, 6, 1), (66, 7, 1),
            (66, 8, 1), (74, 9, 1), (71, 10, 1.5), (69, 11.5, 0.5),
            (67, 12, 1), (71, 13, 1), (74, 14, 2),
        ]
        let sax = synthPattern("Sax Hook", 5, "Tenor Sax", gain: 1, notes(hook, vel: 0.85))
        let saxHarmony = synthPattern("Sax Harmony", 5, "Tenor Sax", gain: -3, notes([
            (62, 0, 1), (66, 1, 1), (69, 2, 1.5), (66, 3.5, 0.5),
            (64, 4, 2), (61, 6, 1), (61, 7, 1),
            (62, 8, 1), (71, 9, 1), (66, 10, 1.5), (66, 11.5, 0.5),
            (62, 12, 1), (67, 13, 1), (71, 14, 2),
        ], vel: 0.7))
        let glock = synthPattern("Glock", 11, "Glockenspiel", gain: 0, notes(hook.filter { $0.2 >= 1 }.map { ($0.0 + 24, $0.1, 0.5) }, vel: 0.7))

        // Hand percussion from the Percussion folder, played by the sampler.
        func hits(_ name: String, _ color: Int, _ file: String, length: Double = 4, gain: Double = 0, _ times: [(Double, Double)]) -> Asset {
            var inst = Instrument.sampler(SampleLibrary.bundledPrefix + "Percussion/\(file).caf")
            inst.params["volume"] = gain
            let n = times.map { Note(pitch: 60, start: $0.0, length: 0.25, velocity: $0.1) }
            return Asset(name: name, colorIndex: color, content: .notes(NotePattern(length: length, notes: n, instrument: inst)))
        }
        let shaker = hits("Shaker", 3, "Shaker", gain: -8, (0..<16).map { (Double($0) * 0.25, $0 % 2 == 0 ? 0.55 : 0.4) })
        let tambourine = hits("Tambourine", 3, "Tambourine", gain: -6, [(1, 0.8), (1.5, 0.45), (3, 0.8), (3.5, 0.45)])

        // Drums: the Acoustic Kit.
        let hats8 = (0..<8).map { ("chat", Double($0) * 0.5, $0 % 2 == 0 ? 0.55 : 0.35) }
        let verseBeat = kitPattern("Verse Beat", 2, kit, length: 4, [("kick", 0, 0.85), ("kick", 2.5, 0.7), ("rim", 1, 0.7), ("rim", 3, 0.7)] + hats8)
        let chorusBeat = kitPattern("Chorus Beat", 2, kit, length: 4, [
            ("kick", 0, 0.95), ("kick", 1.5, 0.7), ("kick", 2, 0.9), ("kick", 2.5, 0.7),
            ("snare", 1, 0.95), ("snare", 3, 0.95), ("ohat", 3.5, 0.5),
        ] + (0..<7).map { ("chat", Double($0) * 0.5, $0 % 2 == 0 ? 0.7 : 0.45) })
        let buildBeat = kitPattern("Build", 7, kit, length: 16, [("kick", 0, 0.85), ("kick", 4, 0.85), ("kick", 8, 0.85), ("kick", 10, 0.8)]
            + [1.0, 3, 5, 7, 9, 11].map { ("snare", $0, 0.75) }
            + (0..<8).map { ("snare", 12 + Double($0) * 0.5, 0.45 + Double($0) * 0.06) }
            + [("tomhi", 14, 0.8), ("tomhi", 14.5, 0.8), ("tomlo", 15, 0.85), ("tomlo", 15.5, 0.9)])
        let fill = kitPattern("Fill", 7, kit, length: 4, [("tomhi", 2, 0.7), ("tomhi", 2.5, 0.75), ("tomlo", 3, 0.8), ("tomlo", 3.5, 0.85)])
        let halfTime = kitPattern("Half-Time", 2, kit, length: 4, [("kick", 0, 0.8), ("snare", 2, 0.8), ("ohat", 1, 0.35), ("ohat", 3, 0.35)])
        let crash = kitPattern("Crash", 9, kit, length: 4, [("crash", 0, 0.8), ("kick", 0, 0.9)])

        let room = effect("reverb", ["mix": 0.18, "size": 0.45])
        // The upright is warm and dark: less low end under the driving parts, more sparkle on top.
        let lowCut = effect("eq", ["lowgain": -6, "lowfreq": 220, "midgain": -2, "midfreq": 400, "midq": 0.8, "highgain": 3])
        // The guitar leaves the low end to the bass and adds sparkle on top.
        let guitarEQ = effect("eq", ["lowgain": -8, "lowfreq": 250, "highgain": 3])
        let hall = effect("reverb", ["mix": 0.28, "size": 0.75])

        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 16, tracks: [
            track("Piano", 6, volume: -2, [clip(pianoIntro, at: 0, length: 16)], effects: [room]),
            track("Kalimba", 4, volume: -4, [clip(kalimba, at: 0, length: 16)], effects: [hall]),
            track("Drums", 7, volume: -4, [clip(fill, at: 12, length: 4)], effects: [room]),
        ])))

        let verseComp = Asset(name: "Verse", colorIndex: 2, content: .composition(Composition(length: 32, tracks: [
            track("Drums", 2, volume: -4, [clip(verseBeat, at: 0, length: 32)], effects: [room]),
            track("Shaker", 3, volume: -6, [clip(shaker, at: 16, length: 16)]),
            track("Bass", 1, volume: -3, [clip(bassVerse, at: 0, length: 32)]),
            track("Piano", 6, volume: -3, [clip(pianoVerse, at: 0, length: 32)], effects: [room]),
            track("Vibes", 9, volume: -5, [clip(vibes, at: 0, length: 32)], effects: [hall]),
            track("Guitar", 7, volume: -6, pan: -0.3, [clip(guitarVerse, at: 16, length: 16)], effects: [guitarEQ, room]),
        ])))

        let preComp = Asset(name: "Pre-Chorus", colorIndex: 5, content: .composition(Composition(length: 16, tracks: [
            track("Drums", 7, volume: -3, [clip(buildBeat, at: 0, length: 16)], effects: [room]),
            track("Bass", 1, volume: -2, [clip(bassPre, at: 0, length: 16)]),
            track("Piano", 6, volume: -2, [clip(pianoPre, at: 0, length: 16)], effects: [lowCut, room]),
            track("Organ", 8, volume: -6, [clip(organPre, at: 0, length: 16)],
                  effects: [keyframed("volume", [:], "volume", [(0, -18), (16, 0)]), hall]),
        ])))

        let chorusComp = Asset(name: "Chorus", colorIndex: 0, content: .composition(Composition(length: 32, tracks: [
            track("Drums", 2, volume: 0, [clip(chorusBeat, at: 0, length: 32)],
                  effects: [effect("compressor", ["threshold": -16, "ratio": 3, "attack": 10, "release": 120]),
                            effect("eq", ["lowgain": -2, "lowfreq": 80, "highgain": 4]), room]),
            track("Crash", 9, volume: -3, [clip(crash, at: 0, length: 4), clip(crash, at: 16, length: 4)]),
            track("Tambourine", 3, volume: -2, [clip(tambourine, at: 0, length: 32)]),
            // A bass recorded direct is light on the very bottom, so it gets a little lift there.
            track("Bass", 1, volume: 3, [clip(bassChorus, at: 0, length: 32)],
                  effects: [effect("eq", ["lowgain": 6, "lowfreq": 110, "midgain": -3, "midfreq": 260, "midq": 1]),
                            effect("saturator", ["drive": 4, "mix": 0.4])]),
            track("Piano", 6, volume: -1, [clip(pianoChorus, at: 0, length: 32)], effects: [lowCut, room]),
            // The organ's sub-octave pipes would thicken the low mids, so it sits on top.
            track("Guitar", 7, volume: -5, pan: -0.25, [clip(guitarChorus, at: 0, length: 32)], effects: [guitarEQ, room]),
            track("Organ", 8, volume: -9, [clip(organChorus, at: 0, length: 32)],
                  effects: [effect("eq", ["lowgain": -10, "lowfreq": 450]), hall]),
            track("Sax", 5, volume: 0, [clip(sax, at: 0, length: 32)],
                  effects: [effect("eq", ["lowgain": -4, "lowfreq": 250, "highgain": 2, "highfreq": 3000]),
                            effect("delay", ["time": 5, "mix": 0.15]), effect("reverb", ["mix": 0.22, "size": 0.6])]),
            track("Glock", 11, volume: -6, [clip(glock, at: 0, length: 32)], effects: [hall]),
        ])))

        let bridgeComp = Asset(name: "Bridge", colorIndex: 4, content: .composition(Composition(length: 16, tracks: [
            track("Drums", 2, volume: -5, [clip(halfTime, at: 0, length: 12), clip(fill, at: 12, length: 4)], effects: [room]),
            track("Bass", 1, volume: -3, [clip(bassBridge, at: 0, length: 16)]),
            track("Piano", 6, volume: -5, [clip(pianoBridge, at: 0, length: 16)], effects: [room]),
            track("Harp", 10, volume: -3, [clip(harp, at: 0, length: 16)], effects: [hall]),
            track("Kalimba", 4, volume: -6, [clip(kalimbaBridge, at: 0, length: 16)], effects: [hall]),
        ])))

        // The last chorus is the chorus (linked), with a sax harmony on top.
        let lastChorus = Asset(name: "Last Chorus", colorIndex: 1, content: .composition(Composition(length: 32, tracks: [
            track("Chorus", 0, [clip(chorusComp, at: 0, length: 32)]),
            track("Sax Harmony", 5, volume: -3, [clip(saxHarmony, at: 0, length: 32)],
                  effects: [effect("reverb", ["mix": 0.25, "size": 0.6])]),
        ])))

        let outro = Asset(name: "Outro", colorIndex: 11, content: .composition(Composition(length: 8, tracks: [
            track("Piano", 6, volume: -2, [clip(pianoEnd, at: 0, length: 8)], effects: [hall]),
            track("Crash", 9, volume: -4, [clip(crash, at: 0, length: 4)]),
        ])))

        var main = Composition(length: 38 * bar)
        main.tracks = [
            track("Intro", 11, [clip(intro, at: 0, length: 16)]),
            track("Verse", 2, [clip(verseComp, at: 4 * bar, length: 32)]),
            track("Pre-Chorus", 5, [clip(preComp, at: 12 * bar, length: 16)]),
            track("Choruses", 0, [clip(chorusComp, at: 16 * bar, length: 32), clip(lastChorus, at: 28 * bar, length: 32)]),
            track("Bridge", 4, [clip(bridgeComp, at: 24 * bar, length: 16)]),
            track("Outro", 11, [clip(outro, at: 36 * bar, length: 8)]),
        ]
        main.effects = [effect("compressor", ["threshold": -12, "ratio": 2, "attack": 30, "release": 200]),
                        effect("limiter", ["gain": 3, "ceiling": -1])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, verseComp, preComp, chorusComp, bridgeComp, lastChorus, outro],
              patterns: [pianoIntro, pianoVerse, pianoPre, pianoChorus, pianoBridge, pianoEnd, bassVerse, bassPre, bassChorus, bassBridge,
                         guitarVerse, guitarChorus,
                         kalimba, kalimbaBridge, vibes, harp, organPre, organChorus, sax, saxHarmony, glock, shaker, tambourine],
              beats: [verseBeat, chorusBeat, buildBeat, fill, halfTime, crash], fx: [])
        return p
    }
}
