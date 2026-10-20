import ShawCore

extension DemoProject {
    // MARK: - Glasswing

    /// "Glasswing": G minor melodic electro in the style of Monstercat (Pegboard Nerds, Rogue), 128 BPM,
    /// 36 bars (about 68 seconds).
    /// Intro (8) · Build (8) · Drop (8) · Drop B (8) · Outro (4)
    ///
    /// The story is a wish that keeps reaching higher: the hook asks a question, sighs, then climbs to
    /// its highest note and falls onto a chord from outside the key (A♭) before it finds its way home.
    /// What should surprise you: the build stops dead for a bar of solo piano before the drop; the
    /// second drop slides a darker chord under the same hook; and the ending lands somewhere other
    /// than home before it gets there.
    static func glasswing() -> Project {
        var p = Project(name: "Glasswing", bpm: 128)
        let bar = 4.0
        let kit = "house"

        // MARK: Harmony
        // Gm9 | E♭maj9 | Cm11 | Dsus4 → D7, then Gm9 | E♭maj9 | Cm11 | A♭maj7 → D7.
        // The keys' top voices barely move while the bass walks G – E♭ – C – D, so the chords
        // glow instead of stepping. A♭ is borrowed from outside the key: the bittersweet turn.
        struct Slot { let start: Double; let length: Double; let pad: [Int]; let root: Int }
        let gm9 = [58, 62, 65, 69], eb9 = [58, 62, 65, 67], cm11 = [58, 63, 65, 67]
        let dsus = [57, 60, 62, 67], d7 = [57, 60, 62, 66], ab7 = [56, 60, 63, 67]
        let G = 43, Eb = 39, C = 36, D = 38, Ab = 44
        func slots(dark: Bool = false) -> [Slot] {
            // The second drop puts A♭ under bar 3 where C was, and moves to D half a beat early,
            // right where the hook leaps up to its A.
            let third: [Slot] = dark
                ? [Slot(start: 8, length: 3.5, pad: ab7, root: Ab), Slot(start: 11.5, length: 2.5, pad: dsus, root: D)]
                : [Slot(start: 8, length: 4, pad: cm11, root: C), Slot(start: 12, length: 2, pad: dsus, root: D)]
            return [Slot(start: 0, length: 4, pad: gm9, root: G), Slot(start: 4, length: 4, pad: eb9, root: Eb)] + third + [
                Slot(start: 14, length: 2, pad: d7, root: D),
                Slot(start: 16, length: 4, pad: gm9, root: G), Slot(start: 20, length: 4, pad: eb9, root: Eb),
                Slot(start: 24, length: 4, pad: cm11, root: C), Slot(start: 28, length: 2, pad: ab7, root: Ab),
                Slot(start: 30, length: 2, pad: d7, root: D),
            ]
        }
        /// The sub's note: an octave under the bass, unless that's too low to hear.
        func subPitch(_ r: Int) -> Int { r - 12 >= 27 ? r - 12 : r }

        // A player, not a grid: each note a few milliseconds off and a little softer or harder.
        var seed: UInt64 = 0x6c61_7373_7769_6e67
        func rand() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53) * 2 - 1
        }
        func human(_ ns: [Note], time: Double, vel: Double) -> [Note] {
            ns.map { n in
                var n = n
                n.start = max(0, n.start + rand() * time)
                n.velocity = min(1, max(0.1, n.velocity + rand() * vel))
                return n
            }
        }

        // MARK: The hook
        // Sung, not programmed: every note on the eighth-note grid, in a long, short, short, long lilt
        // you can feel even without drums. Bar 1 rises D – C – D – F; bar 3 sings the same shape a step
        // higher; in bar 4 the melody's G falls to F♯ just as the chord resolves. The answer leaps to
        // B♭, holds the high C (the top of the song), and sinks onto the A♭ before turning for home.
        let hook: [(Int, Double, Double)] = [
            (74, 0, 1.5), (72, 1.5, 0.5), (74, 2, 0.5), (77, 2.5, 1.5),
            (79, 4, 1.5), (77, 5.5, 0.5), (74, 6, 2),
            (75, 8, 1.5), (74, 9.5, 0.5), (75, 10, 0.5), (79, 10.5, 1.5),
            (81, 12, 1.5), (79, 13.5, 0.5), (78, 14, 1.5), (74, 15.5, 1),
            (74, 16, 1.5), (72, 17.5, 0.5), (74, 18, 0.5), (77, 18.5, 1.5),
            (82, 20, 1.5), (79, 21.5, 0.5), (77, 22, 1.5), (79, 23.5, 0.5),
            (84, 24, 2), (82, 26, 0.5), (79, 26.5, 0.5), (75, 27, 1),
            (79, 28, 1), (75, 29, 1), (78, 30, 1.5), (81, 31.5, 0.5),
        ]
        /// Leaning on the notes that land on the beat, so the line breathes.
        func hookNotes(_ list: [(Int, Double, Double)], up: Int = 0, vel: Double) -> [Note] {
            list.map { Note(pitch: $0.0 + up, start: $0.1, length: $0.2,
                            velocity: vel - ($0.1.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 0.1)) }
        }
        let question = Array(hook.prefix { $0.1 < 16 })
        // The second drop's hook: the same tune, but its answer leaps to a high D (bar 6) instead of B♭.
        let hookB = hook.map { $0.1 == 20 ? (86, $0.1, $0.2) : $0 }

        // MARK: Keys and strings
        // Rolled chords, each note a little after the one under it, like a hand on the keys.
        func rolled(_ chord: [Int], at start: Double, length: Double, vel: Double) -> [Note] {
            chord.enumerated().map { i, pitch in
                Note(pitch: pitch, start: start + Double(i) * 0.05, length: length - Double(i) * 0.05, velocity: vel + Double(i) * 0.04)
            }
        }
        var keyNotes: [Note] = []
        for s in slots() {
            keyNotes += rolled(s.pad, at: s.start, length: s.length - 0.1, vel: 0.58)
            keyNotes.append(Note(pitch: s.root + 12, start: s.start, length: s.length - 0.05, velocity: 0.6))
        }
        let keys = synthPattern("Keys", 4, "Electric Piano", length: 32, human(keyNotes, time: 0.01, vel: 0.05))
        // The intro stays on the first four chords: the A♭ waits for the build.
        let firstHalf = keyNotes.filter { $0.start < 16 }
        let keysIntro = synthPattern("Keys Intro", 4, "Electric Piano", length: 16, human(firstHalf, time: 0.01, vel: 0.05))
        func stringNotes(_ ss: [Slot]) -> [Note] { ss.flatMap { s in s.pad.map { Note(pitch: $0, start: s.start, length: s.length, velocity: 0.6) } } }
        let strings = synthPattern("Strings", 10, "Strings", length: 32, gain: 1, stringNotes(slots()))
        let stringsIntro = synthPattern("Strings Intro", 10, "Strings", length: 16, gain: 1, stringNotes(slots().filter { $0.start < 16 }))

        /// Played like a pianist with the pedal: each note rings until the next one starts (up to
        /// `cap` beats), and the line swells as it climbs.
        func pianist(_ ns: [Note], cap: Double = 2) -> [Note] {
            let sorted = ns.sorted { $0.start < $1.start }
            return human(sorted.enumerated().map { i, n in
                var n = n
                if i + 1 < sorted.count { n.length = max(n.length, min(cap, sorted[i + 1].start - n.start + 0.03)) }
                n.velocity = min(1, n.velocity + Double(n.pitch - 74) * 0.012)
                return n
            }, time: 0.004, vel: 0.03)
        }
        // The real piano carries the hook's question in the intro. The answer waits for the drop.
        let pianoHook = synthPattern("Piano Hook", 6, "Grand Piano", length: 16, gain: 0, pianist(hookNotes(question, vel: 0.62)))
        // The fake-out: the build stops dead, and the piano alone plays the hook's last bar.
        let fakeOut = synthPattern("Piano Alone", 6, "Grand Piano", length: 4, gain: 1,
                                   human(rolled([44, 56, 60, 63], at: 0, length: 1.9, vel: 0.45) + rolled([38, 54, 57, 60], at: 2, length: 1.9, vel: 0.45),
                                         time: 0.004, vel: 0.03)
                                   + pianist(hookNotes(hook.filter { $0.1 >= 28 }.map { ($0.0, $0.1 - 28, $0.2) }, vel: 0.7)))

        // MARK: Drop sounds
        // Big chords: the keys' voicing on wide supersaws, ducked on every beat.
        func padPattern(_ name: String, _ color: Int, _ preset: String, gain: Double, up: Int, dark: Bool, rhythm: [(Double, Double, Double)]? = nil) -> Asset {
            var n: [Note] = []
            for s in slots(dark: dark) {
                if let rhythm {
                    for (t, len, v) in rhythm where t < s.length - 1e-9 {
                        n += s.pad.map { Note(pitch: $0 + up, start: s.start + t, length: min(len, s.length - t), velocity: v) }
                    }
                } else {
                    n += s.pad.map { Note(pitch: $0 + up, start: s.start, length: s.length - 0.05, velocity: 0.8) }
                }
            }
            return synthPattern(name, color, preset, length: 32, gain: gain, tweak: ["cutoff": 14000], n)
        }
        let saws = padPattern("Supersaws", 0, "Supersaw", gain: 3, up: 0, dark: false)
        let sawsDark = padPattern("Supersaws (Dark)", 0, "Supersaw", gain: 3, up: 0, dark: true)
        // The build: the same chords in eighths, accented 3 + 3 + 2 so they push forward.
        let eighths = (0..<8).map { i in (Double(i) * 0.5, 0.4, [0, 3, 6].contains(i) ? 0.85 : 0.55) }
        let sawsBuild = padPattern("Build Chords", 5, "Supersaw", gain: 3, up: 0, dark: false, rhythm: eighths)

        // Rolling bass: two sixteenths after every kick, and on the last one before a chord change
        // it jumps ahead to the next chord's root.
        func rolling(dark: Bool) -> [Note] {
            let ss = slots(dark: dark)
            var n: [Note] = []
            for (i, s) in ss.enumerated() {
                let next = ss[(i + 1) % ss.count].root
                var b = s.start.rounded(.down)
                while b < s.start + s.length - 1e-9 {
                    for (off, v) in [(0.5, 0.95), (0.75, 0.7)] where b + off >= s.start - 1e-9 && b + off < s.start + s.length - 1e-9 {
                        let last = b + off + 0.25 >= s.start + s.length - 1e-9
                        n.append(Note(pitch: last ? next : s.root, start: b + off, length: 0.22, velocity: v))
                    }
                    b += 1
                }
            }
            return n
        }
        // The grittier Pluck Bass this song was mixed with: a harder pluck, a pitch blip, drive, and drift.
        let grit: [String: Double] = ["sub": 0, "fenv": 0.65, "penv": 2, "drive": 0.35, "drift": 0.15]
        let bass = synthPattern("Rolling Bass", 1, "Pluck Bass", length: 32, gain: 0, tweak: grit, rolling(dark: false))
        let bassDark = synthPattern("Rolling Bass (Dark)", 1, "Pluck Bass", length: 32, gain: 0, tweak: grit, rolling(dark: true))
        func subNotes(dark: Bool, upTo end: Double = 32) -> [Note] {
            slots(dark: dark).filter { $0.start < end }.map {
                Note(pitch: subPitch($0.root), start: $0.start, length: min($0.length, end - $0.start) - 0.05, velocity: 0.9)
            }
        }
        let sub = synthPattern("Sub", 1, "Sub Bass", length: 32, gain: 0, subNotes(dark: false))
        let subDark = synthPattern("Sub (Dark)", 1, "Sub Bass", length: 32, gain: 0, subNotes(dark: true))
        let subBuild = synthPattern("Sub Build", 1, "Sub Bass", length: 32, gain: 0, subNotes(dark: false, upTo: 28))

        let lead = synthPattern("Lead", 7, "Hyper Saw", length: 32, gain: 2, human(hookNotes(hook, vel: 0.9), time: 0.003, vel: 0.04))
        // The chopped lead for the second drop: the hook played through one steady gate, a gallop on
        // every beat (hit, rest, hit-hit), so the slicing locks to the groove. Every note still starts
        // where it should; in the half-time bar the gallop slows to half speed.
        func chopLead(_ list: [(Int, Double, Double)]) -> [Note] {
            var out: [Note] = []
            var t = 0.0
            while t < 28 - 1e-9 {
                let half = t >= 24
                let step = half ? 0.5 : 0.25
                let pos = Int((t.truncatingRemainder(dividingBy: half ? 2 : 1) / step).rounded())
                let onset = list.first { abs($0.1 - t) < 1e-9 }
                if let n = list.first(where: { $0.1 <= t + 1e-9 && t < $0.1 + $0.2 - 1e-9 }), onset != nil || pos != 1 {
                    out.append(Note(pitch: n.0, start: t, length: step * 0.75, velocity: pos == 0 ? 0.95 : 0.78))
                }
                t += step
            }
            return out
        }
        let leadChopped = synthPattern("Chopped Lead", 7, "Hyper Saw", length: 32, gain: 2, chopLead(hookB.filter { $0.1 < 28 }))
        // The chip lead an octave up on the hook, for sparkle on top (a nod to Insan3Lik3).
        let chip = synthPattern("Chip Lead", 9, "Chip Lead", length: 32, gain: 0, hookNotes(hook, up: 12, vel: 0.8))
        // The build's pluck: the question, then the question again an octave up, cut off by the fake-out.
        let pluck = synthPattern("Build Pluck", 4, "Pluck", length: 32, gain: 2,
                                 hookNotes(question, vel: 0.8) + hookNotes(question.filter { $0.1 < 11.5 }.map { ($0.0, $0.1 + 16, $0.2) }, up: 12, vel: 0.8))

        // Three notes against four: the chip arp cycles the chord's top three notes in sixteenths,
        // so its pattern lands somewhere new on every beat.
        var arpNotes: [Note] = []
        for s in slots(dark: true) {
            let top = s.pad.suffix(3).map { $0 + 12 }
            var t = s.start, i = 0
            while t < s.start + s.length - 1e-9 {
                arpNotes.append(Note(pitch: top[i % 3], start: t, length: 0.2, velocity: i % 4 == 0 ? 0.8 : 0.5))
                t += 0.25; i += 1
            }
        }
        let arp = synthPattern("Chip Arp", 9, "Chip Arp", length: 32, gain: -2, arpNotes)

        // The last bar of the second drop: the hook's last two notes stutter in sixteenths.
        var stutterNotes: [Note] = []
        for i in 0..<8 { stutterNotes.append(Note(pitch: i < 4 ? 78 : 81, start: Double(i) * 0.25, length: 0.12, velocity: 0.6 + Double(i) * 0.05)) }
        let stutter = synthPattern("Stutter", 7, "Hyper Saw", length: 4, gain: 2, stutterNotes)

        // MARK: Vocals
        // Chopped vocals in the melody's gaps, never the melody itself: chord tones on the off-beats,
        // 32nd-note stutters, and jumps up an octave, with a climbing roll at the end of every four
        // bars. Each pitch picks the nearest of her three vowels, so the chops change color as they move.
        func chopNotes(_ ss: [Slot], melody: [(Int, Double, Double)], dense: Bool, end: Double = 32) -> [Note] {
            // (beat in the bar, length, chord tone: 0 low, 1 middle, 2 top, 3 the low one an octave up)
            let a: [(Double, Double, Int)] = [(0.5, 0.2, 2), (0.75, 0.15, 2), (1.75, 0.2, 1),
                                              (2.75, 0.1, 3), (2.875, 0.1, 3), (3, 0.2, 2), (3.5, 0.3, 0)]
            let b: [(Double, Double, Int)] = [(0.5, 0.15, 1), (1, 0.1, 2), (1.125, 0.1, 2), (1.25, 0.2, 3),
                                              (2.5, 0.2, 2), (2.75, 0.2, 1), (3.25, 0.1, 0), (3.375, 0.1, 1), (3.5, 0.1, 2), (3.625, 0.3, 3)]
            let roll: [(Double, Double, Int)] = (0..<8).map { (3 + Double($0) * 0.125, 0.1, $0 % 4) }
            var out: [Note] = []
            for bar in 0..<8 {
                var hits = dense && bar % 2 == 1 ? b : a
                if bar % 4 == 3 { hits = hits.filter { $0.0 < 3 } + roll }
                for (i, (pos, len, tone)) in hits.enumerated() {
                    let t = Double(bar) * 4 + pos
                    guard t < end, let slot = ss.last(where: { $0.start <= t + 1e-9 }) else { continue }
                    let top = slot.pad.suffix(3).map { $0 + 12 }
                    let tones = top + [top[0] + 12]
                    // Skip a chop that would rub a half step against the melody.
                    let sung = melody.filter { $0.1 < t + len && $0.1 + $0.2 > t }.map(\.0)
                    guard let pitch = ([tones[tone]] + tones).first(where: { c in
                        !sung.contains { m in [1, 11].contains(((c - m) % 12 + 12) % 12) }
                    }) else { continue }
                    let rising = bar % 4 == 3 && pos >= 3 ? 0.55 + (pos - 3) * 0.4 : 0
                    out.append(Note(pitch: pitch, start: t, length: len, velocity: rising > 0 ? rising : (i % 2 == 0 ? 0.85 : 0.65)))
                }
            }
            return out
        }
        let vox = synthPattern("Vocal Chops", 3, "Vocal Chops", length: 32, gain: 0, chopNotes(slots(), melody: hook, dense: false))
        let voxB = synthPattern("Vocal Chops B", 3, "Vocal Chops", length: 32, gain: 0,
                                chopNotes(slots(dark: true), melody: hookB, dense: true, end: 28))
        // A choir of the same "ah" an octave above the chords, close to where she sang it.
        func aahs(_ ss: [Slot], melody: [(Int, Double, Double)]) -> Asset {
            var inst = Instrument.sampler(SampleLibrary.bundledPrefix + "Instruments/Vocal Chops/082.caf")
            for (k, v) in ["playmode": 0, "root": 82, "a": 0.35, "r": 1.2, "volume": 0] as [String: Double] { inst.params[k] = v }
            // It leaves out any note a half step from what the melody sings over that chord.
            let ns = ss.flatMap { s -> [Note] in
                let sung = melody.filter { $0.1 < s.start + s.length && $0.1 + $0.2 > s.start }.map(\.0)
                return s.pad.suffix(3).map { $0 + 12 }
                    .filter { c in !sung.contains { m in [1, 11].contains(((c - m) % 12 + 12) % 12) } }
                    .map { Note(pitch: $0, start: s.start, length: s.length - 0.05, velocity: 0.7) }
            }
            return Asset(name: "Aah Choir", colorIndex: 3, content: .notes(NotePattern(length: 32, notes: ns, instrument: inst)))
        }
        let choir = aahs(slots(), melody: hook)
        // The "ooh" sings the chords' top three notes, soft, like a choir behind the piano.
        func oohs(_ ss: [Slot], end: Double = 32) -> [Note] {
            ss.filter { $0.start < end }.flatMap { s in
                s.pad.suffix(3).map { Note(pitch: $0, start: s.start, length: min(s.length, end - s.start) - 0.05, velocity: 0.7) }
            }
        }
        // One note, up high: the singer's "ah" lifted to D6, swelling in just before the piano reaches
        // its top A, so the voice floats above the climax of the intro.
        var highInst = Instrument.sampler(SampleLibrary.bundledPrefix + "Instruments/Vocal Chops/082.caf")
        for (k, v) in ["playmode": 0, "root": 82, "a": 0.6, "r": 1.5, "volume": 0] as [String: Double] { highInst.params[k] = v }
        let highVoice = Asset(name: "High Voice", colorIndex: 3, content: .notes(NotePattern(length: 16,
            notes: [Note(pitch: 86, start: 11.5, length: 4, velocity: 0.8)], instrument: highInst)))
        let oohIntro = synthPattern("Ooh", 3, "Ooh Pad", length: 16, gain: 0, oohs(slots(), end: 16))
        let oohFakeOut = synthPattern("Ooh Alone", 3, "Ooh Pad", length: 4, gain: 0,
                                      oohs(slots().filter { $0.start >= 28 }.map { Slot(start: $0.start - 28, length: $0.length, pad: $0.pad, root: $0.root) }, end: 4))
        func shout(_ name: String, _ file: String, length: Double, at times: [Double], gain: Double) -> Asset {
            var inst = Instrument.sampler(SampleLibrary.bundledPrefix + "Vocals/\(file).caf")
            inst.params["volume"] = gain
            return Asset(name: name, colorIndex: 3, content: .notes(NotePattern(length: length,
                notes: times.map { Note(pitch: 60, start: $0, length: 1, velocity: 0.9) }, instrument: inst)))
        }
        let hey = shout("Hey", "Hey", length: 32, at: [0, 16], gain: -2)
        // Dry and snappy up front, with a long, airy tail behind each chop.
        let voxFX = [effect("eq", ["lowgain": -12, "lowfreq": 400, "midgain": 3, "midfreq": 2500, "midq": 0.7, "highgain": 4, "highfreq": 6000]),
                     effect("utility", ["width": 1.3]),
                     effect("delay", ["time": 3, "feedback": 0.2, "mix": 0.15]),
                     effect("reverb", ["mix": 0.38, "size": 0.92, "predelay": 30])]
        let choirFX = [effect("eq", ["lowgain": -12, "lowfreq": 400, "highgain": 2, "highfreq": 8000]),
                       effect("pump", ["rate": 2, "depth": 0.4]), effect("reverb", ["mix": 0.55, "size": 0.95])]
        let oohFX = [effect("eq", ["lowgain": -10, "lowfreq": 300]), effect("reverb", ["mix": 0.45, "size": 0.9])]

        // MARK: Outro
        // The drop ends on D7, the chord that wants to go home to G minor. Instead the outro lands on
        // E♭ and the piano sings the hook's answer once more, softly, over E♭ – Cm – Gm – D. That D7
        // asks again, and the second time the song takes the long way home: E♭, then Cm, then G minor.
        let outA = [Slot(start: 0, length: 4, pad: eb9, root: Eb), Slot(start: 4, length: 4, pad: cm11, root: C),
                    Slot(start: 8, length: 4, pad: gm9, root: G), Slot(start: 12, length: 2, pad: dsus, root: D),
                    Slot(start: 14, length: 2, pad: d7, root: D)]
        let outB = [Slot(start: 16, length: 4, pad: eb9, root: Eb), Slot(start: 20, length: 4, pad: cm11, root: C),
                    Slot(start: 24, length: 8, pad: gm9, root: G)]
        var outroKeys: [Note] = []
        for (i, s) in (outA + outB).enumerated() {
            let vel = s.start < 16 ? 0.62 : 0.6 - Double(i - outA.count) * 0.05
            outroKeys += rolled(s.pad, at: s.start, length: s.length - 0.1, vel: vel)
                + [Note(pitch: s.root + 12, start: s.start, length: s.length - 0.1, velocity: vel)]
        }
        let stringsEnd = synthPattern("Strings Ending", 10, "Strings", length: 32, gain: 1,
                                      (outA + outB).flatMap { s in s.pad.map { Note(pitch: $0, start: s.start, length: s.length, velocity: 0.6) } })
        let keysEnd = synthPattern("Keys Ending", 4, "Electric Piano", length: 32, human(outroKeys, time: 0.01, vel: 0.04))
        // The sub stays for the first pass so the floor doesn't fall out from under the drop, then lets go.
        let subEnd = synthPattern("Sub Ending", 1, "Sub Bass", length: 32, gain: 0,
                                  outA.map { Note(pitch: subPitch($0.root), start: $0.start, length: $0.length - 0.05, velocity: 0.8) })
        // First the hook's answer, then the walk down from the high B♭, the hook's reach, to rest on G.
        let pianoEnd = synthPattern("Piano Ending", 6, "Grand Piano", length: 32, gain: 0, pianist(notes([
            (79, 0, 1.5), (77, 1.5, 0.5), (74, 2, 2),
            (75, 4, 1.5), (74, 5.5, 0.5), (75, 6, 0.5), (79, 6.5, 1.5),
            (74, 8, 1.5), (72, 9.5, 0.5), (74, 10, 0.5), (77, 10.5, 1.5),
            (81, 12, 1.5), (79, 13.5, 0.5), (78, 14, 1.5), (74, 15.5, 1),
            (82, 16.5, 1), (79, 17.5, 0.5), (77, 18, 1), (79, 19, 1),
            (75, 20, 1.5), (74, 21.5, 0.5), (72, 22, 1), (69, 23, 1),
            (67, 24, 7.5),
        ], vel: 0.55), cap: 7.5))
        let oohEnd = synthPattern("Ooh Ending", 3, "Ooh Pad", length: 32, gain: 0, oohs(outA + outB, end: 32))
        // The drop's chops, one per chord, echoing off into the reverb like they're in the next room.
        let voxEnd = synthPattern("Vocal Echoes", 3, "Vocal Chops", length: 32, gain: 0,
                                  outA.map { Note(pitch: $0.pad.last! + 12, start: $0.start + 1.5, length: 0.3, velocity: 0.6) })

        // MARK: FX
        let riser = synthPattern("Riser", 9, "Noise Riser", length: 32, [Note(pitch: 60, start: 0, length: 28, velocity: 1)])
        let boom = synthPattern("Impact", 3, "Impact Boom", length: 4, [Note(pitch: 30, start: 0, length: 3, velocity: 1)])

        // MARK: Drums
        // Four on the floor, a clap and snare together on 2 and 4, open hats on the off-beats, and
        // sixteenth hats a hair late so it swings a little.
        func groove(_ o: Double, skipLastOhat: Bool = false) -> [(String, Double, Double)] {
            var h: [(String, Double, Double)] = []
            for b in 0..<4 {
                let t = o + Double(b)
                h.append(("kick", t, b == 0 ? 1 : 0.94))
                if b % 2 == 1 { h += [("clap", t, 0.92), ("snare", t, 0.5)] }
                if !(skipLastOhat && b == 3) { h.append(("ohat", t + 0.5, 0.55)) }
                h += [("chat", t + 0.27, b % 2 == 0 ? 0.42 : 0.34), ("chat", t + 0.77, 0.38)]
            }
            return h
        }
        let beat = kitPattern("Drop Beat", 2, kit, length: 4, groove(0) + [("perc", 3.75, 0.3)])
        // End of four bars: a snare run into the next phrase.
        let fill = kitPattern("Fill", 8, kit, length: 4, groove(0, skipLastOhat: true)
                              + [("snare", 3.25, 0.6), ("snare", 3.5, 0.75), ("snare", 3.75, 0.9)])
        // End of eight: snares, then toms falling into the next drop.
        let bigFill = kitPattern("Big Fill", 8, kit, length: 4, [("kick", 0, 1), ("kick", 1, 0.94), ("clap", 1, 0.92), ("kick", 2, 0.94)]
                                 + (0..<4).map { ("snare", 2 + Double($0) * 0.25, 0.55 + Double($0) * 0.08) }
                                 + [("tomhi", 3, 0.8), ("tomhi", 3.25, 0.8), ("tomlo", 3.5, 0.9), ("tomlo", 3.75, 0.95)])
        // The last two bars of the second drop: half time, a breath while the song winds down.
        let halfTime = kitPattern("Half Bar", 2, kit, length: 4, [("kick", 0, 1), ("snare", 2, 0.9), ("clap", 2, 0.9), ("kick", 2.75, 0.6)]
                                  + (0..<8).map { ("chat", Double($0) * 0.5, 0.3) })
        // The build: kick on every beat getting harder, claps fall away, then the snare speeds up.
        var buildHits: [(String, Double, Double)] = []
        for b in 0..<28 { buildHits.append(("kick", Double(b), 0.7 + Double(b) * 0.01)) }
        for b in stride(from: 1.0, to: 16, by: 2) { buildHits.append(("clap", b, 0.55)) }
        for i in 0..<16 { buildHits.append(("snare", 16 + Double(i) * 0.5, 0.35 + Double(i) * 0.02)) }
        for i in 0..<16 { buildHits.append(("snare", 24 + Double(i) * 0.25, 0.6 + Double(i) * 0.025)) }
        buildHits += [("snare", 31.5, 0.8), ("snare", 31.75, 1)] // the pickup out of the fake-out
        let buildBeat = kitPattern("Build", 5, kit, length: 32, buildHits)
        let crash = kitPattern("Crash", 9, kit, length: 4, [("crash", 0, 0.85)])

        // MARK: Effects
        let room = effect("reverb", ["mix": 0.2, "size": 0.5])
        let hall = effect("reverb", ["mix": 0.32, "size": 0.85])
        let pump = effect("pump", ["rate": 2, "depth": 0.7, "release": 0.5])
        let leadFX = [effect("eq", ["lowgain": -9, "lowfreq": 400, "midgain": 2, "midfreq": 3000, "midq": 0.8]),
                      effect("delay", ["time": 6, "feedback": 0.3, "mix": 0.16]), effect("reverb", ["mix": 0.22, "size": 0.7])]
        let sawFX = [effect("eq", ["lowgain": -10, "lowfreq": 300, "midgain": -5, "midfreq": 550, "midq": 0.8, "highgain": 3, "highfreq": 6000]),
                     effect("utility", ["width": 1.5]), pump,
                     effect("reverb", ["mix": 0.22, "size": 0.8])]
        let bassFX = [effect("eq", ["lowgain": -6, "lowfreq": 90, "midgain": -4, "midfreq": 320, "midq": 1]), effect("saturator", ["drive": 6, "mix": 0.4]),
                      effect("pump", ["rate": 2, "depth": 0.5])]

        // MARK: Sections
        let intro = Asset(name: "Intro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Keys", 4, volume: -9, [clip(keysIntro, at: 0, length: 32)], effects: [effect("reverb", ["mix": 0.3, "size": 0.75])]),
            track("Strings", 10, volume: -10, [clip(stringsIntro, at: 0, length: 32)],
                  effects: [keyframed("volume", [:], "volume", [(0, -30), (16, -6), (32, 0)]), hall]),
            track("Piano", 6, volume: -5, [clip(pianoHook, at: 16, length: 16)], effects: [hall]),
            track("Ooh", 3, volume: -9, [clip(oohIntro, at: 16, length: 16)], effects: oohFX),
            track("High Voice", 3, volume: -8, [clip(highVoice, at: 16, length: 16)],
                  effects: [effect("eq", ["lowgain": -10, "lowfreq": 400]), effect("reverb", ["mix": 0.5, "size": 0.95, "predelay": 40])]),
            track("Sub", 1, volume: -12, [clip(sub, at: 16, length: 16)]),
        ])))

        let build = Asset(name: "Build", colorIndex: 5, content: .composition(Composition(length: 32, tracks: [
            track("Drums", 5, volume: -7, [clip(buildBeat, at: 0, length: 32)]),
            track("Chords", 5, volume: -11, [clip(sawsBuild, at: 0, length: 28)],
                  effects: [effect("eq", ["lowgain": -9, "lowfreq": 250]),
                            keyframed("filter", ["resonance": 0.3], "cutoff", [(0, 350), (28, 9000)]), room]),
            track("Keys", 4, volume: -12, [clip(keys, at: 0, length: 28)], effects: [room]),
            track("Strings", 10, volume: -10, [clip(strings, at: 0, length: 28)], effects: [hall]),
            track("Pluck", 4, volume: -7, [clip(pluck, at: 0, length: 28)],
                  effects: [effect("delay", ["time": 6, "feedback": 0.3, "mix": 0.2]), room]),
            track("Sub", 1, volume: -9, [clip(subBuild, at: 0, length: 32)]),
            track("Riser", 9, volume: -10, [clip(riser, at: 0, length: 32)], effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
            track("Piano Alone", 6, volume: -3, [clip(fakeOut, at: 28, length: 4)],
                  effects: [effect("reverb", ["mix": 0.4, "size": 0.9])]),
            track("Ooh", 3, volume: -12, [clip(oohFakeOut, at: 28, length: 4)], effects: oohFX),
            track("Aah Choir", 3, volume: -14, [clip(choir, at: 16, length: 12)],
                  effects: [effect("eq", ["lowgain": -12, "lowfreq": 400]), effect("reverb", ["mix": 0.55, "size": 0.95])]),
        // It starts well under the drop and climbs, so the drop has somewhere to land.
        ], effects: [keyframed("volume", [:], "volume", [(0, -7), (27, 0)])])))

        func drop(_ name: String, _ color: Int, dark: Bool) -> Asset {
            let drums: [Clip] = dark
                ? [clip(beat, at: 0, length: 12), clip(fill, at: 12, length: 4), clip(beat, at: 16, length: 8),
                   clip(halfTime, at: 24, length: 8)]
                : [clip(beat, at: 0, length: 12), clip(fill, at: 12, length: 4), clip(beat, at: 16, length: 12), clip(bigFill, at: 28, length: 4)]
            let end = 32.0
            var tracks = [
                // Less 909 boom, more hat sizzle.
                track("Drums", 2, drums, effects: [effect("eq", ["lowgain": -3, "lowfreq": 70, "highgain": 5, "highfreq": 7000])]),
                track("Supersaws", 0, volume: -7, [clip(dark ? sawsDark : saws, at: 0, length: end)], effects: sawFX),
                track("Sub", 1, volume: -10, [clip(dark ? subDark : sub, at: 0, length: end)], effects: [effect("pump", ["rate": 2, "depth": 0.6])]),
                track("Bass", 1, volume: -6, [clip(dark ? bassDark : bass, at: 0, length: end)], effects: bassFX),
                // Halfway through, the lead switches from the hook to the riff.
                track("Lead", 7, volume: -4, [clip(dark ? leadChopped : lead, at: 0, length: end)], effects: leadFX),
                track("Chip Lead", 9, volume: dark ? -60 : -13, [clip(chip, at: 0, length: end)],
                      effects: [effect("delay", ["time": 6, "mix": 0.2]), room]),
                // The chops are the only voice in the drop, so nothing that sings in her range hides them.
                track("Vocal Chops", 3, volume: 0, [clip(dark ? voxB : vox, at: 0, length: end)], effects: voxFX),
            ]
            if dark {
                tracks += [
                    track("Chip Arp", 9, volume: -14, [clip(arp, at: 0, length: end)],
                          effects: [effect("delay", ["time": 5, "feedback": 0.25, "mix": 0.18]), effect("utility", ["width": 1.4]), room]),
                    track("Stutter", 7, volume: -4, [clip(stutter, at: 28, length: 4)], effects: leadFX),
                    track("Hey", 3, volume: -6, [clip(hey, at: 0, length: 32)], effects: [effect("reverb", ["mix": 0.25, "size": 0.7])]),
                ]
            }
            // The second drop closes its filter over the last two bars and melts into the outro.
            let fade = dark ? [keyframed("filter", ["resonance": 0.2], "cutoff", [(0, 20000), (24, 20000), (32, 700)]),
                               keyframed("volume", [:], "volume", [(0, 0), (24, 0), (32, -5)])] : []
            return Asset(name: name, colorIndex: color, content: .composition(Composition(length: 32, tracks: tracks, effects: fade)))
        }
        let dropA = drop("Drop", 0, dark: false)
        let dropB = drop("Drop B", 1, dark: true)

        let outro = Asset(name: "Outro", colorIndex: 11, content: .composition(Composition(length: 32, tracks: [
            track("Keys", 4, volume: -8, [clip(keysEnd, at: 0, length: 32)], effects: [effect("reverb", ["mix": 0.35, "size": 0.85])]),
            track("Strings", 10, volume: -10, [clip(stringsEnd, at: 0, length: 32)],
                  effects: [keyframed("volume", [:], "volume", [(0, 0), (20, 0), (32, -30)]), hall]),
            track("Piano", 6, volume: -5, [clip(pianoEnd, at: 0, length: 32)], effects: [hall]),
            track("Sub", 1, volume: -14, [clip(subEnd, at: 0, length: 16)]),
            track("Vocal Echoes", 3, volume: -6, [clip(voxEnd, at: 0, length: 16)],
                  effects: [effect("eq", ["lowgain": -12, "lowfreq": 400]), effect("delay", ["time": 6, "feedback": 0.45, "pingpong": 1, "mix": 0.35]),
                            effect("reverb", ["mix": 0.5, "size": 0.95])]),
            track("Ooh", 3, volume: -9, [clip(oohEnd, at: 0, length: 32)], effects: oohFX),
            // The intro's high "ah" comes back over the last chord.
            track("High Voice", 3, volume: -10, [clip(highVoice, at: 16, length: 16)],
                  effects: [effect("eq", ["lowgain": -10, "lowfreq": 400]), effect("reverb", ["mix": 0.5, "size": 0.95, "predelay": 40])]),
        ])))

        var main = Composition(length: 40 * bar)
        main.tracks = [
            track("Intro", 11, [clip(intro, at: 0, length: 32)]),
            track("Build", 5, [clip(build, at: 8 * bar, length: 32)]),
            track("Drops", 0, [clip(dropA, at: 16 * bar, length: 32), clip(dropB, at: 24 * bar, length: 32)]),
            track("Outro", 11, [clip(outro, at: 32 * bar, length: 32)]),
            track("Crash", 9, volume: -6, [16, 20, 24].map { clip(crash, at: Double($0) * bar, length: 4) }),
            track("FX", 3, volume: -6, [clip(boom, at: 16 * bar, length: 4), clip(boom, at: 24 * bar, length: 4)],
                  effects: [effect("reverb", ["mix": 0.35, "size": 0.9])]),
        ]
        main.effects = [effect("eq", ["midgain": -2.5, "midfreq": 900, "midq": 0.7, "highgain": 3, "highfreq": 5000]), effect("compressor", ["threshold": -10, "ratio": 2, "attack": 30, "release": 200]),
                        effect("limiter", ["gain": 4.5, "ceiling": -1])]
        p.updateComposition(p.mainCompositionID) { $0 = main }
        filed(&p, sections: [intro, build, dropA, dropB, outro],
              patterns: [keys, keysIntro, strings, stringsIntro, pianoHook, fakeOut, saws, sawsDark, sawsBuild, bass, bassDark, sub, subDark, subBuild,
                         lead, leadChopped, chip, pluck, arp, stutter, keysEnd, stringsEnd, pianoEnd, subEnd],
              beats: [beat, fill, bigFill, halfTime, buildBeat, crash], fx: [riser, boom, highVoice, vox, voxB, choir, oohIntro, oohFakeOut, oohEnd, voxEnd, hey])
        return p
    }
}
