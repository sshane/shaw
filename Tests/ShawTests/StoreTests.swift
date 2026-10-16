import AVFoundation
import XCTest
import ShawCore
@testable import Shaw

final class StoreTests: XCTestCase {
    func makeStore() -> Store { Store(project: DemoProject.make(), headless: true) }

    func rms(_ x: [Float]) -> Float { sqrt(x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))) }

    func testDemoProjectIsValid() {
        let s = makeStore()
        XCTAssertNotNil(s.activeComp)
        XCTAssertGreaterThan(s.project.usageCount(of: s.project.assets.first { $0.name == "Drop" }!.id), 1, "Drop should be linked in several places")
        let (l, _) = OfflineRenderer.renderToMemory(project: s.project, composition: s.project.mainCompositionID, beats: 24)
        XCTAssertGreaterThan(rms(l), 0.01)
        XCTAssertLessThan(l.map(abs).max() ?? 0, 4)
    }

    /// Renders the whole demo song and checks each section is audible and nothing clips hard.
    func testDemoSongMix() {
        let s = makeStore()
        let main = s.project.mainCompositionID
        let (l, r) = OfflineRenderer.renderToMemory(project: s.project, composition: main, beats: 288)
        let fpb = 48000.0 * 60 / s.project.bpm
        let sections: [(String, Double, Double)] = [("Intro", 0, 32), ("Build", 32, 64), ("Drop", 64, 128), ("Breakdown", 128, 160),
                                                     ("Build 2", 160, 192), ("Drop 2", 192, 256), ("Outro", 256, 288)]
        for (name, b0, b1) in sections {
            let seg = Array(l[Int(b0 * fpb)..<Int(b1 * fpb)])
            let rr = Array(r[Int(b0 * fpb)..<Int(b1 * fpb)])
            let level = 20 * log10(Double(max(rms(seg), 1e-9)))
            let peak = max(seg.map(abs).max() ?? 0, rr.map(abs).max() ?? 0)
            print(String(format: "MIX %-10@ rms %6.1f dBFS  peak %.2f", name as NSString, level, peak))
            XCTAssertGreaterThan(level, -40, "\(name) is nearly silent")
            XCTAssertLessThan(peak, 1.5, "\(name) clips")
        }
    }

    func testCompositionCannotContainItself() {
        let s = makeStore()
        let main = s.project.mainCompositionID
        XCTAssertNil(s.addClip(asset: main, at: 0, track: nil))
        let drop = s.project.assets.first { $0.name == "Drop" }!.id
        s.openComposition(drop)
        XCTAssertNil(s.addClip(asset: main, at: 0, track: nil), "Main contains Drop, so Drop can't contain Main")
    }

    func testMoveClipAcrossTracksAndUndo() {
        let s = makeStore()
        let comp = s.activeComp!
        let clip = comp.tracks[0].clips[0]
        let origin = s.project
        s.moveClips(origin, ids: [clip.id], deltaBeats: 4, deltaTracks: 1)
        s.endGesture()
        let moved = s.activeComp!
        XCTAssertFalse(moved.tracks[0].clips.contains { $0.id == clip.id })
        XCTAssertEqual(moved.tracks[1].clips.first { $0.id == clip.id }?.start, clip.start + 4)
        s.undo()
        XCTAssertEqual(s.project, origin, "one drag should be one undo step")
    }

    func testDuplicateStaysLinked() {
        let s = makeStore()
        let drop = s.activeComp!.tracks[2].clips[0]
        let before = s.activeComp!.tracks[2].clips.count
        s.selectedClips = [drop.id]
        s.duplicateSelectedClips()
        let copies = s.activeComp!.tracks[2].clips.filter { $0.assetID == drop.assetID }
        XCTAssertEqual(copies.count, before + 1)
        XCTAssertTrue(copies.contains { $0.start == drop.end })
    }

    func testMakeUniqueBreaksLink() {
        let s = makeStore()
        let clip = s.activeComp!.tracks[2].clips[0]
        let before = s.project.usageCount(of: clip.assetID)
        s.makeUnique(clip.id)
        let now = s.clip(clip.id)!
        XCTAssertNotEqual(now.assetID, clip.assetID)
        XCTAssertEqual(s.project.usageCount(of: clip.assetID), before - 1)
        XCTAssertEqual(s.project.usageCount(of: now.assetID), 1)
    }

    func testPrecomposeSoundsTheSame() {
        let s = makeStore()
        let main = s.project.mainCompositionID
        let comp = s.activeComp!
        let ids = Set(comp.tracks[0].clips.map(\.id) + comp.tracks[1].clips.map(\.id))
        let (before, _) = OfflineRenderer.renderToMemory(project: s.project, composition: main, beats: 16)
        s.selectedClips = ids
        s.precomposeSelection()
        let after = s.activeComp!
        XCTAssertEqual(after.tracks.count, comp.tracks.count + 1)
        XCTAssertTrue(after.tracks[1].clips.isEmpty && after.tracks[2].clips.isEmpty)
        let (rendered, _) = OfflineRenderer.renderToMemory(project: s.project, composition: main, beats: 16)
        var maxDiff: Float = 0
        for i in 0..<min(before.count, rendered.count) { maxDiff = max(maxDiff, abs(before[i] - rendered[i])) }
        // Synth unison phases are randomized per instance, so allow a small difference for pads.
        XCTAssertLessThan(abs(rms(before) - rms(rendered)) / max(rms(before), 1e-6), 0.1, "precomp should sound like the original")
    }

    func testDeleteAssetRemovesClipsEverywhere() {
        let s = makeStore()
        let hats = s.project.assets.first { $0.name == "Shuffle Hats" }!.id
        s.deleteAssets([hats])
        XCTAssertNil(s.project.asset(hats))
        XCTAssertEqual(s.project.usageCount(of: hats), 0)
        for a in s.project.assets {
            if case .composition(let c) = a.content {
                XCTAssertFalse(c.tracks.flatMap(\.clips).contains { $0.assetID == hats })
            }
        }
    }

    func testSplitClip() {
        let s = makeStore()
        let clip = s.activeComp!.tracks[0].clips.min { $0.start < $1.start }! // Intro, 0..32
        let before = s.activeComp!.tracks[0].clips.count
        s.selectedClips = [clip.id]
        s.splitSelectedClips(at: 10)
        let clips = s.activeComp!.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.count, before + 1)
        XCTAssertEqual(clips[0].length, 10)
        XCTAssertEqual(clips[1].start, 10)
        XCTAssertEqual(clips[1].offset, 10)
    }

    func testEffectEditCoalescesIntoOneUndo() {
        let s = makeStore()
        let host = EffectHost.composition(s.activeCompID)
        s.addEffect("reverb", to: host)
        let afterAdd = s.project
        for v in stride(from: 0.1, to: 0.9, by: 0.1) {
            s.updateEffects(host, live: true) { $0[0].params["mix"] = v }
        }
        s.endGesture()
        s.undo()
        XCTAssertEqual(s.project, afterAdd)
    }

    func testWorkspaceMovePanel() {
        var w = Workspace.standard
        w.move(.mixer, to: .right)
        XCTAssertEqual(w.location(of: .mixer), .right)
        XCTAssertEqual(w.slot(.right).active, .mixer)
        XCTAssertFalse(w.slot(.bottom).tabs.contains(.mixer))
    }

    func testClipSegments() {
        let segs = clipSegments(offset: 0, length: 10, loops: true, sourceLength: 4)
        XCTAssertEqual(segs.count, 3)
        XCTAssertTrue(segs[1].loopStart)
        let trimmed = clipSegments(offset: 0, length: 10, loops: false, sourceLength: 4)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertTrue(trimmed[1].empty)
    }
}

final class ExportTests: XCTestCase {
    func testExportDemoSongToWav() throws {
        let p = DemoProject.make()
        let dir = ProcessInfo.processInfo.environment["SHAW_EXPORT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("First Light.wav")
        try? FileManager.default.removeItem(at: url)
        try OfflineRenderer.export(project: p, composition: p.mainCompositionID, to: url)
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertEqual(seconds, 288 * 60 / p.bpm + 2, accuracy: 0.05)
        XCTAssertEqual(file.fileFormat.channelCount, 2)
    }
}
