import AppKit
import Observation
import ShawCore
import SwiftUI
import UniformTypeIdentifiers

enum InspectorTarget: Equatable {
    case composition(AssetID)
    case track(AssetID, UUID)
    case clip(AssetID, UUID)
    case asset(AssetID)
    /// A session slot: composition, track, scene.
    case slot(AssetID, UUID, Int)
}

/// Anything that can hold an effect chain. Compositions and tracks are treated alike.
enum EffectHost: Equatable {
    case composition(AssetID)
    case track(AssetID, UUID)
    case clip(AssetID, UUID)
}

enum FocusArea { case timeline, session, pianoRoll, beatMaker, project, inspector, other }

enum SnapSetting: String, CaseIterable, Identifiable {
    case auto = "Auto", bar = "1 Bar", beat = "1/4", eighth = "1/8", sixteenth = "1/16", thirtysecond = "1/32", off = "Off"
    var id: String { rawValue }

    /// Grid size in beats. `pixelsPerBeat` drives the adaptive setting.
    func beats(pixelsPerBeat: Double, beatsPerBar: Int) -> Double {
        switch self {
        case .bar: return Double(beatsPerBar)
        case .beat: return 1
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        case .thirtysecond: return 0.125
        case .off: return 0
        case .auto:
            for g in [0.125, 0.25, 0.5, 1.0, Double(beatsPerBar), Double(beatsPerBar * 4)] where g * pixelsPerBeat >= 14 { return g }
            return Double(beatsPerBar * 4)
        }
    }
}

/// Transport state polled from the engine ~30 times a second. Kept separate so
/// only the views that show the playhead redraw while playing.
@Observable final class TransportModel {
    var playing = false
    var position = 0.0
    var sessionBeat = 0.0
    var sessions: [UUID: SessionInfo] = [:]
    var masterLevel: Float = 0
}

@Observable final class Store {
    var project: Project
    /// Where the project was last saved. Remembered across launches (with the autosave) so
    /// ⌘S keeps saving to the same file instead of asking for a name again.
    var fileURL: URL? {
        didSet {
            guard !isolated else { return }
            UserDefaults.standard.set(fileURL?.path, forKey: Store.fileURLKey)
        }
    }
    static let fileURLKey = "ShawProjectFile"
    static let welcomeKey = "ShawSeenWelcome.v1"

    func dismissWelcome() {
        showWelcome = false
        if !isolated { UserDefaults.standard.set(true, forKey: Store.welcomeKey) }
    }
    var dirty = false

    // Navigation
    var openComps: [AssetID] = []
    var activeCompID: AssetID
    var selectedClips: Set<UUID> = []
    var inspector: InspectorTarget?
    var selectedAssets: Set<AssetID> = []
    var pianoRollAsset: AssetID?
    var focus: FocusArea = .timeline
    var workspace = Workspace.load() { didSet { if workspace != oldValue && !isolated { workspace.save() } } }
    var renamingAsset: AssetID?
    var selectedNotes: Set<UUID> = []
    /// Drum patterns: show the FL-style step grid instead of the piano roll (same notes either way).
    var drumStepView = false
    /// Effects selected by clicking their titles (all on one layer: `selectedEffectsHost`).
    var selectedEffects: Set<UUID> = []
    var selectedEffectsHost: EffectHost?
    @ObservationIgnored var clipboard: ShawClipboard?
    /// First-launch quick start (also Help → Welcome to Shaw).
    var showWelcome = false
    /// Layers whose keyframe rows are twirled open in the timeline, and the selected ◆s.
    var expandedTracks: Set<UUID> = []
    var selectedKeyframes: Set<UUID> = []
    var browserTab: BrowserTab = .instruments
    /// Bumped to move keyboard focus into the browser's search field.
    var focusBrowserSearch = 0
    /// The timeline clip whose pattern is open in an editor (drives looping and variations).
    var editingClip: UUID?
    /// The instrument the computer keyboard plays when no editor has focus.
    var lastInstrumentAsset: AssetID?
    // Computer keyboard as a piano (Ableton style).
    var keyboardEnabled = true
    var keyboardOctave = 3        // the A key plays C of this octave (C3 = MIDI 48)
    var keyboardVelocity = 0.8
    /// Editors: false = Ableton style (double-click to add/delete), true = click to draw/paint.
    var drawMode = false
    /// Play notes and hits while clicking them in the editors (never while the song plays).
    var auditionNotes = (UserDefaults.standard.object(forKey: "ShawAuditionNotes.v2") as? Bool) ?? true {
        didSet { if !isolated { UserDefaults.standard.set(auditionNotes, forKey: "ShawAuditionNotes.v2") } }
    }
    /// Copied piano-roll notes (⌘C / ⌘X) and where ⌘V pastes them (last click in the grid).
    @ObservationIgnored var noteClipboard: [Note] = []
    @ObservationIgnored var rollInsertBeat: Double?
    /// Pitches currently held on the computer keyboard (lit up in the piano roll).
    var playingPitches: Set<Int> = []
    @ObservationIgnored var heldKeys: [String: (pitch: Int, isDrum: Bool)] = [:]
    var rollSnap: Double = 0.25
    var rollZoom: Double = 60 // pixels per beat in the piano roll
    var lastNoteLength: Double = 0.25

    // Timeline view
    var zoom: Double = 15 // pixels per beat
    var snap: SnapSetting = .auto
    var trackHeight: CGFloat = 58
    /// Bumped to ask the timeline to zoom so the whole composition fits.
    var fitRequest = 0
    /// True while the user drags the playhead, so follow-scrolling doesn't fight them.
    @ObservationIgnored var scrubbing = false

    // Transport settings (mirrored into the engine)
    var loopEnabled = true { didSet { syncLoop() } }
    var loopStart = 0.0 { didSet { syncLoop() } }
    var loopEnd = 16.0 { didSet { syncLoop() } }
    var metronome = false { didSet { engine.setMetronome(metronome) } }

    let transport = TransportModel()
    @ObservationIgnored let engine = AudioEngine()
    @ObservationIgnored private var undoStack: [Project] = []
    @ObservationIgnored private var redoStack: [Project] = []
    @ObservationIgnored private var gestureActive = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var autosaveWork: DispatchWorkItem?
    @ObservationIgnored private var lastAutosave = Date.distantPast
    var canUndo = false
    var canRedo = false

    /// Set in tests: no alerts, no autosave.
    @ObservationIgnored var headless = false
    /// Debug/snapshot runs: start from the demo and never touch the user's autosave or preferences.
    @ObservationIgnored private(set) var isolated = false

    /// True when launched for a debug snapshot (see DebugSnapshot); such runs must not touch user data.
    static var isIsolatedLaunch: Bool { ProcessInfo.processInfo.environment["SHAW_SNAPSHOT"] != nil }

    init(project initial: Project? = nil, headless: Bool = false, isolated: Bool = Store.isIsolatedLaunch) {
        self.isolated = isolated || headless
        // A brand-new user starts with an empty project that guides them; the demo is one click away.
        let snapshotDemo = self.isolated && ProcessInfo.processInfo.environment["SHAW_EMPTY"] == nil
        let restored = (initial == nil && !self.isolated) ? Store.restoreAutosave() : nil
        var p = initial ?? restored ?? (snapshotDemo ? DemoProject.make() : DemoProject.empty())
        p.migrateDrumPatterns() // old step-sequencer beats become drum-kit piano-roll patterns
        project = p
        activeCompID = p.mainCompositionID
        openComps = [p.mainCompositionID]
        self.headless = headless
        if restored != nil, let path = UserDefaults.standard.string(forKey: Store.fileURLKey),
           FileManager.default.fileExists(atPath: path) {
            // The autosave belongs to this file: keep saving there, and only flag it edited if it differs.
            let url = URL(fileURLWithPath: path)
            fileURL = url
            var saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Project.self, from: $0) }
            saved?.migrateDrumPatterns()
            dirty = saved != p
        }
        if !headless { engine.start() }
        SampleLibrary.shared.onLoad = { [weak self] _ in self?.refreshEngine() }
        refreshEngine()
        syncLoop()
        if !headless {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer!, forMode: .common)
        }
        if isolated { workspace = .standard }
        showWelcome = isolated ? ProcessInfo.processInfo.environment["SHAW_WELCOME"] != nil
                               : !UserDefaults.standard.bool(forKey: Store.welcomeKey)
        if let first = p.assets.first(where: { $0.kind == .notes }) { pianoRollAsset = first.id }
    }

    private func poll() {
        let s = engine.snapshot()
        if transport.playing != s.playing { transport.playing = s.playing }
        if transport.position != s.position { transport.position = s.position }
        if transport.sessionBeat != s.sessionBeat { transport.sessionBeat = s.sessionBeat }
        if transport.sessions != s.sessions { transport.sessions = s.sessions }
        let lvl = max(engine.masterMeter.peakL, engine.masterMeter.peakR)
        if abs(transport.masterLevel - lvl) > 0.002 { transport.masterLevel = lvl }
        if !s.playing { engine.masterMeter.decay() }
    }

    private func syncLoop() { engine.setLoop(enabled: loopEnabled, start: loopStart, end: loopEnd) }

    func refreshEngine() {
        if project.composition(activeCompID) == nil { activeCompID = project.mainCompositionID }
        engine.update(project: project, root: activeCompID)
    }

    // MARK: - Editing & undo

    /// Apply a discrete edit (one undo step).
    func edit(_ body: (inout Project) -> Void) {
        gestureActive = false // a discrete edit always starts a fresh undo step
        let before = project
        // Edit a copy, then swap it in: closures may safely read `store.project` while editing
        // (mutating `project` in place while reading it is a Swift exclusivity violation → crash).
        var next = project
        body(&next)
        guard next != before else { return }
        project = next
        pushUndo(before)
        changed()
    }

    /// Apply an edit during a continuous gesture. The first call snapshots for
    /// undo; call `endGesture()` when the drag finishes.
    func live(_ body: (inout Project) -> Void) {
        let before = project
        var next = project // see edit(_:)
        body(&next)
        guard next != before else { return }
        project = next
        if !gestureActive {
            gestureActive = true
            pushUndo(before)
        }
        changed()
    }

    func endGesture() { gestureActive = false }

    private func pushUndo(_ p: Project) {
        undoStack.append(p)
        if undoStack.count > 300 { undoStack.removeFirst() }
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    private func changed() {
        dirty = true
        refreshEngine()
        scheduleAutosave()
    }

    func undo() {
        guard let p = undoStack.popLast() else { return }
        redoStack.append(project)
        project = p
        canUndo = !undoStack.isEmpty
        canRedo = true
        sanitizeNavigation()
        changed()
    }

    func redo() {
        guard let p = redoStack.popLast() else { return }
        undoStack.append(project)
        project = p
        canUndo = true
        canRedo = !redoStack.isEmpty
        sanitizeNavigation()
        changed()
    }

    private func sanitizeNavigation() {
        openComps = openComps.filter { project.composition($0) != nil }
        if project.composition(activeCompID) == nil { activeCompID = project.mainCompositionID }
        if openComps.isEmpty { openComps = [activeCompID] }
        if let p = pianoRollAsset, project.asset(p) == nil { pianoRollAsset = nil }
        if let comp = activeComp {
            let ids = Set(comp.tracks.flatMap(\.clips).map(\.id))
            selectedClips = selectedClips.intersection(ids)
        }
    }

    // MARK: - Accessors

    var activeComp: Composition? { project.composition(activeCompID) }
    var activeAsset: Asset? { project.asset(activeCompID) }

    func gridBeats() -> Double { snap.beats(pixelsPerBeat: zoom, beatsPerBar: project.beatsPerBar) }

    func snapBeat(_ b: Double, disable: Bool = false) -> Double {
        let g = gridBeats()
        if disable || g <= 0 { return max(0, b) }
        return max(0, (b / g).rounded() * g)
    }

    func color(of assetID: AssetID) -> Color { Theme.label(project.asset(assetID)?.colorIndex ?? 0) }

    // MARK: - Navigation

    func openComposition(_ id: AssetID) {
        guard project.composition(id) != nil else { return }
        if !openComps.contains(id) { openComps.append(id) }
        if activeCompID != id {
            engine.stop(returnToStart: false)
            engine.seek(0)
            activeCompID = id
            selectedClips = []
            refreshEngine()
            fitRequest += 1
        }
        inspector = .composition(id)
        workspace.reveal(.timeline)
        loopWholeComposition()
    }

    func closeComposition(_ id: AssetID) {
        openComps.removeAll { $0 == id }
        if openComps.isEmpty { openComps = [project.mainCompositionID] }
        if activeCompID == id { openComposition(openComps.last!) }
    }

    /// Double-click behaviour: compositions open as tabs, patterns open their editor.
    /// - Parameter clip: the timeline clip it was opened from; editing it loops that clip.
    func open(asset id: AssetID, clip: UUID? = nil) {
        guard let a = project.asset(id) else { return }
        switch a.kind {
        case .composition: openComposition(id)
        case .notes:
            pianoRollAsset = id
            lastInstrumentAsset = id
            inspector = clip.map { .clip(activeCompID, $0) } ?? .asset(id)
            workspace.reveal(.pianoRoll)
            focus = .pianoRoll
        case .drums, .audio:
            inspector = .asset(id)
        }
        if a.kind == .notes {
            editingClip = clip ?? contextClip(for: id)?.id
            if let c = editingClip { loop(aroundClip: c) }
        }
    }

    // MARK: - Transport

    func togglePlay() {
        if transport.playing { engine.stop() } else { engine.play() }
        poll()
    }

    func stop() { engine.stop(); poll() }

    func seek(_ beat: Double) { engine.seek(beat); poll() }

    func returnToStart() { engine.seek(loopEnabled ? loopStart : 0); poll() }

    // MARK: - Assets

    private func nextColor() -> Int { project.assets.count % Theme.labels.count }

    @discardableResult
    func newComposition(name: String? = nil, lengthBars: Int = 16) -> AssetID {
        var comp = Composition(length: Double(lengthBars * project.beatsPerBar))
        comp.tracks = [Track(name: "Track 1", colorIndex: 0), Track(name: "Track 2", colorIndex: 1)]
        let a = Asset(name: project.uniqueName(name ?? "Comp"), colorIndex: nextColor(), content: .composition(comp))
        edit { $0.assets.append(a) }
        return a.id
    }

    @discardableResult
    func newPattern(preset: String = "Pluck", name: String? = nil, bars: Int = 4) -> AssetID {
        let p = NotePattern(length: Double(bars * project.beatsPerBar), instrument: .preset(preset))
        let a = Asset(name: project.uniqueName(name ?? preset), colorIndex: nextColor(), content: .notes(p))
        edit { $0.assets.append(a) }
        return a.id
    }

    @discardableResult
    func newBeat(kit: String = DrumKits.defaultKit, name: String? = nil) -> AssetID {
        // Drums are an ordinary piano-roll pattern played by a kit.
        let p = NotePattern(length: Double(project.beatsPerBar), instrument: .kit(kit))
        let a = Asset(name: project.uniqueName(name ?? "\(DrumKits.kitName(kit)) Beat"), colorIndex: nextColor(), content: .notes(p))
        edit { $0.assets.append(a) }
        return a.id
    }

    @discardableResult
    func importAudio(_ urls: [URL]) -> [AssetID] {
        var ids: [AssetID] = []
        var errors: [String] = []
        var newAssets: [Asset] = []
        for url in urls {
            do {
                let ref = try SampleLibrary.probe(url)
                let a = Asset(name: url.deletingPathExtension().lastPathComponent, colorIndex: 6 + newAssets.count % 3, content: .audio(ref))
                newAssets.append(a)
                ids.append(a.id)
                _ = SampleLibrary.shared.data(for: url.path)
            } catch {
                errors.append(url.lastPathComponent)
            }
        }
        if !newAssets.isEmpty { edit { $0.assets += newAssets } }
        if !errors.isEmpty { showAlert("Could not import", "Shaw couldn't read: \(errors.joined(separator: ", "))") }
        return ids
    }

    func importAudioDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importAudio(panel.urls) }
    }

    func renameAsset(_ id: AssetID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        edit { $0.updateAsset(id) { $0.name = n } }
    }

    func setAssetColor(_ id: AssetID, _ c: Int) { edit { $0.updateAsset(id) { $0.colorIndex = c } } }

    @discardableResult
    func duplicateAsset(_ id: AssetID) -> AssetID? {
        guard let idx = project.index(of: id), let copy = duplicated(project.assets[idx]) else { return nil }
        edit { $0.assets.insert(copy, at: idx + 1) }
        return copy.id
    }

    /// A copy of an asset with fresh ids (not yet added to the project).
    private func duplicated(_ original: Asset) -> Asset? {
        var a = original
        a.id = UUID()
        a.name = project.uniqueName(a.name.replacingOccurrences(of: " copy", with: "") + " copy")
        if case .composition(var c) = a.content {
            // New ids for tracks/clips so state paths don't collide.
            for ti in c.tracks.indices {
                c.tracks[ti].id = UUID()
                for ci in c.tracks[ti].clips.indices { c.tracks[ti].clips[ci].id = UUID() }
            }
            a.content = .composition(c)
        }
        return a
    }

    func deleteAssets(_ ids: Set<AssetID>) {
        var ids = ids
        ids.remove(project.mainCompositionID)
        guard !ids.isEmpty else { NSSound.beep(); return }
        let uses = ids.reduce(0) { $0 + project.usageCount(of: $1) }
        if uses > 0 {
            let names = ids.compactMap { project.asset($0)?.name }.joined(separator: ", ")
            guard confirm("Delete \(names)?", "It is used \(uses) time\(uses == 1 ? "" : "s"). Those clips will be removed too.") else { return }
        }
        edit { p in
            p.assets.removeAll { ids.contains($0.id) }
            for i in p.assets.indices {
                guard case .composition(var c) = p.assets[i].content else { continue }
                for ti in c.tracks.indices {
                    c.tracks[ti].clips.removeAll { ids.contains($0.assetID) }
                    c.tracks[ti].slots = c.tracks[ti].slots.filter { !ids.contains($0.value.assetID) }
                }
                p.assets[i].content = .composition(c)
            }
        }
        selectedAssets.subtract(ids)
        sanitizeNavigation()
        if case .asset(let a)? = inspector, ids.contains(a) { inspector = nil }
    }

    func setMainComposition(_ id: AssetID) { edit { $0.mainCompositionID = id } }

    func newFolder() {
        edit { $0.folders.append(Folder(name: "Folder \($0.folders.count + 1)")) }
    }

    func moveAssets(_ ids: Set<AssetID>, toFolder folder: UUID?) {
        edit { p in for id in ids { p.updateAsset(id) { $0.folderID = folder } } }
    }

    // MARK: - Tracks

    @discardableResult
    func addTrack(in compID: AssetID? = nil, name: String? = nil, at index: Int? = nil) -> UUID {
        let cid = compID ?? activeCompID
        let count = project.composition(cid)?.tracks.count ?? 0
        let t = Track(name: name ?? "Track \(count + 1)", colorIndex: count % Theme.labels.count)
        edit { p in
            p.updateComposition(cid) { c in
                if let i = index, i <= c.tracks.count { c.tracks.insert(t, at: i) } else { c.tracks.append(t) }
            }
        }
        return t.id
    }

    func updateTrack(_ trackID: UUID, in compID: AssetID? = nil, live: Bool = false, _ body: @escaping (inout Track) -> Void) {
        let cid = compID ?? activeCompID
        let f: (inout Project) -> Void = { p in
            p.updateComposition(cid) { c in
                if let i = c.trackIndex(trackID) { body(&c.tracks[i]) }
            }
        }
        if live { self.live(f) } else { edit(f) }
    }

    func deleteTrack(_ trackID: UUID, in compID: AssetID? = nil) {
        let cid = compID ?? activeCompID
        edit { p in p.updateComposition(cid) { $0.tracks.removeAll { $0.id == trackID } } }
        if case .track(_, let t)? = inspector, t == trackID { inspector = nil }
    }

    func moveTrack(_ trackID: UUID, by delta: Int) {
        edit { p in
            p.updateComposition(self.activeCompID) { c in
                guard let i = c.trackIndex(trackID) else { return }
                let j = max(0, min(c.tracks.count - 1, i + delta))
                let t = c.tracks.remove(at: i)
                c.tracks.insert(t, at: j)
            }
        }
    }

    // MARK: - Clips

    /// Returns false (and beeps) if placing `asset` into `comp` would create a loop.
    func canPlace(_ asset: AssetID, in comp: AssetID) -> Bool {
        if project.composition(asset) != nil && project.composition(asset, contains: comp) { return false }
        return true
    }

    @discardableResult
    func addClip(asset: AssetID, at start: Double, track trackID: UUID?, in compID: AssetID? = nil) -> UUID? {
        let cid = compID ?? activeCompID
        guard canPlace(asset, in: cid) else {
            NSSound.beep()
            showAlert("Can't place that here", "A composition can't contain itself.")
            return nil
        }
        let len = project.sourceLength(of: asset)
        let clip = Clip(assetID: asset, start: max(0, start), length: len)
        let name = project.asset(asset)?.name ?? "Track"
        let color = project.asset(asset)?.colorIndex ?? 0
        let bpb = Double(project.beatsPerBar)
        edit { p in
            p.updateComposition(cid) { c in
                if let tid = trackID, let i = c.trackIndex(tid) {
                    c.tracks[i].clips.append(clip)
                } else {
                    var t = Track(name: name, colorIndex: color)
                    t.clips = [clip]
                    c.tracks.append(t)
                }
                // Grow the composition if the clip runs past its end (After Effects doesn't, but it's friendlier).
                if clip.end > c.length { c.length = (clip.end / bpb).rounded(.up) * bpb }
            }
        }
        selectedClips = [clip.id]
        inspector = .clip(cid, clip.id)
        return clip.id
    }

    func updateClip(_ id: UUID, live: Bool = false, _ body: @escaping (inout Clip) -> Void) {
        let cid = activeCompID
        let f: (inout Project) -> Void = { p in p.updateComposition(cid) { $0.updateClip(id, body) } }
        if live { self.live(f) } else { edit(f) }
    }

    func clip(_ id: UUID) -> Clip? {
        guard let c = activeComp, let (ti, ci) = c.locate(clip: id) else { return nil }
        return c.tracks[ti].clips[ci]
    }

    /// Move clips by a beat delta and a track delta (live, during drag), starting from `origin` positions.
    func moveClips(_ origin: Project, ids: Set<UUID>, deltaBeats: Double, deltaTracks: Int) {
        let cid = activeCompID
        guard let comp = origin.composition(cid) else { return }
        var moved: [(Clip, Int)] = []
        for (ti, t) in comp.tracks.enumerated() {
            for c in t.clips where ids.contains(c.id) { moved.append((c, ti)) }
        }
        guard !moved.isEmpty else { return }
        let minStart = moved.map(\.0.start).min() ?? 0
        let d = max(deltaBeats, -minStart)
        let minTrack = moved.map(\.1).min() ?? 0, maxTrack = moved.map(\.1).max() ?? 0
        let dt = max(-minTrack, min(comp.tracks.count - 1 - maxTrack, deltaTracks))
        var newComp = comp
        for ti in newComp.tracks.indices { newComp.tracks[ti].clips.removeAll { ids.contains($0.id) } }
        for (c, ti) in moved {
            var c2 = c
            c2.start = c.start + d
            newComp.tracks[ti + dt].clips.append(c2)
        }
        live { p in
            p.updateComposition(cid) { $0 = newComp }
        }
    }

    func duplicateSelectedClips() {
        guard let comp = activeComp, !selectedClips.isEmpty else { return }
        let sel = comp.tracks.flatMap(\.clips).filter { selectedClips.contains($0.id) }
        let span = (sel.map(\.end).max() ?? 0) - (sel.map(\.start).min() ?? 0)
        var newIDs: Set<UUID> = []
        let bpb = Double(project.beatsPerBar)
        edit { p in
            p.updateComposition(self.activeCompID) { c in
                for ti in c.tracks.indices {
                    for clip in c.tracks[ti].clips where self.selectedClips.contains(clip.id) {
                        var copy = clip
                        copy.id = UUID()
                        copy.start = clip.start + span
                        c.tracks[ti].clips.append(copy)
                        newIDs.insert(copy.id)
                    }
                }
                let end = c.contentEnd
                if end > c.length { c.length = (end / bpb).rounded(.up) * bpb }
            }
        }
        selectedClips = newIDs
    }

    func deleteSelectedClips() {
        guard !selectedClips.isEmpty else { return }
        let ids = selectedClips
        edit { p in
            p.updateComposition(self.activeCompID) { c in
                for ti in c.tracks.indices { c.tracks[ti].clips.removeAll { ids.contains($0.id) } }
            }
        }
        selectedClips = []
        if case .clip? = inspector { inspector = .composition(activeCompID) }
    }

    /// Split selected clips at the playhead.
    func splitSelectedClips(at beat: Double) {
        edit { p in
            p.updateComposition(self.activeCompID) { c in
                for ti in c.tracks.indices {
                    var add: [Clip] = []
                    for ci in c.tracks[ti].clips.indices {
                        let clip = c.tracks[ti].clips[ci]
                        guard self.selectedClips.contains(clip.id), beat > clip.start + 0.01, beat < clip.end - 0.01 else { continue }
                        var right = clip
                        right.id = UUID()
                        right.start = beat
                        right.length = clip.end - beat
                        right.offset = clip.offset + (beat - clip.start)
                        c.tracks[ti].clips[ci].length = beat - clip.start
                        add.append(right)
                    }
                    c.tracks[ti].clips += add
                }
            }
        }
    }

    /// Give a clip its own copy of its source so edits no longer affect other uses.
    func makeUnique(_ clipID: UUID) {
        guard let c = clip(clipID), let idx = project.index(of: c.assetID), let copy = duplicated(project.assets[idx]) else { return }
        let cid = activeCompID
        edit { p in
            p.assets.insert(copy, at: idx + 1)
            p.updateComposition(cid) { $0.updateClip(clipID) { $0.assetID = copy.id } }
        }
    }

    /// After Effects "Pre-compose": move selected clips into a new composition and replace them with one clip.
    func precomposeSelection() {
        guard let comp = activeComp, !selectedClips.isEmpty else { return }
        let sel = selectedClips
        let start = comp.tracks.flatMap(\.clips).filter { sel.contains($0.id) }.map(\.start).min() ?? 0
        let end = comp.tracks.flatMap(\.clips).filter { sel.contains($0.id) }.map(\.end).max() ?? 4
        let bar = Double(project.beatsPerBar)
        let s0 = (start / bar).rounded(.down) * bar
        var inner = Composition(length: max(bar, ((end - s0) / bar).rounded(.up) * bar))
        var firstTrack: Int?
        for (ti, t) in comp.tracks.enumerated() {
            let clips = t.clips.filter { sel.contains($0.id) }
            guard !clips.isEmpty else { continue }
            if firstTrack == nil { firstTrack = ti }
            // Inner tracks inherit the track's mix and effects so the precomp sounds identical.
            var nt = Track(name: t.name, colorIndex: t.colorIndex)
            nt.clips = clips.map { var c = $0; c.start -= s0; return c }
            nt.volume = t.volume
            nt.pan = t.pan
            nt.mute = t.mute
            nt.solo = t.solo
            nt.effects = t.effects.map { var e = $0; e.id = UUID(); return e }
            inner.tracks.append(nt)
        }
        let asset = Asset(name: project.uniqueName("Precomp"), colorIndex: nextColor(), content: .composition(inner))
        let clip = Clip(assetID: asset.id, start: s0, length: inner.length)
        var holder = Track(name: asset.name, colorIndex: asset.colorIndex)
        holder.clips = [clip]
        let insertAt = firstTrack ?? 0
        edit { p in
            p.assets.append(asset)
            p.updateComposition(self.activeCompID) { c in
                for ti in c.tracks.indices { c.tracks[ti].clips.removeAll { sel.contains($0.id) } }
                // A fresh track, so the outer track's effects don't apply twice.
                c.tracks.insert(holder, at: insertAt)
            }
        }
        selectedClips = [clip.id]
        inspector = .clip(activeCompID, clip.id)
    }

    /// Drop a pattern/asset onto an empty spot: create the asset first, then the clip.
    func createPatternClip(kind: AssetKind, at start: Double, track: UUID?) {
        let id: AssetID
        switch kind {
        case .drums: id = newBeat()
        default: id = newPattern()
        }
        if let c = addClip(asset: id, at: start, track: track) { open(asset: id, clip: c) }
    }

    // MARK: - Effects

    func effects(of host: EffectHost) -> [Effect] {
        switch host {
        case .composition(let id): return project.composition(id)?.effects ?? []
        case .track(let cid, let tid):
            guard let c = project.composition(cid), let i = c.trackIndex(tid) else { return [] }
            return c.tracks[i].effects
        case .clip(let cid, let kid):
            guard let c = project.composition(cid), let (ti, ci) = c.locate(clip: kid) else { return [] }
            return c.tracks[ti].clips[ci].effects
        }
    }

    func updateEffects(_ host: EffectHost, live: Bool = false, _ body: @escaping (inout [Effect]) -> Void) {
        let f: (inout Project) -> Void = { p in
            switch host {
            case .composition(let id): p.updateComposition(id) { body(&$0.effects) }
            case .track(let cid, let tid):
                p.updateComposition(cid) { c in if let i = c.trackIndex(tid) { body(&c.tracks[i].effects) } }
            case .clip(let cid, let kid):
                p.updateComposition(cid) { $0.updateClip(kid) { body(&$0.effects) } }
            }
        }
        if live { self.live(f) } else { edit(f) }
    }

    func addEffect(_ kind: String, to host: EffectHost) {
        guard let d = EffectRegistry.descriptor(kind) else { return }
        let e = d.makeEffect()
        updateEffects(host) { $0.append(e) }
        switch host {
        case .composition(let id): inspector = .composition(id)
        case .track(let c, let t): inspector = .track(c, t)
        case .clip(let c, let k): inspector = .clip(c, k)
        }
        workspace.reveal(.inspector)
    }

    /// Effect host for whatever the inspector is showing.
    var currentEffectHost: EffectHost? {
        switch inspector {
        case .composition(let id)?: return .composition(id)
        case .track(let c, let t)?: return .track(c, t)
        case .clip(let c, let k)?: return .clip(c, k)
        case .asset(let a)?: return project.composition(a) != nil ? .composition(a) : nil
        case .slot(let c, let t, _)?: return .track(c, t)
        case nil: return .composition(activeCompID)
        }
    }

    // MARK: - Session

    func setSlot(track: UUID, scene: Int, asset: AssetID?) {
        if let a = asset, !canPlace(a, in: activeCompID) { NSSound.beep(); return }
        edit { p in
            p.updateComposition(self.activeCompID) { c in
                guard let i = c.trackIndex(track) else { return }
                if let a = asset { c.tracks[i].slots[scene] = SessionClip(assetID: a) } else { c.tracks[i].slots[scene] = nil }
                if scene >= c.sceneCount { c.sceneCount = scene + 1 }
            }
        }
    }

    func launch(track: UUID, scene: Int) {
        engine.launch(track: track, scene: scene)
        poll()
    }

    func launchScene(_ scene: Int) {
        guard let comp = activeComp else { return }
        var map: [UUID: Bool] = [:]
        for t in comp.tracks { map[t.id] = t.slots[scene] != nil }
        engine.launchScene(scene, tracks: map)
        poll()
    }

    // MARK: - Pattern position (for editor playheads)

    /// Where `asset` is currently playing, in its own beats, if it is playing in the active composition.
    func localPosition(of asset: AssetID, at pos: Double) -> Double? {
        guard let comp = activeComp else { return nil }
        let len = max(project.sourceLength(of: asset), 0.0001)
        for t in comp.tracks {
            if let s = transport.sessions[t.id], let scene = s.playing, t.slots[scene]?.assetID == asset {
                return max(0, transport.sessionBeat - s.launchBeat).truncatingRemainder(dividingBy: len)
            }
            for c in t.clips where c.assetID == asset && pos >= c.start && pos < c.end {
                let src = c.offset + pos - c.start
                if c.loops { return src.truncatingRemainder(dividingBy: len) }
                return src < len ? src : nil
            }
        }
        return nil
    }

    // MARK: - Files

    func newProject() {
        guard confirmDiscard() else { return }
        load(DemoProject.empty(), url: nil)
    }

    func openDemo() {
        guard confirmDiscard() else { return }
        load(DemoProject.make(), url: nil)
    }

    func openDialog() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Store.shawType, .json]
        if panel.runModal() == .OK, let url = panel.url { open(url: url) }
    }

    func open(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let p = try JSONDecoder().decode(Project.self, from: data)
            load(p, url: url)
        } catch {
            showAlert("Couldn't open project", error.localizedDescription)
        }
    }

    private func load(_ p: Project, url: URL?) {
        engine.stop()
        var p = p
        p.migrateDrumPatterns()
        project = p
        fileURL = url
        dirty = false
        undoStack = []
        redoStack = []
        canUndo = false
        canRedo = false
        activeCompID = p.mainCompositionID
        openComps = [p.mainCompositionID]
        selectedClips = []
        inspector = nil
        pianoRollAsset = p.assets.first { $0.kind == .notes }?.id
        engine.seek(0)
        refreshEngine()
        scheduleAutosave()
        fitRequest += 1
    }

    func save() {
        if let url = fileURL { write(to: url) } else { saveAs() }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Store.shawType]
        panel.nameFieldStringValue = project.name + ".shaw"
        if panel.runModal() == .OK, let url = panel.url {
            project.name = url.deletingPathExtension().lastPathComponent
            write(to: url)
            fileURL = url
        }
    }

    private func write(to url: URL) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(project).write(to: url, options: .atomic)
            dirty = false
        } catch {
            showAlert("Couldn't save", error.localizedDescription)
        }
    }

    func exportAudio() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        let compName = activeAsset?.name ?? "Mix"
        panel.nameFieldStringValue = "\(project.name) - \(compName).wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let p = project, cid = activeCompID
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try OfflineRenderer.export(project: p, composition: cid, to: url)
                DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch {
                DispatchQueue.main.async { self.showAlert("Export failed", error.localizedDescription) }
            }
        }
    }

    static let shawType = UTType(exportedAs: "com.shaw.project", conformingTo: .json)

    // MARK: Autosave

    static var autosaveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shaw")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Autosave.shaw")
    }

    static func restoreAutosave() -> Project? {
        guard let data = try? Data(contentsOf: autosaveURL) else { return nil }
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    private func scheduleAutosave() {
        guard !headless, !isolated else { return }
        autosaveWork?.cancel()
        let p = project
        let work = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(p) { try? data.write(to: Store.autosaveURL, options: .atomic) }
            }
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: Alerts

    func showAlert(_ title: String, _ message: String) {
        guard !headless else { return }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    func confirm(_ title: String, _ message: String) -> Bool {
        guard !headless else { return true }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    private func confirmDiscard() -> Bool {
        guard dirty, fileURL != nil || !undoStack.isEmpty else { return true }
        return confirm("Discard unsaved changes?", "Your current project has changes that haven't been saved to a file.")
    }
}
