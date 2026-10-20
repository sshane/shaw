import XCTest
@testable import ShawCore
@testable import Shaw

/// A theory check for the demo songs, since nobody writing them can listen: it flattens every
/// pitched note through all nested compositions and flags the moments that sound like wrong notes.
enum MusicLint {
    struct Event { let pitch: Int; let start: Double; let end: Double; let part: String }

    /// Every pitched (non-drum) note as heard in the song, in song beats.
    static func flatten(_ p: Project) -> [Event] {
        var out: [Event] = []
        func walk(_ comp: Composition, from: Double, to: Double, shift: Double, depth: Int) {
            guard depth < 8 else { return }
            for t in comp.tracks where !t.mute {
                for c in t.clips where !c.mute {
                    let a = max(from, c.start + shift), b = min(to, c.end + shift)
                    guard a < b, let asset = p.asset(c.assetID) else { continue }
                    switch asset.content {
                    case .composition(let inner):
                        // Clip time t maps to inner time (t - start + offset), looping if needed.
                        let len = inner.length
                        var passStart = c.start + shift - c.offset
                        while passStart < b {
                            walk(inner, from: max(a, passStart), to: min(b, passStart + len), shift: passStart, depth: depth + 1)
                            if !c.loops { break }
                            passStart += len
                        }
                    // Drum kits, Shaw's hand percussion, and its shouts aren't pitched.
                    case .notes(let pat) where !pat.instrument.isDrumKit
                        && !(pat.instrument.sample ?? "").hasPrefix(SampleLibrary.bundledPrefix + "Percussion/")
                        && !(pat.instrument.sample ?? "").hasPrefix(SampleLibrary.bundledPrefix + "Vocals/"):
                        if pat.instrument.preset.contains("Riser") || pat.instrument.preset.contains("lifter")
                            || pat.instrument.preset.contains("Impact") || pat.instrument.preset.contains("Zap") { continue }
                        let len = pat.length
                        var passStart = c.start + shift - c.offset
                        while passStart < b {
                            for n in pat.notes {
                                let s = max(a, passStart + n.start), e = min(b, passStart + min(n.end, len))
                                if s < e { out.append(Event(pitch: n.pitch, start: s, end: e, part: asset.name)) }
                            }
                            if !c.loops { break }
                            passStart += len
                        }
                    default: break
                    }
                }
            }
        }
        if let main = p.composition(p.mainCompositionID) { walk(main, from: 0, to: main.length, shift: 0, depth: 0) }
        return out
    }

    struct Report {
        var clashes: [(Double, String)] = []
        var outOfKey: [(Double, String)] = []
        var description: String {
            var s = "\(clashes.count) half-step clashes, \(outOfKey.count) notes out of key\n"
            for c in clashes.prefix(25) { s += String(format: "  clash  bar %5.2f  %@\n", c.0 / 4 + 1, c.1 as NSString) }
            for c in outOfKey.prefix(15) { s += String(format: "  key    bar %5.2f  %@\n", c.0 / 4 + 1, c.1 as NSString) }
            return s
        }
    }

    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static func name(_ p: Int) -> String { "\(names[p % 12])\(p / 12 - 1)" }

    /// `scale`: pitch classes in key. Clashes: two different parts a minor 2nd or minor 9th apart,
    /// overlapping for more than a sixteenth note.
    /// `strict`: also flag a half step between parts spread across octaves (like A5 over an A♭ bass).
    static func check(_ p: Project, scale: Set<Int>, strict: Bool = false) -> Report {
        let ev = flatten(p).sorted { $0.start < $1.start }
        var r = Report()
        for (i, a) in ev.enumerated() {
            if !scale.contains(a.pitch % 12) { r.outOfKey.append((a.start, "\(a.part) \(name(a.pitch))")) }
            for b in ev[(i + 1)...] {
                if b.start >= a.end { break }
                let overlap = min(a.end, b.end) - max(a.start, b.start)
                // Minor 2nd or minor 9th: the upper note a half step above the lower one's pitch class.
                // (A major 7th, like A under G#, is the lush maj7 sound and is fine.)
                let interval = abs(a.pitch - b.pitch)
                // Within one part only adjacent half steps count (a deliberate 9th spread across octaves is fine).
                let crossClash = strict ? (interval % 12 == 1) : (interval == 1 || interval == 13)
                if overlap > 0.25, a.part == b.part ? interval == 1 : crossClash {
                    r.clashes.append((max(a.start, b.start), "\(a.part) \(name(a.pitch)) vs \(b.part) \(name(b.pitch))"))
                }
            }
        }
        return r
    }
}

final class MusicLintTests: XCTestCase {
    /// No demo song may have wrong-sounding half-step rubs or notes outside its key.
    func testDemoSongsHaveNoWrongNotes() {
        let major: (Int) -> Set<Int> = { root in Set([0, 2, 4, 5, 7, 9, 11].map { ($0 + root) % 12 }) }
        let minor: (Int) -> Set<Int> = { root in Set([0, 2, 3, 5, 7, 8, 10].map { ($0 + root) % 12 }) }
        // G7 in C minor uses B natural (harmonic minor), so allow it there.
        for (p, key) in [(DemoProject.starlightFM(), minor(0).union([11])), (DemoProject.afterburn(), minor(6)), (DemoProject.lanterns(), major(4)),
                         (DemoProject.postcards(), major(2))] {
            let r = MusicLint.check(p, scale: key)
            XCTAssertTrue(r.clashes.isEmpty && r.outOfKey.isEmpty, "\(p.name): \(r.description)")
        }
        // Glasswing borrows F# (the D7) and Ab (the Ab7), and is held to the strict octave-spread check.
        let r = MusicLint.check(DemoProject.glasswing(), scale: minor(7).union([6, 8]), strict: true)
        XCTAssertTrue(r.clashes.isEmpty && r.outOfKey.isEmpty, "Glasswing: \(r.description)")
        // Sunroom borrows F, C, and G (its D minor 6 and F major 9).
        let s = MusicLint.check(DemoProject.sunroom(), scale: major(9).union([5, 0, 7]), strict: true)
        XCTAssertTrue(s.clashes.isEmpty && s.outOfKey.isEmpty, "Sunroom: \(s.description)")
    }
}
