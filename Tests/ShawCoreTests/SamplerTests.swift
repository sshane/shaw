import AVFoundation
import XCTest
@testable import ShawCore

final class SamplerTests: XCTestCase {
    let sr = 48000.0

    /// A scratch folder for this test run's audio files (removed afterwards).
    lazy var scratch: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ShawSamplerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    func sine(_ hz: Double, seconds: Double, amp: Float = 0.5, rate: Double = 48000) -> [Float] {
        (0..<Int(seconds * rate)).map { amp * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    /// Writes a mono 32-bit float WAV into the scratch folder.
    func writeWav(_ samples: [Float], name: String, rate: Double = 48000) throws -> String {
        let url = scratch.appendingPathComponent(name)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        buf.floatChannelData![0].update(from: samples, count: samples.count)
        try file.write(from: buf)
        return url.path
    }

    /// Frequency from upward zero crossings over the given range.
    func frequency(_ x: [Float], from: Int, to: Int) -> Double {
        var crossings: [Double] = []
        for i in max(1, from)..<min(x.count, to) where x[i - 1] < 0 && x[i] >= 0 {
            crossings.append(Double(i - 1) + Double(-x[i - 1] / (x[i] - x[i - 1])))
        }
        guard crossings.count > 2 else { return 0 }
        return Double(crossings.count - 1) / ((crossings.last! - crossings.first!) / sr)
    }

    func rms(_ x: [Float], from: Int, to: Int) -> Float {
        let s = max(0, from), e = min(x.count, to)
        guard e > s else { return 0 }
        var acc: Float = 0
        for i in s..<e { acc += x[i] * x[i] }
        return sqrt(acc / Float(e - s))
    }

    /// Render a sampler directly: notes are (pitch, start s, end s).
    func play(_ sample: MipSample, _ notes: [(Int, Double, Double)], params: [String: Double] = [:], seconds: Double) -> [Float] {
        let s = Sampler(sampleRate: sr)
        let p = SamplerParams.defs.resolve(params)
        let total = Int(seconds * sr)
        var out = [Float](repeating: 0, count: total)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 256); defer { l.deallocate() }
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 256); defer { r.deallocate() }
        var f = 0
        while f < total {
            let n = min(256, total - f)
            for (pitch, on, off) in notes {
                let a = Int(on * sr), b = Int(off * sr)
                if a >= f && a < f + n { s.noteOn(pitch, velocity: 1, params: p, sample: sample) }
                if b >= f && b < f + n { s.noteOff(pitch) }
            }
            l.initialize(repeating: 0, count: n); r.initialize(repeating: 0, count: n)
            s.render(l, r, frames: n, params: p)
            for i in 0..<n { out[f + i] = l[i] }
            f += n
        }
        return out
    }

    // MARK: Pitch

    func testPitchesUpAnOctave() {
        let sample = MipSample(SampleData(left: sine(440, seconds: 1), sampleRate: sr))
        let up = play(sample, [(72, 0, 0.8)], seconds: 0.6)
        XCTAssertEqual(frequency(up, from: 2000, to: 26000), 880, accuracy: 2, "an octave up doubles the frequency")
        let root = play(sample, [(60, 0, 0.8)], seconds: 0.6)
        XCTAssertEqual(frequency(root, from: 2000, to: 26000), 440, accuracy: 1)
        let down = play(sample, [(48, 0, 0.8)], seconds: 0.6)
        XCTAssertEqual(frequency(down, from: 2000, to: 26000), 220, accuracy: 1)
        // An octave up still sounds as loud as the original (the half-rate copy is flat there).
        XCTAssertEqual(rms(up, from: 2000, to: 20000), rms(root, from: 2000, to: 20000), accuracy: 0.02)
    }

    func testRootNoteAndFileSampleRateSetThePitch() {
        // A 44.1 kHz file still plays in tune at 48 kHz, and Root Note A4 plays it as is on A4.
        let sample = MipSample(SampleData(left: sine(440, seconds: 1, rate: 44100), sampleRate: 44100))
        let out = play(sample, [(69, 0, 0.8)], params: ["root": 69], seconds: 0.6)
        XCTAssertEqual(frequency(out, from: 2000, to: 26000), 440, accuracy: 1)
        let fine = play(sample, [(69, 0, 0.8)], params: ["root": 69, "fine": 50], seconds: 0.6)
        XCTAssertEqual(frequency(fine, from: 2000, to: 26000), 440 * pow(2, 0.5 / 12), accuracy: 1.5)
    }

    func testPitchingFarUpDoesNotAlias() {
        // 6 kHz pitched up 31 semitones would be 36 kHz: past Nyquist, so it should vanish,
        // not fold back down as a loud 12 kHz whistle.
        let sample = MipSample(SampleData(left: sine(6000, seconds: 1), sampleRate: sr))
        let high = play(sample, [(91, 0, 0.8)], seconds: 0.4)
        XCTAssertLessThan(rms(high, from: 2000, to: 18000), 0.005)
        // 2 kHz up an octave is 4 kHz and must come through clearly.
        let ok = MipSample(SampleData(left: sine(2000, seconds: 1), sampleRate: sr))
        let fine = play(ok, [(72, 0, 0.8)], seconds: 0.4)
        XCTAssertGreaterThan(rms(fine, from: 2000, to: 18000), 0.3)
        XCTAssertEqual(frequency(fine, from: 2000, to: 18000), 4000, accuracy: 10)
    }

    func testStereoSamplesKeepTheirSides() {
        // Left has the tone, right is silent, and that holds an octave up (read from a half-rate copy).
        let left = sine(440, seconds: 1), right = [Float](repeating: 0, count: left.count)
        let sample = MipSample(SampleData(left: left, right: right, sampleRate: sr))
        let s = Sampler(sampleRate: sr)
        let p = SamplerParams.defs.resolve([:])
        s.noteOn(72, velocity: 1, params: p, sample: sample)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 4800); defer { l.deallocate() }
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 4800); defer { r.deallocate() }
        l.initialize(repeating: 0, count: 4800); r.initialize(repeating: 0, count: 4800)
        s.render(l, r, frames: 4800, params: p)
        let outL = Array(UnsafeBufferPointer(start: l, count: 4800)), outR = Array(UnsafeBufferPointer(start: r, count: 4800))
        XCTAssertGreaterThan(rms(outL, from: 500, to: 4800), 0.3)
        XCTAssertLessThan(rms(outR, from: 500, to: 4800), 0.0001)
    }

    // MARK: Modes

    func testOneShotPlaysTheWholeSampleAndNoteLengthStopsAtRelease() {
        let sample = MipSample(SampleData(left: sine(220, seconds: 1), sampleRate: sr))
        // A short note: 0.1 s.
        let oneShot = play(sample, [(60, 0, 0.1)], params: ["playmode": 1], seconds: 1.2)
        let gated = play(sample, [(60, 0, 0.1)], params: ["playmode": 0, "r": 0.05], seconds: 1.2)
        XCTAssertGreaterThan(rms(oneShot, from: Int(0.7 * sr), to: Int(0.9 * sr)), 0.2, "One-Shot keeps playing after the note ends")
        XCTAssertLessThan(rms(oneShot, from: Int(1.05 * sr), to: Int(1.2 * sr)), 0.0001, "and stops at the end of the sample")
        XCTAssertGreaterThan(rms(gated, from: Int(0.02 * sr), to: Int(0.09 * sr)), 0.2)
        XCTAssertLessThan(rms(gated, from: Int(0.3 * sr), to: Int(0.9 * sr)), 0.0005, "Note Length stops after the release")
    }

    func testLoopSustainsWhileHeld() {
        let sample = MipSample(SampleData(left: sine(220, seconds: 0.5), sampleRate: sr))
        let looped = play(sample, [(60, 0, 1.5)], params: ["playmode": 0, "loop": 1, "loopstart": 0.2, "loopend": 0.8], seconds: 1.8)
        XCTAssertGreaterThan(rms(looped, from: Int(1.0 * sr), to: Int(1.4 * sr)), 0.2, "loops past the sample's end while held")
        XCTAssertLessThan(rms(looped, from: Int(1.75 * sr), to: Int(1.8 * sr)), 0.001, "and lets go on release")
    }

    func testStartSkipsIntoTheSample() {
        // First half silent, second half a tone: Start at 50% plays the tone right away.
        let half = [Float](repeating: 0, count: 24000) + sine(440, seconds: 0.5)
        let sample = MipSample(SampleData(left: half, sampleRate: sr))
        let fromStart = play(sample, [(60, 0, 0.9)], params: ["playmode": 1], seconds: 0.2)
        let skipped = play(sample, [(60, 0, 0.9)], params: ["playmode": 1, "start": 0.5], seconds: 0.2)
        XCTAssertLessThan(rms(fromStart, from: 0, to: 9000), 0.001)
        XCTAssertGreaterThan(rms(skipped, from: 500, to: 9000), 0.2)
    }

    // MARK: Voices

    func testVoiceStealingFadesInsteadOfClicking() {
        // A flat (DC) sample: any hard cut shows up as a jump between neighbouring samples.
        let sample = MipSample(SampleData(left: [Float](repeating: 0.5, count: Int(sr * 3)), sampleRate: sr))
        // 18 held notes, 10 ms apart: the 17th and 18th have to steal.
        let notes = (0..<18).map { (40 + $0 * 2, Double($0) * 0.01, 2.5) }
        let out = play(sample, notes, params: ["playmode": 0], seconds: 0.5)
        var maxJump: Float = 0
        for i in 1..<out.count { maxJump = max(maxJump, abs(out[i] - out[i - 1])) }
        XCTAssertLessThan(maxJump, 0.05, "voices fade in and out over milliseconds; a cut would jump by 0.5")
        // Never more than 16 at once.
        XCTAssertEqual(out[Int(0.4 * sr)], 16 * 0.5, accuracy: 0.05)
    }

    func testRetriggeringAKeyFadesTheOldNote() {
        let sample = MipSample(SampleData(left: [Float](repeating: 0.5, count: Int(sr * 3)), sampleRate: sr))
        let out = play(sample, [(60, 0, 2), (60, 0.1, 2)], params: ["playmode": 1], seconds: 0.3)
        XCTAssertEqual(out[Int(0.25 * sr)], 0.5, accuracy: 0.01, "the same key doesn't stack up")
        var maxJump: Float = 0
        for i in 1..<out.count { maxJump = max(maxJump, abs(out[i] - out[i - 1])) }
        XCTAssertLessThan(maxJump, 0.05)
    }

    // MARK: Through the project

    func samplerProject(path: String, notes: [Note], params: [String: Double] = [:]) -> Project {
        var p = Project()
        var inst = Instrument.sampler(path)
        for (k, v) in params { inst.params[k] = v }
        let pat = Asset(name: "Chop", colorIndex: 1, content: .notes(NotePattern(length: 4, notes: notes, instrument: inst)))
        p.assets.append(pat)
        p.updateComposition(p.mainCompositionID) { c in
            var t = Track(name: "Chop", colorIndex: 1)
            t.clips = [Clip(assetID: pat.id, start: 0, length: 4)]
            c.tracks = [t]
        }
        return p
    }

    func testSamplerPatternPlaysThroughTheEngine() throws {
        let path = try writeWav(sine(440, seconds: 1), name: "tone.wav")
        // 120 bpm: one beat is 0.5 s. A one-octave-up note on beat 1.
        let p = samplerProject(path: path, notes: [Note(pitch: 72, start: 1, length: 0.25, velocity: 1)])
        let (l, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 3, sampleRate: sr)
        XCTAssertLessThan(rms(l, from: 0, to: Int(0.45 * sr)), 0.0001, "silent before the note")
        XCTAssertEqual(frequency(l, from: Int(0.55 * sr), to: Int(0.9 * sr)), 880, accuracy: 2)
        // Short file, so it defaults to One-Shot: it keeps going past the 1/16 note.
        XCTAssertGreaterThan(rms(l, from: Int(0.8 * sr), to: Int(0.95 * sr)), 0.1)
    }

    func testCustomKitSampleReplacesOneSound() throws {
        let path = try writeWav(sine(1000, seconds: 0.3, amp: 0.7), name: "mykick.wav")
        var p = Project()
        var inst = Instrument.kit("trap")
        inst.kitSamples = ["kick": path]
        let notes = [Note(pitch: DrumKits.pitch(of: "kick"), start: 0, length: 0.25, velocity: 1),
                     Note(pitch: DrumKits.pitch(of: "snare"), start: 1, length: 0.25, velocity: 1)]
        let pat = Asset(name: "Beat", colorIndex: 1, content: .notes(NotePattern(length: 4, notes: notes, instrument: inst)))
        p.assets.append(pat)
        p.updateComposition(p.mainCompositionID) { c in
            var t = Track(name: "Beat", colorIndex: 1)
            t.clips = [Clip(assetID: pat.id, start: 0, length: 4)]
            c.tracks = [t]
        }
        let (l, _) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: 2, sampleRate: sr)
        XCTAssertEqual(frequency(l, from: 1000, to: Int(0.25 * sr)), 1000, accuracy: 5, "the kick row plays your file")
        XCTAssertGreaterThan(rms(l, from: Int(0.5 * sr), to: Int(0.6 * sr)), 0.01, "the snare is still the built-in one")
    }

    // MARK: Previews

    func testPreviewsPlaySamplerNotesAndFiles() throws {
        let path = try writeWav(sine(440, seconds: 1), name: "preview.wav")
        XCTAssertNotNil(SampleLibrary.shared.mipmappedSync(path))
        let engine = AudioEngine()
        engine.previewNoteOn(60, velocity: 1, instrument: .sampler(path))
        let notes = engine.renderForTesting(frames: 9600)
        XCTAssertGreaterThan(rms(notes, from: 1000, to: 9600), 0.1, "playing a sampler pattern on the keyboard")
        engine.previewAllOff()

        let done = expectation(description: "loaded")
        SampleLibrary.shared.loadForPreview(path) { m in
            XCTAssertNotNil(m)
            if let m { engine.previewSample(m) }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        _ = engine.renderForTesting(frames: 48000) // let the keyboard note's release die away
        engine.previewSample(SampleLibrary.shared.mipmappedSync(path)!)
        let file = engine.renderForTesting(frames: 9600)
        XCTAssertEqual(frequency(file, from: 1000, to: 9600), 440, accuracy: 2, "clicking a file in the browser plays it as is")
    }

    func testPreviewOfCustomKitSound() throws {
        let path = try writeWav(sine(1000, seconds: 0.3, amp: 0.7), name: "mysnare.wav")
        XCTAssertNotNil(SampleLibrary.shared.loadSync(path))
        let engine = AudioEngine()
        var kit = Instrument.kit("trap")
        kit.kitSamples = ["snare": path]
        engine.previewNoteOn(DrumKits.pitch(of: "snare"), velocity: 1, instrument: kit)
        let out = engine.renderForTesting(frames: 9600)
        XCTAssertEqual(frequency(out, from: 500, to: 9600), 1000, accuracy: 5)
    }

    // MARK: Saving

    func testProjectRoundTripsSamplerAndCustomKit() throws {
        var p = samplerProject(path: "/Samples/Vox Chop.wav", notes: [Note(pitch: 64, start: 0, length: 1)],
                               params: ["root": 62, "start": 0.25, "loop": 1, "cutoff": 3000])
        var kit = Instrument.kit("house")
        kit.kitSamples = ["kick": "/Samples/Kick 1.wav", "chat": "/Samples/Hat.aif"]
        p.assets.append(Asset(name: "Beat", colorIndex: 2, content: .notes(NotePattern(length: 4, instrument: kit))))
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(back, p)
        guard case .notes(let s)? = back.assets.first(where: { $0.name == "Chop" })?.content else { return XCTFail() }
        XCTAssertTrue(s.instrument.isSampler)
        XCTAssertEqual(s.instrument.sample, "/Samples/Vox Chop.wav")
        XCTAssertEqual(s.instrument.preset, "Vox Chop")
        XCTAssertEqual(s.instrument.params["root"], 62)
        guard case .notes(let k)? = back.assets.last?.content else { return XCTFail() }
        XCTAssertEqual(k.instrument.kitSamples?["chat"], "/Samples/Hat.aif")
        XCTAssertEqual(k.instrument.displayName, "House 909 (custom)")
        XCTAssertEqual(back.instrumentSamplePaths, ["/Samples/Vox Chop.wav", "/Samples/Kick 1.wav", "/Samples/Hat.aif"])
    }

    func testOldProjectsStillDecode() throws {
        // Instruments as projects saved them before the sampler existed.
        let synth = try JSONDecoder().decode(Instrument.self, from: Data(#"{"preset":"Pluck","params":{"cutoff":900}}"#.utf8))
        XCTAssertTrue(synth.isSynth)
        XCTAssertNil(synth.sample)
        XCTAssertNil(synth.kitSamples)
        XCTAssertEqual(synth.params["cutoff"], 900)
        let kit = try JSONDecoder().decode(Instrument.self, from: Data(#"{"preset":"Trap 808","params":{},"kit":"trap"}"#.utf8))
        XCTAssertTrue(kit.isDrumKit)
        XCTAssertFalse(kit.hasCustomKitSamples)
        XCTAssertEqual(kit.displayName, "Trap 808")
        // New fields stay out of the file unless they're used, so older Shaw builds can still read it.
        let json = String(data: try JSONEncoder().encode(Instrument.preset("Pluck")), encoding: .utf8)!
        XCTAssertFalse(json.contains("sample"))
        XCTAssertFalse(json.contains("kitSamples"))
        // A whole project with no new fields decodes.
        var p = Project()
        p.assets.append(Asset(name: "Lead", colorIndex: 1, content: .notes(NotePattern(instrument: .preset("Lead")))))
        let old = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: old), p)
    }

    func testShortSamplesDefaultToOneShot() {
        XCTAssertEqual(Instrument.sampler("/a.wav", duration: 0.4).params["playmode"], 1)
        XCTAssertEqual(Instrument.sampler("/pad.wav", duration: 8).params["playmode"], 0)
        XCTAssertEqual(ParamDef.parseNote("C4"), 60)
        XCTAssertEqual(ParamDef.parseNote("a#3"), 58)
        XCTAssertEqual(ParamDef.parseNote("Db2"), 37)
        XCTAssertEqual(ParamDef.noteName(60), "C4")
    }
}
