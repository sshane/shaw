import XCTest
@testable import ShawCore

/// Pitch tracking, note finding, and tuning, on a synthetic voice: harmonics shaped by an "ah"
/// vowel's resonances, with a sharp note, a flat note with vibrato, and an "s" (noise) between them.
final class VocalTuneTests: XCTestCase {
    let sr = 48000.0

    struct Part { var midi: Double?; var seconds: Double; var vibratoCents = 0.0 }

    /// Vowel resonances (an "ah": peaks near 700, 1200, and 2600 Hz) applied to each harmonic.
    func formant(_ f: Double) -> Double {
        exp(-pow((f - 700) / 250, 2)) + 0.6 * exp(-pow((f - 1200) / 300, 2)) + 0.3 * exp(-pow((f - 2600) / 400, 2)) + 0.03
    }

    func voice(_ parts: [Part]) -> [Float] {
        var out: [Float] = []
        var phase = 0.0
        var seed: UInt64 = 7
        for part in parts {
            let n = Int(part.seconds * sr)
            for i in 0..<n {
                let t = Double(i) / sr
                guard let m = part.midi else {
                    // Silence, or (when negative seconds would be odd) noise: use midi nil + vibrato as a flag.
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let noise = part.vibratoCents > 0 ? (Double(seed >> 11) / Double(1 << 53) * 2 - 1) * 0.1 : 0
                    out.append(Float(noise))
                    continue
                }
                let f0 = 440 * pow(2, (m - 69 + part.vibratoCents / 100 * sin(2 * .pi * 5.5 * t)) / 12)
                phase += f0 / sr
                // Fade in and out over 20 ms so notes don't click.
                let env = min(1, min(t, part.seconds - t) / 0.02)
                var s = 0.0
                var k = 1.0
                while k * f0 < 5000 { s += sin(2 * .pi * k * phase) * formant(k * f0) / k; k += 1 }
                out.append(Float(s * 0.3 * env))
            }
        }
        return out
    }

    /// The take used throughout: A3 a third of a semitone sharp, an "s", C4 a quarter flat with vibrato.
    lazy var take: [Float] = voice([Part(midi: nil, seconds: 0.1), Part(midi: 57.35, seconds: 0.7),
                                    Part(midi: nil, seconds: 0.12, vibratoCents: 1), // noise
                                    Part(midi: 59.75, seconds: 0.8, vibratoCents: 20), Part(midi: nil, seconds: 0.1)])

    func frames(_ t: PitchTrack, _ from: Double, _ to: Double) -> [Float] {
        Array(t.pitch[Int(from / t.frameSeconds)..<min(t.pitch.count, Int(to / t.frameSeconds))])
    }
    func median(_ x: [Float]) -> Float { let s = x.filter { $0 > 0 }.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }

    func testTheTrackerHearsEachNote() {
        let t = PitchTracker.track(take, sampleRate: sr)
        XCTAssertEqual(median(frames(t, 0.25, 0.7)), 57.35, accuracy: 0.08, "the sharp A3, within 8 cents")
        XCTAssertEqual(median(frames(t, 1.1, 1.6)), 59.75, accuracy: 0.08, "the flat C4, under its vibrato")
        let s = frames(t, 0.84, 0.9)
        XCTAssertGreaterThan(Double(s.filter { $0 == 0 }.count) / Double(s.count), 0.7, "the \"s\" isn't sung")
        XCTAssertLessThan(frames(t, 0.2, 0.75).filter { $0 > 0 && abs($0 - 57.35) > 6 }.count, 2, "no octave jumps")
    }

    func testNotesAreFoundWithTheirCenters() {
        let t = PitchTracker.track(take, sampleRate: sr)
        let notes = NoteFinder.notes(in: t)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first?.center ?? 0, 57.35, accuracy: 0.06)
        XCTAssertEqual(notes.last?.center ?? 0, 59.75, accuracy: 0.06)
        // The vibrato shows up as quick modulation, not as drift.
        if let b = notes.last {
            let mod = b.modulation.map { Double($0) }, drift = b.drift.map { Double($0) }
            XCTAssertGreaterThan(rms(mod), 0.08, "vibrato is in the modulation")
            XCTAssertLessThan(rms(drift), rms(mod))
        }
    }

    func testTuningMovesNotesIntoTuneAndKeepsTheVibrato() {
        var tune = VocalTune()
        tune.amount = 1; tune.speed = 0; tune.straighten = 0
        let out = tune.render(take, sampleRate: sr, classes: Set(0..<12))
        XCTAssertEqual(out.count, take.count, "timing never changes")
        let t = PitchTracker.track(out, sampleRate: sr)
        let notes = NoteFinder.notes(in: t)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first?.center ?? 0, 57, accuracy: 0.07, "A3, in tune")
        XCTAssertEqual(notes.last?.center ?? 0, 60, accuracy: 0.07, "C4, in tune")
        let before = NoteFinder.notes(in: PitchTracker.track(take, sampleRate: sr)).last!.modulation.map { Double($0) }
        let after = notes.last!.modulation.map { Double($0) }
        XCTAssertEqual(rms(after), rms(before), accuracy: rms(before) * 0.35, "the vibrato is still there")
        // The "s" passes through untouched.
        let a = Int(0.82 * sr), b = Int(0.9 * sr)
        XCTAssertEqual(rms(out[a..<b].map(Double.init)), rms(take[a..<b].map(Double.init)), accuracy: 0.02)
    }

    func testRobotFlattensTheVibrato() {
        let out = VocalTune.robot.render(take, sampleRate: sr, classes: Set(0..<12))
        let notes = NoteFinder.notes(in: PitchTracker.track(out, sampleRate: sr))
        let before = NoteFinder.notes(in: PitchTracker.track(take, sampleRate: sr)).last!.modulation.map { Double($0) }
        XCTAssertLessThan(rms(notes.last!.modulation.map { Double($0) }), rms(before) * 0.4, "flat as a robot")
        XCTAssertEqual(notes.last?.center ?? 0, 60, accuracy: 0.07)
    }

    func testTheKeyDecidesWhereNotesGo() {
        // In A minor, a C4 sung a little flat goes to C; a B4-ish note would too, if it's sharper than B.
        let classes = VocalTune.scale(9, minor: true)
        XCTAssertEqual(VocalTune.snap(59.75, to: classes), 60)
        XCTAssertEqual(VocalTune.snap(61.45, to: classes), 62, "between C♯ and D, and C♯ isn't in A minor: up to D")
        XCTAssertEqual(VocalTune.snap(61.1, to: classes), 61, "clearly a C♯: kept, just in tune")
        XCTAssertEqual(VocalTune.snap(57.35, to: classes), 57)
    }

    /// How much of a steady note's sound is its harmonics (dB above everything between them), over
    /// `from`...`to` seconds, below 4 kHz.
    func harmonicity(_ x: [Float], midi: Double, from: Double, to: Double) -> Double {
        let a = Int(from * sr), len = Int((to - from) * sr)
        let f0 = 440 * pow(2, (midi - 69) / 12)
        var harm = 0.0, rest = 0.0
        // A plain DFT at each bin up to 4 kHz, 2 Hz apart, under a Hann window.
        let win = (0..<len).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(len)) }
        for hz in stride(from: 60.0, to: 4000, by: 2) {
            var re = 0.0, im = 0.0
            let w = 2 * .pi * hz / sr
            for i in 0..<len { let v = Double(x[a + i]) * win[i]; re += v * cos(w * Double(i)); im += v * sin(w * Double(i)) }
            let e = re * re + im * im
            let k = (hz / f0).rounded()
            if k >= 1 && abs(hz - k * f0) < 12 { harm += e } else { rest += e }
        }
        return 10 * log10(harm / max(rest, 1e-20))
    }

    func testShiftingAddsNoNoise() {
        // A steady note moved a third of a semitone stays as purely harmonic as the voice was.
        let sharp = voice([Part(midi: 60.35, seconds: 1.2)])
        let moved = VocalTune.robot.render(sharp, sampleRate: sr, classes: Set(0..<12))
        XCTAssertGreaterThan(harmonicity(moved, midi: 60, from: 0.4, to: 1.0), 45, "no clicks, no grit")
        XCTAssertEqual(median(frames(PitchTracker.track(moved, sampleRate: sr), 0.4, 1.0)), 60, accuracy: 0.01)
        // A flat C4 with vibrato, tuned hard: the correction follows the vibrato in time, so what's left
        // is a steady C4.
        let vib = voice([Part(midi: 59.7, seconds: 1.2, vibratoCents: 25)])
        let flat = VocalTune.robot.render(vib, sampleRate: sr, classes: Set(0..<12))
        let left = frames(PitchTracker.track(flat, sampleRate: sr), 0.4, 1.0).map { Double($0) - 60 }
        XCTAssertLessThan(rms(left), 0.03, "within 3 cents of C4 throughout")
        XCTAssertGreaterThan(harmonicity(flat, midi: 60, from: 0.4, to: 1.0), 30)
    }

    func testTheSongsKeyComesFromItsNotes() {
        // C major: the scale, with C, E, and G held longest.
        var cMajor = [Double](repeating: 0, count: 12)
        for (pc, w) in [(0, 4.0), (2, 1), (4, 3), (5, 1), (7, 3), (9, 1), (11, 1)] { cMajor[pc] = w }
        XCTAssertEqual(VocalTune.detectKey(cMajor), VocalTune.Key(root: 0, minor: false))
        // A minor: the same notes, leaning on A, C, and E.
        var aMinor = [Double](repeating: 0, count: 12)
        for (pc, w) in [(9, 4.0), (11, 1), (0, 3), (2, 1), (4, 3), (5, 1), (7, 1)] { aMinor[pc] = w }
        XCTAssertEqual(VocalTune.detectKey(aMinor), VocalTune.Key(root: 9, minor: true))
        XCTAssertNil(VocalTune.detectKey([Double](repeating: 0, count: 12)))
        XCTAssertEqual(VocalTune.Key(root: 3, minor: true).name, "E♭ minor")
        // Auto takes the song's key, else the take's; a chosen key overrides both.
        var t = VocalTune()
        XCTAssertEqual(t.key(song: nil, take: .init(root: 2, minor: false)), .init(root: 2, minor: false))
        t.scale = .minor; t.root = 4
        XCTAssertEqual(t.key(song: .init(root: 0, minor: false), take: nil), .init(root: 4, minor: true))
        t.scale = .chromatic
        XCTAssertNil(t.key(song: .init(root: 0, minor: false), take: nil))
    }

    func testAStereoTakeStaysTogether() {
        // Two channels shift as one: the same grains, so the image doesn't smear.
        let l = voice([Part(midi: 57.35, seconds: 0.8)]), r = l.map { $0 * 0.5 }
        let t = PitchTracker.track(l, sampleRate: sr)
        let cents = VocalTune.robot.corrections(t, notes: NoteFinder.notes(in: t), classes: Set(0..<12))
        let out = PitchShifter.shift([l, r], track: t, cents: cents)
        XCTAssertEqual(out.count, 2)
        for i in stride(from: 0, to: l.count, by: 97) { XCTAssertEqual(out[1][i], out[0][i] * 0.5, accuracy: 1e-5) }
    }

    /// Two recordings of one file, tuned differently, each get their own version, and a chosen
    /// key doesn't re-render when the song's key changes.
    func testTheCacheKeepsEachRecordingsOwnTuning() {
        let cache = TuneCache()
        let source = SampleData(left: take, sampleRate: sr)
        var natural = VocalTune.natural, robot = VocalTune.robot
        natural.scale = .chromatic; robot.scale = .chromatic
        let deadline = Date().addingTimeInterval(20)
        var a: SampleData?, b: SampleData?
        while (a == nil || b == nil || a === b) && Date() < deadline {
            a = cache.tuned("A", path: "take", source: source, tune: natural, songKey: nil)
            b = cache.tuned("B", path: "take", source: source, tune: robot, songKey: nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let na = try! XCTUnwrap(a), nb = try! XCTUnwrap(b)
        XCTAssertFalse(na === nb, "each recording plays its own settings")
        XCTAssertTrue(cache.tuned("A", path: "take", source: source, tune: natural, songKey: .init(root: 2, minor: false)) === na,
                      "a chosen key doesn't depend on the song's")
        XCTAssertTrue(cache.tunedSync("B", path: "take", source: source, tune: robot, songKey: nil) === nb, "export reuses it")
        XCTAssertFalse(cache.isRendering("take"))
        // Turned off: kept briefly (undo), then let go; nothing is wanted any more.
        cache.keep(owners: ["A"])
        XCTAssertNotNil(cache.takeKey("take"))
    }

    func rms(_ x: [Double]) -> Double { x.isEmpty ? 0 : sqrt(x.reduce(0) { $0 + $1 * $1 } / Double(x.count)) }
}
