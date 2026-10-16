import XCTest
@testable import ShawCore

final class PerfTests: XCTestCase {
    func testRealtimeFactor() {
        var p = Project()
        var assets: [Asset] = []
        for i in 0..<8 {
            var pat = NotePattern(length: 16, instrument: .preset("Supersaw"))
            for b in 0..<4 { for k in [0, 4, 7] { pat.notes.append(Note(pitch: 48 + k + i, start: Double(b * 4), length: 4)) } }
            assets.append(Asset(name: "P\(i)", colorIndex: i, content: .notes(pat)))
        }
        p.assets += assets
        p.updateComposition(p.mainCompositionID) { c in
            c.tracks = assets.map { a in
                var t = Track(name: a.name, colorIndex: 0)
                t.clips = [Clip(assetID: a.id, start: 0, length: 16)]
                t.effects = [EffectRegistry.descriptor("reverb")!.makeEffect(), EffectRegistry.descriptor("delay")!.makeEffect()]
                return t
            }
        }
        let start = Date()
        _ = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 16, sampleRate: 48000)
        let elapsed = Date().timeIntervalSince(start)
        let audio = 16 * 60 / 120.0
        print("PERF: rendered \(audio)s of 8x(3-note 7-voice supersaw + reverb + delay) in \(elapsed)s, \(audio / elapsed)x realtime")
    }
}
