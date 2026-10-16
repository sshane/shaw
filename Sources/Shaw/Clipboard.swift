import AppKit
import ShawCore

/// What ⌘C last copied. Whatever was copied most recently is what ⌘V pastes.
enum ShawClipboard {
    case effects([Effect])
    /// Clips with their track position relative to the first copied clip's track.
    case clips([(clip: Clip, trackOffset: Int)])
}

extension Store {
    // MARK: - Effect selection (After Effects style)

    /// Find an effect anywhere in the project.
    func locateEffect(_ id: UUID) -> (host: EffectHost, effect: Effect)? {
        for a in project.assets {
            guard case .composition(let c) = a.content else { continue }
            if let e = c.effects.first(where: { $0.id == id }) { return (.composition(a.id), e) }
            for t in c.tracks {
                if let e = t.effects.first(where: { $0.id == id }) { return (.track(a.id, t.id), e) }
                for k in t.clips {
                    if let e = k.effects.first(where: { $0.id == id }) { return (.clip(a.id, k.id), e) }
                }
            }
        }
        return nil
    }

    /// Click an effect title: select it (⇧/⌘ adds to the selection within the same layer).
    func selectEffect(_ id: UUID, in host: EffectHost, extend: Bool) {
        focus = .inspector
        if extend && selectedEffectsHost == host {
            if selectedEffects.contains(id) { selectedEffects.remove(id) } else { selectedEffects.insert(id) }
        } else {
            selectedEffects = [id]
        }
        selectedEffectsHost = host
    }

    func selectAllEffects() {
        guard let host = selectedEffectsHost ?? currentEffectHost else { return }
        selectedEffects = Set(effects(of: host).map(\.id))
        selectedEffectsHost = host
    }

    func deleteSelectedEffects() {
        guard let host = selectedEffectsHost, !selectedEffects.isEmpty else { return }
        let ids = selectedEffects
        updateEffects(host) { $0.removeAll { ids.contains($0.id) } }
        selectedEffects = []
    }

    func duplicateSelectedEffects() {
        guard let host = selectedEffectsHost, !selectedEffects.isEmpty else { return }
        let ids = selectedEffects
        var copies: Set<UUID> = []
        updateEffects(host) { fx in
            var out: [Effect] = []
            for e in fx {
                out.append(e)
                if ids.contains(e.id) {
                    var c = e
                    c.id = UUID()
                    out.append(c)
                    copies.insert(c.id)
                }
            }
            fx = out
        }
        selectedEffects = copies
    }

    /// Drag an effect's title onto a list: reorder within the same layer, copy onto another.
    func dropEffect(_ id: UUID, onto host: EffectHost, before target: UUID?) {
        guard let (from, effect) = locateEffect(id) else { return }
        if from == host {
            updateEffects(host) { fx in
                guard let i = fx.firstIndex(where: { $0.id == id }) else { return }
                let e = fx.remove(at: i)
                let j = target.flatMap { t in fx.firstIndex { $0.id == t } } ?? fx.count
                fx.insert(e, at: j)
            }
        } else {
            var copy = effect
            copy.id = UUID()
            updateEffects(host) { fx in
                let j = target.flatMap { t in fx.firstIndex { $0.id == t } } ?? fx.count
                fx.insert(copy, at: j)
            }
            selectedEffects = [copy.id]
            selectedEffectsHost = host
        }
    }

    // MARK: - Copy / paste

    /// ⌘C. Returns false if there was nothing to copy here (so text fields keep working).
    @discardableResult
    func copySelection() -> Bool {
        switch focus {
        case .timeline where !selectedClips.isEmpty:
            guard let comp = activeComp else { return false }
            var items: [(Clip, Int)] = []
            for (ti, t) in comp.tracks.enumerated() {
                for c in t.clips where selectedClips.contains(c.id) { items.append((c, ti)) }
            }
            let base = items.map(\.1).min() ?? 0
            clipboard = .clips(items.map { (clip: $0.0, trackOffset: $0.1 - base) })
            return true
        default:
            guard let host = selectedEffectsHost, !selectedEffects.isEmpty else { return false }
            // Keep the stack order, not selection order.
            clipboard = .effects(effects(of: host).filter { selectedEffects.contains($0.id) })
            return true
        }
    }

    /// ⌘X: copy, then delete what was copied.
    @discardableResult
    func cutSelection() -> Bool {
        guard copySelection() else { return false }
        if case .clips? = clipboard, focus == .timeline { deleteSelectedClips() } else { deleteSelectedEffects() }
        return true
    }

    /// ⌘V: effects go onto whatever is selected (several clips at once, a track, a composition);
    /// clips go at the playhead.
    @discardableResult
    func paste() -> Bool {
        switch clipboard {
        case .effects(let fx)?:
            let targets = effectPasteTargets()
            guard !targets.isEmpty else { NSSound.beep(); return true }
            var newIDs: Set<UUID> = []
            edit { p in
                for host in targets {
                    let copies = fx.map { e -> Effect in var c = e; c.id = UUID(); newIDs.insert(c.id); return c }
                    Store.mutateEffects(&p, host) { $0 += copies }
                }
            }
            if targets.count == 1 {
                selectedEffects = newIDs
                selectedEffectsHost = targets[0]
            }
            return true
        case .clips(let items)?:
            pasteClips(items)
            return true
        case nil:
            return false
        }
    }

    private func effectPasteTargets() -> [EffectHost] {
        let cid = activeCompID
        switch focus {
        case .timeline:
            if !selectedClips.isEmpty { return selectedClips.map { .clip(cid, $0) } }
            if case .track(let c, let t)? = inspector { return [.track(c, t)] }
            return [.composition(cid)]
        case .project:
            let comps = selectedAssets.filter { project.composition($0) != nil }
            if !comps.isEmpty { return comps.map { .composition($0) } }
        case .inspector:
            if let h = selectedEffectsHost ?? currentEffectHost { return [h] }
        default: break
        }
        return currentEffectHost.map { [$0] } ?? []
    }

    private func pasteClips(_ items: [(clip: Clip, trackOffset: Int)]) {
        guard let comp = activeComp, !items.isEmpty else { return }
        let first = items.map(\.clip.start).min() ?? 0
        let at = snapBeat(transport.position)
        // Paste onto the selected layer if there is one, else the clips' original layers.
        var baseTrack = 0
        if case .track(_, let t)? = inspector, let i = comp.trackIndex(t) { baseTrack = i }
        else if let i = comp.locate(clip: items[0].clip.id)?.0 { baseTrack = i }
        var newIDs: Set<UUID> = []
        let bpb = Double(project.beatsPerBar)
        edit { p in
            p.updateComposition(self.activeCompID) { c in
                for item in items {
                    var k = item.clip
                    k.id = UUID()
                    k.start = at + (item.clip.start - first)
                    let ti = baseTrack + item.trackOffset
                    while c.tracks.count <= ti { c.tracks.append(Track(name: "Track \(c.tracks.count + 1)", colorIndex: c.tracks.count)) }
                    c.tracks[ti].clips.append(k)
                    newIDs.insert(k.id)
                }
                let end = c.contentEnd
                if end > c.length { c.length = (end / bpb).rounded(.up) * bpb }
            }
        }
        selectedClips = newIDs
    }

    /// Effect-list mutation on a project value (for batched edits).
    static func mutateEffects(_ p: inout Project, _ host: EffectHost, _ body: (inout [Effect]) -> Void) {
        switch host {
        case .composition(let id): p.updateComposition(id) { body(&$0.effects) }
        case .track(let cid, let tid):
            p.updateComposition(cid) { c in if let i = c.trackIndex(tid) { body(&c.tracks[i].effects) } }
        case .clip(let cid, let kid):
            p.updateComposition(cid) { $0.updateClip(kid) { body(&$0.effects) } }
        }
    }

    func selectAllClips() {
        guard let comp = activeComp else { return }
        selectedClips = Set(comp.tracks.flatMap(\.clips).map(\.id))
    }
}
