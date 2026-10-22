import AppKit
import Foundation
import ShawCore

/// A take in progress: where it goes, and what the screen shows while it records.
struct RecordingState: Equatable {
    var track: UUID
    var comp: AssetID
    /// Where the take starts in the song (the playhead when you pressed Record).
    var startBeat: Double
    var url: URL
    /// The waveform so far, one peak per `AudioRecorder.peakInterval`, from the first recorded sample.
    var peaks: [Float] = []
    var level: Float = 0
    /// Seconds of audio recorded before `startBeat` (the count-in), so the live waveform lines up.
    var preroll: Double
    var countingIn: Bool
}

extension Store {
    /// R, or the ● button: start recording at the playhead, or stop and keep the take.
    func toggleRecord() {
        if recording != nil { stopRecording() } else { startRecording() }
    }

    /// Where takes are saved: a folder per project in ~/Music/Shaw/Recordings, so your audio is
    /// always a plain file you can find, not only inside a project.
    var recordingsFolder: URL {
        if isolated { return FileManager.default.temporaryDirectory.appendingPathComponent("ShawRecordings", isDirectory: true) }
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        let name = displayName.replacingOccurrences(of: "/", with: "-")
        return music.appendingPathComponent("Shaw/Recordings/\(name.isEmpty ? "Untitled" : name)", isDirectory: true)
    }

    func startRecording() {
        switch AudioRecorder.permission {
        case .undetermined:
            AudioRecorder.requestPermission { [weak self] ok in
                if ok { self?.startRecording() } else { self?.explainMicrophoneAccess() }
            }
            return
        case .denied:
            explainMicrophoneAccess()
            return
        case .granted:
            break
        }
        guard recording == nil, let comp = activeComp else { return }
        let compID = activeCompID
        let track = recordingTrack(in: comp) ?? addTrack(name: "Recording")
        let now = engine.snapshot()
        let bar = Double(project.beatsPerBar)
        // Stopped: count in a bar from the playhead. Playing: punch in a moment from now.
        let start = now.playing ? now.position + 0.1 : now.position
        let url = nextTakeURL()
        let recorder = AudioRecorder()
        do {
            try recorder.start(writingTo: url)
        } catch {
            showAlert("Couldn't start recording", error.localizedDescription)
            return
        }
        self.recorder = recorder
        loopBeforeRecording = loopEnabled
        loopEnabled = false // a take records straight through; loop takes come later
        engine.mark(beat: start)
        if !now.playing { engine.play(from: start, countIn: bar) }
        recording = RecordingState(track: track, comp: compID, startBeat: start, url: url,
                                   preroll: now.playing ? 0.1 * 60 / project.bpm : bar * 60 / project.bpm, countingIn: !now.playing)
        selectedClips = []
        inspector = .track(compID, track)
    }

    /// Stop the take, put it on its layer where it was sung, and stop the song.
    func stopRecording() {
        guard let rec = recording else { return }
        let marked = engine.markedNanos
        engine.stop(returnToStart: false)
        let take = recorder?.stop()
        recorder = nil
        recording = nil
        loopEnabled = loopBeforeRecording
        guard let take else { return }
        // Where in the file the start beat was sung: the moment it was heard (rendered, plus the time
        // to reach the speakers) against the moment the first sample was captured (its arrival time,
        // less the time from the mic). Without host times, assume the count-in lasted as long as it should.
        var offset = rec.preroll
        if let m = marked, let first = take.firstSampleNanos {
            let heard = Double(m) / 1e9 + AudioRecorder.outputLatency()
            let captured = Double(first) / 1e9 - AudioRecorder.inputLatency()
            offset = heard - captured
        }
        offset = min(max(0, offset), take.duration)
        placeTake(take, offset: offset, rec: rec)
    }

    /// Put a finished take on its layer: the clip starts at the start beat, and the count-in before
    /// it stays in the file (drag the clip's start left to bring in a pickup).
    func placeTake(_ take: AudioRecorder.Take, offset: Double, rec: RecordingState) {
        let kept = take.duration - offset
        guard kept > 0.05 else {
            try? FileManager.default.removeItem(at: take.url)
            return
        }
        let name = take.url.deletingPathExtension().lastPathComponent
        let ref = AudioFileRef(path: take.url.path, duration: take.duration, sampleRate: take.sampleRate, channels: 1)
        let asset = Asset(name: name, colorIndex: 3, content: .audio(ref))
        _ = SampleLibrary.shared.data(for: take.url.path)
        let beatsPerSecond = project.bpm / 60
        let clip = Clip(assetID: asset.id, start: rec.startBeat, length: kept * beatsPerSecond, offset: offset * beatsPerSecond)
        edit { p in
            p.assets.append(asset)
            p.updateComposition(rec.comp) { c in
                if let i = c.tracks.firstIndex(where: { $0.id == rec.track }) { c.tracks[i].clips.append(clip) }
            }
        }
        selectedClips = [clip.id]
        inspector = .clip(rec.comp, clip.id)
    }

    /// The layer to record onto: the selected one, if it holds only audio (or nothing yet).
    private func recordingTrack(in comp: Composition) -> UUID? {
        guard case .track(let cid, let tid)? = inspector, cid == activeCompID,
              let t = comp.tracks.first(where: { $0.id == tid }) else { return nil }
        let allAudio = t.clips.allSatisfy { project.asset($0.assetID)?.kind == .audio }
        return allAudio ? tid : nil
    }

    private func nextTakeURL() -> URL {
        let folder = recordingsFolder
        var n = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent("Take \(n).caf").path) { n += 1 }
        return folder.appendingPathComponent("Take \(n).caf")
    }

    private func explainMicrophoneAccess() {
        guard !headless else { return }
        let a = NSAlert()
        a.messageText = "Shaw can't hear your microphone"
        a.informativeText = "Turn on Shaw in System Settings, under Privacy & Security, then Microphone. Then press Record again."
        a.addButton(withTitle: "Open System Settings")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Called by the transport timer: keep the live waveform and level moving.
    func pollRecording() {
        guard var rec = recording, let recorder else { return }
        let s = recorder.snapshot()
        rec.peaks = s.peaks
        rec.level = s.level
        rec.countingIn = engine.snapshot().countingIn
        if rec != recording { recording = rec }
    }
}
