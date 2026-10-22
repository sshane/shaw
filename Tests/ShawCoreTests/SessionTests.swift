import XCTest
@testable import ShawCore

final class SessionTests: XCTestCase {
    let sr = 48000.0

    /// One track with a kick on every beat in session slot 0 and nothing on the timeline.
    func makeProject(tracks: Int = 1) -> (Project, [UUID]) {
        var p = Project(bpm: 120)
        var d = DrumPattern(steps: 4, stepsPerBeat: 1)
        d.rows[0].steps = [1, 1, 1, 1]
        let beat = Asset(name: "Kicks", colorIndex: 0, content: .drums(d))
        p.assets.append(beat)
        var ids: [UUID] = []
        p.updateComposition(p.mainCompositionID) { c in
            c.length = 16
            for i in 0..<tracks {
                var t = Track(name: "T\(i)", colorIndex: 0)
                t.slots = [0: SessionClip(assetID: beat.id)]
                ids.append(t.id)
                c.tracks.append(t)
            }
        }
        return (p, ids)
    }

    func beatRMS(_ x: [Float], beat: Int) -> Float {
        let fpb = Int(sr * 0.5) // 120 BPM
        let s = beat * fpb, e = min(x.count, s + fpb / 4)
        guard e > s else { return 0 }
        return sqrt(x[s..<e].reduce(0) { $0 + $1 * $1 } / Float(e - s))
    }

    func testLaunchedClipKeepsPlayingAcrossLoopWrap() {
        let (p, ids) = makeProject()
        let e = AudioEngine()
        e.update(project: p, root: p.mainCompositionID)
        e.setLoop(enabled: true, start: 0, end: 4)
        e.seek(2)
        e.launch(track: ids[0], scene: 0) // stopped → starts now at beat 2
        let out = e.renderForTesting(frames: Int(sr * 0.5 * 8)) // 8 beats, wraps twice
        for b in 0..<8 { XCTAssertGreaterThan(beatRMS(out, beat: b), 0.02, "beat \(b) should have a kick") }
    }

    func testQueuedLaunchFiresWhenLoopEndsOnBar() {
        let (p, ids) = makeProject()
        let e = AudioEngine()
        e.update(project: p, root: p.mainCompositionID)
        e.setLoop(enabled: true, start: 0, end: 4)
        e.play(from: 1)
        _ = e.renderForTesting(frames: 512)
        e.launch(track: ids[0], scene: 0) // queued for the next bar on the session clock
        let out = e.renderForTesting(frames: Int(sr * 0.5 * 8))
        XCTAssertNil(e.sessionStateForTesting(ids[0])?.queued, "queued launch should have fired")
        XCTAssertGreaterThan(beatRMS(out, beat: 5), 0.02)
    }

    func testSceneLaunchWhileStoppedStartsTogether() {
        let (p, ids) = makeProject(tracks: 3)
        let e = AudioEngine()
        e.update(project: p, root: p.mainCompositionID)
        e.seek(1.3)
        e.launchScene(0, tracks: Dictionary(uniqueKeysWithValues: ids.map { ($0, true) }))
        let infos = ids.compactMap { e.sessionStateForTesting($0) }
        XCTAssertEqual(infos.count, 3)
        XCTAssertTrue(infos.allSatisfy { $0.playing == 0 && $0.queued == nil })
        XCTAssertEqual(Set(infos.map(\.launchBeat)).count, 1, "all tracks share one launch beat")
    }

    func testRemovingPlayingSlotReleasesTrack() {
        var (p, ids) = makeProject()
        let e = AudioEngine()
        e.update(project: p, root: p.mainCompositionID)
        e.launch(track: ids[0], scene: 0)
        _ = e.renderForTesting(frames: 1024)
        p.updateComposition(p.mainCompositionID) { $0.tracks[0].slots = [:] }
        e.update(project: p, root: p.mainCompositionID)
        _ = e.renderForTesting(frames: 1024)
        XCTAssertNil(e.sessionStateForTesting(ids[0]))
    }
}

final class CountInTests: XCTestCase {
    /// A count-in clicks for its beats with the playhead waiting, then playback starts right on time.
    func testCountInHoldsThePlayheadThenPlays() {
        let e = AudioEngine()
        let p = Project()
        e.update(project: p, root: p.mainCompositionID)
        e.play(from: 4, countIn: 4) // a bar at 120 BPM: two seconds
        _ = e.renderForTesting(frames: 48000) // one second in
        var s = e.snapshot()
        XCTAssertTrue(s.countingIn)
        XCTAssertFalse(s.playing)
        XCTAssertEqual(s.position, 4, accuracy: 1e-9, "the playhead waits")
        _ = e.renderForTesting(frames: 48000 + 4800) // a tenth of a second past the count-in
        s = e.snapshot()
        XCTAssertFalse(s.countingIn)
        XCTAssertTrue(s.playing)
        XCTAssertEqual(s.position, 4.2, accuracy: 0.01, "playback started the moment the count-in ended")
        e.stop()
        XCTAssertFalse(e.snapshot().countingIn)
    }
}
