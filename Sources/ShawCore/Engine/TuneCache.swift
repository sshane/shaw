import Foundation

/// Tuned versions of recordings, rendered in the background whenever a recording's Tune settings
/// (or, with an Auto key, the song's key) change. Playback keeps each recording's last finished
/// version until its next one is ready, so dragging a control never drops back to the untuned take.
///
/// Each recording asks as its own owner (its asset), so two recordings of the same file can be
/// tuned differently. Versions nobody uses any more are let go, a few seconds after they stop
/// playing, so the audio thread is never the one to free them.
public final class TuneCache {
    struct Job: Hashable {
        let path: String
        let tune: VocalTune
        let songKey: VocalTune.Key?
    }

    /// A take's pitch, its notes, and the key they're in (computed once per file).
    struct Analysis {
        let track: PitchTrack
        let notes: [SungNote]
        let key: VocalTune.Key?
    }

    private var analyses: [String: Analysis] = [:]
    private var rendered: [Job: SampleData] = [:]
    /// When each version was last asked for: recent ones stay, so undo and redo are instant.
    private var used: [Job: Date] = [:]
    /// What each owner asks for now, and the last version it had (played while the next renders).
    private var current: [String: Job] = [:]
    private var shown: [String: Job] = [:]
    /// Waiting to render, oldest first, with the audio to render from.
    private var queue: [(Job, SampleData)] = []
    private var inFlight: Set<Job> = []
    private var working = false
    private let lock = NSLock()
    /// How long a version nobody plays any more stays at hand.
    static let linger: TimeInterval = 20

    /// Called on the main queue when a new version of a file is ready.
    public var onReady: ((String) -> Void)?

    private func job(_ path: String, _ tune: VocalTune, _ songKey: VocalTune.Key?) -> Job {
        // Only an Auto key depends on the song: a chosen key doesn't re-render when the song's notes change.
        Job(path: path, tune: tune, songKey: tune.scale == .auto ? songKey : nil)
    }

    /// `owner`'s take tuned with these settings; while that renders, the owner's last version
    /// (nil before the first).
    public func tuned(_ owner: String, path: String, source: SampleData, tune: VocalTune, songKey: VocalTune.Key?) -> SampleData? {
        let j = job(path, tune, songKey)
        lock.lock(); defer { lock.unlock() }
        current[owner] = j
        used[j] = Date()
        if let d = rendered[j] {
            shown[owner] = j
            return d
        }
        if !inFlight.contains(j) && !queue.contains(where: { $0.0 == j }) { queue.append((j, source)) }
        if !working {
            working = true
            DispatchQueue.global(qos: .userInitiated).async { self.work() }
        }
        return shown[owner].flatMap { rendered[$0] }
    }

    /// The same, rendered right away if it isn't ready (export).
    public func tunedSync(_ owner: String, path: String, source: SampleData, tune: VocalTune, songKey: VocalTune.Key?) -> SampleData {
        let j = job(path, tune, songKey)
        lock.lock()
        current[owner] = j
        used[j] = Date()
        // Already rendering in the background: wait for it rather than doing it twice.
        while inFlight.contains(j) {
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.01)
            lock.lock()
        }
        if let d = rendered[j] { shown[owner] = j; lock.unlock(); return d }
        queue.removeAll { $0.0 == j }
        inFlight.insert(j)
        lock.unlock()
        let d = render(j, source)
        finish(j, d)
        lock.lock()
        shown[owner] = j
        lock.unlock()
        DispatchQueue.main.async { self.onReady?(path) }
        return d
    }

    /// Forget the owners that no longer have Tune on (deleted, turned off, another project).
    public func keep(owners: Set<String>) {
        lock.lock()
        for o in Array(current.keys) where !owners.contains(o) { current[o] = nil }
        for o in Array(shown.keys) where !owners.contains(o) { shown[o] = nil }
        let old = evict()
        lock.unlock()
        release(old)
    }

    /// The key a file is sung in, once it has been analyzed.
    public func takeKey(_ path: String) -> VocalTune.Key? {
        lock.lock(); defer { lock.unlock() }
        return analyses[path]?.key
    }

    /// True while a version of a file that's wanted renders.
    public func isRendering(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let wanted = Set(current.values)
        return inFlight.contains { $0.path == path } || queue.contains { $0.0.path == path && wanted.contains($0.0) }
    }

    private func work() {
        while true {
            lock.lock()
            // Settings someone has moved on from (the middle of a slider drag) aren't worth rendering.
            let wanted = Set(current.values)
            queue.removeAll { !wanted.contains($0.0) }
            guard !queue.isEmpty else {
                working = false
                lock.unlock()
                return
            }
            let (j, source) = queue.removeFirst()
            inFlight.insert(j)
            lock.unlock()
            finish(j, render(j, source))
            DispatchQueue.main.async { self.onReady?(j.path) }
        }
    }

    private func finish(_ j: Job, _ d: SampleData) {
        lock.lock()
        inFlight.remove(j)
        rendered[j] = d
        used[j] = Date()
        let old = evict()
        lock.unlock()
        release(old)
    }

    /// Drop versions no owner plays or asks for and nobody has wanted lately (call with the lock held).
    private func evict() -> [SampleData] {
        let keep = Set(current.values).union(shown.values)
        let now = Date()
        var old: [SampleData] = []
        for (j, d) in rendered where !keep.contains(j) && now.timeIntervalSince(used[j] ?? .distantPast) > Self.linger {
            rendered[j] = nil
            used[j] = nil
            old.append(d)
        }
        let paths = Set(rendered.keys.map(\.path)).union(keep.map(\.path)).union(inFlight.map(\.path))
        for p in Array(analyses.keys) where !paths.contains(p) { analyses[p] = nil }
        for j in Array(used.keys) where rendered[j] == nil && !keep.contains(j) && now.timeIntervalSince(used[j]!) > Self.linger { used[j] = nil }
        return old
    }

    /// Let go of versions a little later, once no graph can be playing them.
    private func release(_ old: [SampleData]) {
        if !old.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { _ = old } }
    }

    private func analysis(_ path: String, _ source: SampleData) -> Analysis {
        lock.lock()
        if let a = analyses[path] { lock.unlock(); return a }
        lock.unlock()
        var mono = Array(UnsafeBufferPointer(start: source.l, count: source.frames))
        if source.channels > 1 { for i in mono.indices { mono[i] = (mono[i] + source.r[i]) / 2 } }
        let track = PitchTracker.track(mono, sampleRate: source.sampleRate)
        let notes = NoteFinder.notes(in: track)
        let a = Analysis(track: track, notes: notes, key: VocalTune.key(of: notes))
        lock.lock()
        analyses[path] = a
        lock.unlock()
        return a
    }

    private func render(_ j: Job, _ source: SampleData) -> SampleData {
        let a = analysis(j.path, source)
        let classes = VocalTune.pitchClasses(j.tune.key(song: j.songKey, take: a.key))
        let cents = j.tune.corrections(a.track, notes: a.notes, classes: classes)
        var channels = [Array(UnsafeBufferPointer(start: source.l, count: source.frames))]
        if source.channels > 1 { channels.append(Array(UnsafeBufferPointer(start: source.r, count: source.frames))) }
        let out = PitchShifter.shift(channels, track: a.track, cents: cents)
        return SampleData(left: out[0], right: out.count > 1 ? out[1] : nil, sampleRate: source.sampleRate)
    }
}
