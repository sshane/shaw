import AVFoundation
import XCTest
@testable import ShawCore

/// The real instruments, kit, and percussion that come with Shaw (Resources/Sounds), and the
/// sampler playing a folder of recorded notes.
final class RecordedInstrumentTests: XCTestCase {
    let sr = 48000.0

    lazy var scratch: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ShawRecordedTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    func writeSine(_ hz: Double, to url: URL) throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let n = Int(sr)
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for i in 0..<n { buf.floatChannelData![0][i] = 0.5 * Float(sin(2 * .pi * hz * Double(i) / sr)) }
        try file.write(from: buf)
    }

    func frequency(_ x: [Float]) -> Double {
        var crossings: [Double] = []
        for i in 1000..<x.count where x[i - 1] < 0 && x[i] >= 0 {
            crossings.append(Double(i - 1) + Double(-x[i - 1] / (x[i] - x[i - 1])))
        }
        guard crossings.count > 2 else { return 0 }
        return Double(crossings.count - 1) / ((crossings.last! - crossings.first!) / sr)
    }

    /// One note through a sampler playing a recorded instrument.
    func play(_ zones: SampleZones, _ note: Int, params: [String: Double] = [:]) -> [Float] {
        let s = Sampler(sampleRate: sr)
        let p = SamplerParams.defs.resolve(params)
        let (sample, root) = SamplerSource.zones(zones).pick(note)
        s.noteOn(note, velocity: 1, params: p, sample: sample, recordedAt: root)
        var out = [Float](repeating: 0, count: 9600), r = out
        out.withUnsafeMutableBufferPointer { l in
            r.withUnsafeMutableBufferPointer { r in s.render(l.baseAddress!, r.baseAddress!, frames: 9600, params: p) }
        }
        return out
    }

    func testEachNotePlaysTheNearestRecording() throws {
        // A3 recorded as 057, A4 as 069.
        try writeSine(220, to: scratch.appendingPathComponent("057.wav"))
        try writeSine(440, to: scratch.appendingPathComponent("069.wav"))
        let zones = try XCTUnwrap(SampleLibrary.loadZones(scratch))
        XCTAssertEqual(zones.roots, [57, 69])
        XCTAssertEqual(frequency(play(zones, 69)), 440, accuracy: 2, "a recorded note plays as recorded")
        XCTAssertEqual(frequency(play(zones, 71)), 493.9, accuracy: 2, "B4 is A4 pitched up two semitones")
        XCTAssertEqual(frequency(play(zones, 59)), 246.9, accuracy: 2, "B3 comes from the A3 recording")
        XCTAssertEqual(frequency(play(zones, 69, params: ["root": 62])), 392, accuracy: 2, "Root Note transposes: D4 plays everything down two")
    }

    func testHalfwayTakesTheHigherRecording() throws {
        try writeSine(261.6, to: scratch.appendingPathComponent("060.wav"))
        try writeSine(329.6, to: scratch.appendingPathComponent("064.wav"))
        let zones = try XCTUnwrap(SampleLibrary.loadZones(scratch))
        XCTAssertEqual(zones.zone(for: 62).1, 64, "pitching down sounds more natural than pitching up")
        XCTAssertEqual(zones.zone(for: 30).1, 60)
        XCTAssertEqual(zones.zone(for: 100).1, 64)
    }

    func testShawsOwnSoundsHavePortablePaths() {
        let url = SampleLibrary.fileURL("shaw:Percussion/Shaker.caf")
        XCTAssertEqual(url.path, SampleLibrary.bundledRoot.appendingPathComponent("Percussion/Shaker.caf").path)
        XCTAssertEqual(SampleLibrary.portablePath(url.path), "shaw:Percussion/Shaker.caf", "a file inside the app is saved the portable way")
        XCTAssertEqual(SampleLibrary.portablePath("/Users/me/Samples/Kick.wav"), "/Users/me/Samples/Kick.wav")
        XCTAssertEqual(Instrument.sampleName("shaw:Percussion/Shaker.caf"), "Shaker")
    }

    func testRealInstrumentsShareTheSoundNames() {
        XCTAssertEqual(Set(RecordedInstruments.names).count, RecordedInstruments.names.count)
        for name in RecordedInstruments.names {
            XCTAssertFalse(SynthPresets.names.contains(name), "\(name) is also a synth preset")
            let inst = Instrument.preset(name)
            XCTAssertTrue(inst.isSampler, name)
            XCTAssertEqual(inst.sample, RecordedInstruments.named(name)?.path)
        }
        XCTAssertTrue(Instrument.preset("Pluck").isSynth)
    }

    func testEveryRealInstrumentIsThere() throws {
        for r in RecordedInstruments.all {
            XCTAssertTrue(SampleLibrary.shared.isFolder(r.path), "\(r.name): no folder at \(SampleLibrary.fileURL(r.path).path)")
            let zones = try XCTUnwrap(SampleLibrary.loadZones(SampleLibrary.fileURL(r.path)), r.name)
            XCTAssertGreaterThanOrEqual(zones.roots.count, 4, "\(r.name) needs recordings across its range")
            // No more than an octave between recordings, so nothing gets stretched too far.
            for (a, b) in zip(zones.roots, zones.roots.dropFirst()) {
                XCTAssertLessThanOrEqual(b - a, 12, "\(r.name): a gap from \(a) to \(b)")
            }
        }
    }

    func testTheAcousticKitAndPercussionAreThere() {
        for v in DrumKits.voices {
            let s = DrumKits.sample(kit: "acoustic", voice: v.id, sampleRate: sr)
            XCTAssertNotNil(s, "Acoustic Kit \(v.name)")
            if let s {
                let pk = (0..<s.frames).reduce(Float(0)) { max($0, abs(s.l[$1]), abs(s.r[$1])) }
                XCTAssertLessThanOrEqual(pk, 0.95, "\(v.name) never clips")
                XCTAssertGreaterThan(pk, 0.05, "\(v.name) isn't silent")
            }
        }
        let percussion = (try? FileManager.default.contentsOfDirectory(atPath: SampleLibrary.fileURL("shaw:Percussion").path)) ?? []
        XCTAssertGreaterThanOrEqual(percussion.filter { $0.hasSuffix(".caf") }.count, 8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: SampleLibrary.fileURL("shaw:CREDITS.txt").path), "the recordings say where they're from")
    }

    func testEveryRealInstrumentPlaysAChord() {
        for name in RecordedInstruments.names {
            var p = Project()
            let chord = [60, 64, 67].map { Note(pitch: $0, start: 0, length: 2, velocity: 0.8) }
            let pat = Asset(name: name, colorIndex: 1, content: .notes(NotePattern(length: 4, notes: chord, instrument: .preset(name))))
            p.assets.append(pat)
            p.updateComposition(p.mainCompositionID) { c in
                var t = Track(name: name, colorIndex: 1)
                t.clips = [Clip(assetID: pat.id, start: 0, length: 4)]
                c.tracks = [t]
            }
            let (l, r) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 2, sampleRate: sr)
            let pk = zip(l, r).reduce(Float(0)) { max($0, abs($1.0), abs($1.1)) }
            XCTAssertGreaterThan(pk, 0.05, "\(name): the chord is heard")
            XCTAssertLessThan(pk, 1, "\(name): and doesn't clip")
        }
    }
}
