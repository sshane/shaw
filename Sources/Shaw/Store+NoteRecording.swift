import AppKit
import Foundation
import ShawCore

/// Where recorded notes land: as played, or moved onto the nearest beat of a grid. Only where notes
/// start moves; they keep the length you held them. The take snaps when you stop: snapping a note as
/// it came in could move it a moment ahead of the playhead, and then the song would play it a
/// second time just after you did.
enum RecordSnap: String, CaseIterable, Identifiable {
    case off, quarter, eighth, sixteenth, eighthTriplet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off (exactly as played)"
        case .quarter: return "1/4"
        case .eighth: return "1/8"
        case .sixteenth: return "1/16"
        case .eighthTriplet: return "1/8 triplets"
        }
    }
    var beats: Double {
        switch self {
        case .off: return 0
        case .quarter: return 1
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        case .eighthTriplet: return 1.0 / 3
        }
    }
}

/// Keyboard playing being recorded into a pattern.
struct NoteTake {
    /// The pattern the notes go into, and the clip that places it in the song.
    var asset: AssetID
    var comp: AssetID
    var clip: UUID
    var startBeat: Double
    /// The project before the take, so the whole take is one undo step.
    var before: Project
    /// Seconds from the engine to your ears: a key pressed now goes with what played this long ago.
    var latency: Double
    /// Keys held down: the note, when it went down (song beats), and how hard.
    var held: [String: (pitch: Int, beat: Double, velocity: Double)] = [:]
    /// The notes this take added, to snap when it ends.
    var recorded: Set<UUID> = []
}

extension Store {
    static let recordSnapKey = "RecordSnap"

    /// True when Record would capture keyboard playing rather than the microphone: the keyboard plays
    /// an instrument, and you haven't picked a layer of audio recordings to record onto.
    var recordsNotes: Bool {
        guard keyboardEnabled, let t = keyboardTarget, project.asset(t)?.kind == .notes else { return false }
        if case .track(let cid, let tid)? = inspector, cid == activeCompID,
           let tr = activeComp?.tracks.first(where: { $0.id == tid }), !tr.clips.isEmpty,
           tr.clips.allSatisfy({ project.asset($0.assetID)?.kind == .audio }) { return false }
        return true
    }

    /// Start recording the keyboard into the pattern it plays. Stopped, it counts in a bar from the
    /// playhead; playing, it records from now. With the loop on, every pass adds to the pattern.
    func startNoteRecording() {
        guard noteTake == nil, recording == nil, let asset = keyboardTarget, project.asset(asset)?.kind == .notes else { return }
        let now = engine.snapshot()
        let bar = Double(project.beatsPerBar)
        let before = project
        let start = now.position
        // The clip under the playhead that plays this pattern, or a new one on its own layer, from that bar.
        let clipID: UUID
        if let c = activeComp?.tracks.flatMap(\.clips).first(where: { $0.assetID == asset && start >= $0.start - 1e-9 && start < $0.end }) {
            clipID = c.id
        } else {
            let length = project.sourceLength(of: asset)
            let c = Clip(assetID: asset, start: floor(start / bar) * bar, length: length)
            clipID = c.id
            let name = project.asset(asset)?.name ?? "Recording"
            takeEdit { p in
                p.updateComposition(activeCompID) { comp in
                    var t = Track(name: name, colorIndex: comp.tracks.count % Theme.labels.count)
                    t.clips = [c]
                    comp.tracks.append(t)
                }
            }
        }
        noteTake = NoteTake(asset: asset, comp: activeCompID, clip: clipID, startBeat: start, before: before,
                            latency: headless ? 0 : AudioRecorder.outputLatency())
        if !now.playing { engine.play(from: start, countIn: bar) }
        poll()
    }

    /// Stop the take: notes still held end now, and the whole take becomes one undo step.
    func stopNoteRecording() {
        guard let take = noteTake else { return }
        let end = takeBeat(nil)
        for (key, _) in take.held { noteUp(key, atBeat: end) }
        snapTake()
        noteTake = nil
        endTake(from: take.before)
        engine.stop(returnToStart: false)
        poll()
    }

    /// Snap the take's notes to the record grid, on the song's beats (the pattern may start off the beat).
    private func snapTake() {
        let g = recordSnap.beats
        guard g > 0, let take = noteTake, !take.recorded.isEmpty, let clip = clip(take.clip) else { return }
        let origin = clip.start - clip.offset
        takeEdit { p in
            p.updateNotes(take.asset) { pat in
                for i in pat.notes.indices where take.recorded.contains(pat.notes[i].id) {
                    var local = ((pat.notes[i].start + origin) / g).rounded() * g - origin
                    if clip.loops && local >= pat.length - 1e-9 { local -= pat.length }
                    pat.notes[i].start = max(0, local)
                }
            }
        }
    }

    /// The song beat you heard at `time` (an event's timestamp; now if nil).
    func takeBeat(_ time: TimeInterval?) -> Double? {
        let t = (time ?? ProcessInfo.processInfo.systemUptime) - (noteTake?.latency ?? 0)
        return engine.beat(atHostNanos: UInt64(max(0, t) * 1e9))
    }

    /// A key went down while recording. Drums land right away (a hit has no length to wait for).
    func noteDown(_ key: String, pitch: Int, velocity: Double, drum: Bool, atBeat beat: Double?) {
        guard noteTake != nil, let beat else { return }
        if drum {
            record(pitch: pitch, at: beat, length: max(0.25, recordSnap.beats), velocity: velocity)
        } else {
            noteTake?.held[key] = (pitch, beat, velocity)
        }
    }

    /// A key came up while recording: its note goes into the pattern.
    func noteUp(_ key: String, atBeat beat: Double?) {
        guard let h = noteTake?.held.removeValue(forKey: key) else { return }
        // Released after a loop wrapped around: the note lasted to the loop's end.
        var end = beat ?? h.beat + 0.25
        if end < h.beat, loopEnabled { end = loopEnd }
        record(pitch: h.pitch, at: h.beat, length: max(1.0 / 32, end - h.beat), velocity: h.velocity)
    }

    /// Put one played note into the take's pattern, where it sounds at song beat `beat`.
    func record(pitch: Int, at beat: Double, length: Double, velocity: Double) {
        guard let take = noteTake, let comp = project.composition(take.comp), let (ti, ci) = comp.locate(clip: take.clip),
              case .notes(let pattern)? = project.asset(take.asset)?.content else { return }
        let clip = comp.tracks[ti].clips[ci]
        var b = beat
        // A pickup played a hair before the start belongs on it; anything earlier was the count-in.
        if b < take.startBeat {
            guard b >= take.startBeat - 0.25 else { return }
            b = take.startBeat
        }
        let bar = Double(project.beatsPerBar)
        let note = Note(pitch: pitch, start: 0, length: length, velocity: velocity)
        noteTake?.recorded.insert(note.id)
        takeEdit { p in
            // Playing past the clip's end makes it longer, by whole bars.
            if b + length > clip.end {
                p.updateComposition(take.comp) { c in
                    c.tracks[ti].clips[ci].length = ceil((b + length - clip.start) / bar) * bar
                }
            }
            p.updateNotes(take.asset) { pat in
                var local = b - clip.start + clip.offset
                if clip.loops && pattern.length > 0 {
                    // A looping clip plays the pattern over and over: each pass adds to the same notes.
                    local = local.truncatingRemainder(dividingBy: pattern.length)
                } else if local + length > pat.length {
                    pat.length = ceil((local + length) / bar) * bar
                }
                var n = note
                n.start = local
                pat.notes.append(n)
            }
        }
    }

    /// Snap the starts of `ids` (or every note, if none) in a pattern to a grid of `grid` beats, keeping
    /// their lengths. One undo step.
    func quantize(_ asset: AssetID, notes ids: Set<UUID>, grid: Double) {
        guard grid > 0 else { return }
        edit { p in
            p.updateNotes(asset) { pat in
                for i in pat.notes.indices where ids.isEmpty || ids.contains(pat.notes[i].id) {
                    pat.notes[i].start = max(0, (pat.notes[i].start / grid).rounded() * grid)
                }
            }
        }
    }
}
