import AppKit
import ShawCore

extension Store {
    // MARK: - Merging clips into one

    /// Why the given clips can't be merged, or nil if they can. Deliberately strict so a merge
    /// never changes how anything sounds.
    func mergeProblem(_ ids: Set<UUID>) -> String? {
        guard ids.count >= 2 else { return "Select two or more clips on one layer" }
        guard let comp = activeComp else { return "No composition" }
        let located = ids.compactMap { comp.locate(clip: $0) }
        guard located.count == ids.count else { return "Some clips aren't in this composition" }
        guard Set(located.map(\.0)).count == 1 else { return "Clips are on different layers" }
        let clips = located.map { comp.tracks[$0.0].clips[$0.1] }
        var instrument: Instrument?
        for c in clips {
            guard case .notes(let p)? = project.asset(c.assetID)?.content else {
                return "Only patterns can be merged (not compositions or audio)"
            }
            if let i = instrument, i != p.instrument { return "Clips use different instruments" }
            instrument = p.instrument
        }
        let first = clips[0]
        if clips.contains(where: { $0.mute }) { return "A clip is muted" }
        if clips.contains(where: { $0.gain != first.gain }) { return "Clips have different gain" }
        if clips.contains(where: { $0.effects.contains { !$0.keyframes.isEmpty } }) { return "Clips have keyframes" }
        let fx = Store.effectSignature(first.effects)
        if clips.contains(where: { Store.effectSignature($0.effects) != fx }) { return "Clips have different effects" }
        return nil
    }

    /// Effects compared by what they do, ignoring ids and whether their cards are collapsed.
    static func effectSignature(_ fx: [Effect]) -> [Effect] {
        fx.map { var e = $0; e.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!; e.expanded = true; return e }
    }

    /// Merge the selected clips into one clip of one new pattern, with every note where it was.
    /// The originals are removed (and their patterns too, if nothing else uses them). One undo step.
    func mergeSelectedClips() {
        let ids = selectedClips
        guard mergeProblem(ids) == nil, let comp = activeComp else { NSSound.beep(); return }
        let clips = comp.tracks.flatMap(\.clips).filter { ids.contains($0.id) }.sorted { $0.start < $1.start }
        guard let first = clips.first, let (ti, _) = comp.locate(clip: first.id),
              let firstAsset = project.asset(first.assetID), case .notes(let firstPattern) = firstAsset.content else { return }
        let start = first.start
        let end = clips.map(\.end).max() ?? first.end
        var notes: [Note] = []
        for c in clips {
            guard case .notes(let p)? = project.asset(c.assetID)?.content else { continue }
            notes += Store.audibleNotes(of: c, pattern: p).map { n in var m = n; m.start += c.start - start; return m }
        }
        notes.sort { $0.start < $1.start }
        let pattern = NotePattern(length: end - start, notes: notes, instrument: firstPattern.instrument)
        let sources = Set(clips.map(\.assetID))
        let cid = activeCompID
        var merged = Clip(assetID: UUID(), start: start, length: end - start)
        merged.gain = first.gain
        merged.effects = first.effects.map { var e = $0; e.id = UUID(); return e }
        var newAsset = Asset(name: firstAsset.name, colorIndex: firstAsset.colorIndex, folderID: firstAsset.folderID, content: .notes(pattern))
        merged.assetID = newAsset.id
        let mergedClip = merged
        edit { p in
            p.updateComposition(cid) { c in
                c.tracks[ti].clips.removeAll { ids.contains($0.id) }
                c.tracks[ti].clips.append(mergedClip)
            }
            // Patterns that were only used by the merged clips go away; shared ones stay.
            let unused = sources.filter { p.usageCount(of: $0) == 0 }
            let insertAt = p.index(of: first.assetID) ?? p.assets.count
            p.assets.removeAll { unused.contains($0.id) }
            if !unused.contains(first.assetID) { newAsset.name = p.uniqueName(Store.baseName(firstAsset.name)) }
            p.assets.insert(newAsset, at: min(insertAt, p.assets.count))
        }
        selectedClips = [mergedClip.id]
        inspector = .clip(cid, mergedClip.id)
        if let pr = pianoRollAsset, project.asset(pr) == nil || sources.contains(pr) { open(asset: newAsset.id, clip: mergedClip.id) }
    }

    /// The notes a clip actually plays, in clip time: honours its offset, trimming and looping.
    static func audibleNotes(of c: Clip, pattern p: NotePattern) -> [Note] {
        let L = max(p.length, 1e-6)
        var out: [Note] = []
        func place(_ n: Note, at t: Double) {
            guard t >= 0, t < c.length else { return }
            var m = n
            m.id = UUID()
            m.start = t
            m.length = min(n.length, L - n.start, c.length - t)
            if m.length > 0 { out.append(m) }
        }
        if c.loops {
            var passStart = -c.offset.truncatingRemainder(dividingBy: L)
            while passStart < c.length {
                for n in p.notes where n.start < L { place(n, at: passStart + n.start) }
                passStart += L
            }
        } else {
            for n in p.notes where n.start >= c.offset && n.start < min(L, c.offset + c.length) {
                place(n, at: n.start - c.offset)
            }
        }
        return out
    }
}
