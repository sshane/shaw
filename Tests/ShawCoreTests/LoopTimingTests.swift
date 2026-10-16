import XCTest
@testable import ShawCore

/// Regression: the first hit of a beat was sometimes skipped when playback looped.
final class LoopTimingTests: XCTestCase {
    /// Count drum onsets: a loud sample after at least `gap` seconds of near-silence.
    func onsets(_ x: [Float], sr: Double, gap: Double = 0.15) -> Int {
        var count = 0, quiet = Int(gap * sr)
        for v in x {
            if abs(v) > 0.15 {
                if quiet >= Int(gap * sr) { count += 1 }
                quiet = 0
            } else {
                quiet += 1
            }
        }
        return count
    }

    func kickProject(bpm: Double, clipLength: Double) -> Project {
        var p = Project(bpm: bpm)
        var d = DrumPattern(kit: "house", steps: 16)
        d.rows[0].steps[0] = 1 // a single kick on beat 1
        let beat = Asset(name: "K", colorIndex: 0, content: .drums(d))
        var n = NotePattern(length: 4, instrument: .preset("Pluck"))
        n.notes = [Note(pitch: 60, start: 0, length: 0.1)]
        let notes = Asset(name: "N", colorIndex: 0, content: .notes(n))
        p.assets += [beat, notes]
        p.updateComposition(p.mainCompositionID) { c in
            c.length = max(clipLength, 4)
            var t = Track(name: "Drums", colorIndex: 0)
            t.clips = [Clip(assetID: beat.id, start: 0, length: clipLength, loops: true)]
            c.tracks = [t]
        }
        return p
    }

    func testTransportLoopNeverDropsTheFirstHit() {
        for bpm in [124.0, 127.3, 140.0, 93.0] {
            let p = kickProject(bpm: bpm, clipLength: 4)
            let e = AudioEngine()
            e.update(project: p, root: p.mainCompositionID)
            e.setLoop(enabled: true, start: 0, end: 4)
            e.play(from: 0)
            let loops = 40
            let frames = Int(Double(loops) * 4 * 60 / bpm * 48000)
            let out = e.renderForTesting(frames: frames)
            XCTAssertEqual(onsets(out, sr: 48000), loops, "at \(bpm) BPM every loop should start with the kick")
        }
    }

    func testLoopedClipNeverDropsTheFirstHit() {
        for bpm in [124.0, 127.3, 140.0] {
            let p = kickProject(bpm: bpm, clipLength: 160)
            let (l, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 160, sampleRate: 44100)
            XCTAssertEqual(onsets(l, sr: 44100), 40, "at \(bpm) BPM each repeat of the clip should start with the kick")
        }
    }
}
