import Foundation
import ShawCore

/// One moment of a time-lapse: the project as it stood then, and what was on screen.
struct TimelapseFrame {
    var project: Project
    var comp: AssetID
    var roll: AssetID?
    var inspector: InspectorTarget?
    var selected: Set<UUID> = []
}

/// A time-lapse in progress, and everything needed to put the real project back afterwards.
final class TimelapseRun {
    let frames: [TimelapseFrame]
    var index = 0
    var timer: Timer?
    let project: Project
    let activeCompID: AssetID
    let openComps: [AssetID]
    let pianoRollAsset: AssetID?
    let inspector: InspectorTarget?
    let selectedClips: Set<UUID>
    let editingClip: UUID?
    let zoom: Double

    init(frames: [TimelapseFrame], from s: Store) {
        self.frames = frames
        project = s.project
        activeCompID = s.activeCompID
        openComps = s.openComps
        pianoRollAsset = s.pianoRollAsset
        inspector = s.inspector
        selectedClips = s.selectedClips
        editingClip = s.editingClip
        zoom = s.zoom
    }
}

extension Store {
    /// Replays how the open project could have been built, fast: each section opened in song
    /// order, its tracks added one by one, every pattern's notes written in the piano roll, the
    /// clips placed, and the effects added. It only changes what's on screen: no undo steps, no
    /// autosave, and the real project comes back at the end (or on Esc, or any edit).
    func playTimelapse() {
        guard timelapse == nil else { return }
        let frames = Store.timelapseFrames(of: project)
        guard frames.count > 1 else { return }
        engine.stop()
        engine.previewAllOff()
        let run = TimelapseRun(frames: frames, from: self)
        timelapse = run
        timelapseProgress = 0
        // About half a minute whatever the project's size, but never a blur or a crawl.
        let interval = min(0.25, max(0.035, 30 / Double(frames.count)))
        run.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.advanceTimelapse() }
        showTimelapseFrame(frames[0])
    }

    /// Ends the time-lapse. With `restore`, the real project and view come back as they were.
    func stopTimelapse(restore: Bool = true) {
        guard let run = timelapse else { return }
        run.timer?.invalidate()
        timelapse = nil
        timelapseProgress = nil
        guard restore else { return }
        project = run.project
        openComps = run.openComps
        activeCompID = run.activeCompID
        pianoRollAsset = run.pianoRollAsset
        inspector = run.inspector
        selectedClips = run.selectedClips
        editingClip = run.editingClip
        zoom = run.zoom
        refreshEngine()
        loopWholeComposition()
    }

    /// Jumps to a point in the time-lapse (0...1), paused there. For snapshots and tests.
    func seekTimelapse(to fraction: Double) {
        guard let run = timelapse else { return }
        run.timer?.invalidate()
        run.index = min(run.frames.count - 1, max(0, Int(fraction * Double(run.frames.count - 1))))
        timelapseProgress = fraction
        showTimelapseFrame(run.frames[run.index])
    }

    private func advanceTimelapse() {
        guard let run = timelapse else { return }
        run.index += 1
        guard run.index < run.frames.count else {
            // Hold on the finished song for a moment, then hand it back.
            run.timer?.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.timelapse === run { self?.stopTimelapse() }
            }
            return
        }
        timelapseProgress = Double(run.index) / Double(run.frames.count - 1)
        showTimelapseFrame(run.frames[run.index])
    }

    private func showTimelapseFrame(_ f: TimelapseFrame) {
        project = f.project
        if !openComps.contains(f.comp) { openComps.append(f.comp) }
        openComps = openComps.filter { project.composition($0) != nil }
        if activeCompID != f.comp {
            activeCompID = f.comp
            fitRequest += 1
        }
        if let r = f.roll { pianoRollAsset = r }
        if let p = pianoRollAsset, project.asset(p) == nil { pianoRollAsset = nil }
        inspector = f.inspector
        selectedClips = f.selected
        refreshEngine()
    }

    /// The steps, reconstructed from the finished project (a project you just opened has no edit
    /// history): left to right through the song, building each thing the first time it's used.
    static func timelapseFrames(of final: Project) -> [TimelapseFrame] {
        let mainID = final.mainCompositionID
        guard let main = final.asset(mainID), case .composition(let mainComp) = main.content else { return [] }
        var w = final
        var bareMain = main
        bareMain.content = .composition(emptied(mainComp))
        w.assets = [bareMain]
        var frames: [TimelapseFrame] = []
        var built: Set<AssetID> = [mainID]

        func snap(_ comp: AssetID, roll: AssetID? = nil, _ inspector: InspectorTarget?, selected: Set<UUID> = []) {
            frames.append(TimelapseFrame(project: w, comp: comp, roll: roll, inspector: inspector, selected: selected))
        }
        func build(_ id: AssetID, in parent: AssetID) {
            guard !built.contains(id), let a = final.asset(id) else { return }
            built.insert(id)
            switch a.content {
            case .composition(let c):
                var bare = a
                bare.content = .composition(emptied(c))
                w.assets.append(bare)
                fill(id, c)
                snap(parent, .composition(parent))
            case .notes(let pat):
                // Pick the sound, then write the notes left to right, a few at a time.
                var bare = pat
                bare.notes = []
                var asset = a
                asset.content = .notes(bare)
                w.assets.append(asset)
                snap(parent, roll: id, .asset(id))
                let notes = pat.notes.sorted { $0.start < $1.start }
                let chunks = min(8, notes.count)
                for k in stride(from: 1, through: chunks, by: 1) {
                    w.updateNotes(id) { $0.notes = Array(notes.prefix(notes.count * k / chunks)) }
                    snap(parent, roll: id, .asset(id))
                }
            default:
                w.assets.append(a)
                snap(parent, .asset(id))
            }
        }

        func fill(_ id: AssetID, _ c: Composition) {
            snap(id, .composition(id))
            for t in c.tracks {
                var bare = t
                bare.clips = []
                bare.effects = []
                w.updateComposition(id) { $0.tracks.append(bare) }
                snap(id, .track(id, t.id))
                for clip in t.clips.sorted(by: { $0.start < $1.start }) {
                    build(clip.assetID, in: id)
                    w.updateComposition(id) { comp in
                        if let ti = comp.tracks.firstIndex(where: { $0.id == t.id }) { comp.tracks[ti].clips.append(clip) }
                    }
                    let roll = final.asset(clip.assetID)?.kind == .notes ? clip.assetID : nil
                    snap(id, roll: roll, .clip(id, clip.id), selected: [clip.id])
                }
                for e in t.effects {
                    w.updateComposition(id) { comp in
                        if let ti = comp.tracks.firstIndex(where: { $0.id == t.id }) { comp.tracks[ti].effects.append(e) }
                    }
                    snap(id, .track(id, t.id))
                }
            }
            for e in c.effects {
                w.updateComposition(id) { $0.effects.append(e) }
                snap(id, .composition(id))
            }
        }

        fill(mainID, mainComp)
        // Anything the song never uses still ends up in the Project panel, in its place.
        frames.append(TimelapseFrame(project: final, comp: mainID, roll: nil, inspector: .composition(mainID)))
        return frames
    }

    private static func emptied(_ c: Composition) -> Composition {
        var c = c
        c.tracks = []
        c.effects = []
        return c
    }
}
