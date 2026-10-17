import AVFoundation
import XCTest
@testable import ShawCore
@testable import Shaw

final class SamplerWorkflowTests: XCTestCase {
    func emptyStore() -> Store { Store(project: DemoProject.empty(), headless: true) }

    /// A scratch folder for this test's audio files (removed afterwards).
    lazy var scratch: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ShawSamplerWorkflow-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    /// A short tone as a WAV file, at `name` inside the scratch folder (subfolders allowed).
    @discardableResult
    func wav(_ name: String, seconds: Double = 0.3) throws -> String {
        let url = scratch.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let n = Int(seconds * 48000)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for i in 0..<n { buf.floatChannelData![0][i] = 0.5 * Float(sin(2 * .pi * 440 * Double(i) / 48000)) }
        try file.write(from: buf)
        return url.path
    }

    func pattern(_ s: Store, _ id: AssetID) -> NotePattern? {
        if case .notes(let p)? = s.project.asset(id)?.content { return p }
        return nil
    }

    func testDoubleClickingASampleAddsASamplerLayer() throws {
        let s = emptyStore()
        let path = try wav("Vox Chop.wav")
        let id = try XCTUnwrap(s.addSampler(path))
        let comp = s.activeComp!
        XCTAssertEqual(comp.tracks.count, 1)
        XCTAssertEqual(comp.tracks[0].name, "Vox Chop")
        XCTAssertEqual(comp.tracks[0].clips.first?.assetID, id)
        XCTAssertEqual(s.pianoRollAsset, id, "opens in the piano roll")
        XCTAssertEqual(s.project.asset(id)?.name, "Vox Chop")
        let p = try XCTUnwrap(pattern(s, id))
        XCTAssertTrue(p.instrument.isSampler)
        XCTAssertEqual(p.instrument.sample, path)
        XCTAssertEqual(p.instrument.params["playmode"], 1, "a short chop plays whole")
        XCTAssertNil(s.instrumentStatus(id), "synth-only save and revert do not apply")
    }

    func testDroppingAFileTurnsAPatternIntoASamplerAndKeepsNotes() throws {
        let s = emptyStore()
        s.addInstrument(.synth("Pluck"))
        let clip = s.activeComp!.tracks[0].clips[0]
        s.edit { $0.updateNotes(clip.assetID) { $0.notes = [Note(pitch: 62, start: 0, length: 1)] } }
        let path = try wav("Pad Long.wav", seconds: 3)
        XCTAssertTrue(s.useSample(path, forPattern: clip.assetID))
        let p = try XCTUnwrap(pattern(s, clip.assetID))
        XCTAssertTrue(p.instrument.isSampler)
        XCTAssertEqual(p.notes.count, 1)
        XCTAssertEqual(p.instrument.params["playmode"], 0, "a long sound follows the note length")
        XCTAssertEqual(s.project.asset(clip.assetID)?.name, "Pad Long", "auto names follow the sound")
        XCTAssertEqual(s.activeComp!.tracks[0].name, "Pad Long")

        // Swapping the file keeps your settings.
        s.edit { $0.updateNotes(clip.assetID) { $0.instrument.params["cutoff"] = 2000; $0.instrument.params["start"] = 0.4 } }
        let other = try wav("Other.wav", seconds: 3)
        XCTAssertTrue(s.useSample(other, forPattern: clip.assetID))
        let q = try XCTUnwrap(pattern(s, clip.assetID))
        XCTAssertEqual(q.instrument.sample, other)
        XCTAssertEqual(q.instrument.params["cutoff"], 2000)
        XCTAssertEqual(q.instrument.params["start"], 0, "where to start belongs to the old file")

        // And back to a synth.
        XCTAssertTrue(s.replaceInstrument(ofAsset: clip.assetID, with: .synth("Keys")))
        XCTAssertTrue(try XCTUnwrap(pattern(s, clip.assetID)).instrument.isSynth)
    }

    func testDrumSoundsFromYourOwnFiles() throws {
        let s = emptyStore()
        s.addInstrument(.kit("trap"))
        let id = s.activeComp!.tracks[0].clips[0].assetID
        let kick = try wav("Kick.wav"), hat = try wav("Hat.wav"), snare = try wav("Snare.wav")
        s.setKitSample(kick, voice: "kick", pattern: id)
        var p = try XCTUnwrap(pattern(s, id))
        XCTAssertEqual(p.instrument.kitSamples, ["kick": kick])
        XCTAssertEqual(p.instrument.displayName, "Trap 808 (custom)")

        // Trying another kit keeps your sounds.
        XCTAssertTrue(s.replaceInstrument(ofAsset: id, with: .kit("house")))
        p = try XCTUnwrap(pattern(s, id))
        XCTAssertEqual(p.instrument.kit, "house")
        XCTAssertEqual(p.instrument.kitSamples, ["kick": kick])

        // Several files dropped on the snare fill it and the sounds below it.
        s.setKitSamples([snare, hat], startingAt: "snare", pattern: id)
        p = try XCTUnwrap(pattern(s, id))
        XCTAssertEqual(p.instrument.kitSamples?["snare"], snare)
        XCTAssertEqual(p.instrument.kitSamples?["kick"], hat, "the next row down is the kick")

        // Back to the built-in sounds.
        s.setKitSample(nil, voice: "kick", pattern: id)
        s.setKitSample(nil, voice: "snare", pattern: id)
        p = try XCTUnwrap(pattern(s, id))
        XCTAssertNil(p.instrument.kitSamples)
        XCTAssertEqual(p.instrument.displayName, "House 909")
        s.undo()
        XCTAssertEqual(try XCTUnwrap(pattern(s, id)).instrument.kitSamples, ["snare": snare])
    }

    func testSampleFolderScanFindsAudioFilesInOrder() throws {
        try wav("kick 10.wav"); try wav("kick 2.wav"); try wav("Vocals/chop.wav"); try wav("Vocals/Takes/la.wav")
        try Data("not audio".utf8).write(to: scratch.appendingPathComponent("notes.txt"))
        let files = Store.scanSampleFolder(scratch)
        XCTAssertEqual(files.map(\.name), ["kick 2", "kick 10", "chop", "la"], "top level first, numbers in natural order")
        XCTAssertEqual(files.map(\.folder), ["", "", "Vocals", "Vocals / Takes"])
    }

    func testSampleFoldersAreNotSavedFromIsolatedRuns() {
        let before = UserDefaults.standard.object(forKey: Store.sampleFoldersKey) as? [String]
        let s = emptyStore()
        XCTAssertTrue(s.sampleFolders.isEmpty, "isolated runs don't read your folders")
        s.addSampleFolder(scratch)
        XCTAssertEqual(s.sampleFolders, [scratch.standardizedFileURL.path])
        XCTAssertEqual(s.browserTab, .samples)
        XCTAssertEqual(UserDefaults.standard.object(forKey: Store.sampleFoldersKey) as? [String], before, "and never write them")
        s.removeSampleFolder(scratch.standardizedFileURL.path)
        XCTAssertTrue(s.sampleFolders.isEmpty)
    }

    func testKeyboardPlaysASamplerPattern() throws {
        let s = emptyStore()
        let id = try XCTUnwrap(s.addSampler(try wav("Pluck.wav")))
        XCTAssertEqual(s.keyboardTarget, id)
        XCTAssertTrue(s.keyboardKey("a", down: true, isRepeat: false))
        XCTAssertEqual(s.heldKeys["a"]?.isDrum, false, "a sampler plays the piano layout")
        XCTAssertTrue(s.keyboardKey("a", down: false, isRepeat: false))
    }

    func testNotAudioIsRefused() throws {
        let s = emptyStore()
        let text = scratch.appendingPathComponent("readme.wav")
        try Data("hello".utf8).write(to: text)
        XCTAssertNil(s.addSampler(text.path))
        XCTAssertTrue(s.activeComp!.tracks.isEmpty)
    }
}
