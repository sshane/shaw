import AppKit
import ShawCore

/// One keyframed effect parameter, shown as a row of ◆ under its layer in the timeline.
struct AnimatedProperty: Identifiable, Equatable {
    let host: EffectHost
    let effectID: UUID
    let paramID: String
    let label: String
    /// Where this property's time 0 sits in the composition (the clip start for clip effects).
    let origin: Double
    /// Visible span in composition beats (the clip, or the whole composition).
    let span: ClosedRange<Double>

    var id: String { "\(effectID):\(paramID)" }
}

/// Vertical layout of the timeline: each layer plus its open keyframe rows.
struct TrackLayout {
    let tops: [CGFloat]
    let heights: [CGFloat]
    let props: [[AnimatedProperty]]
    let total: CGFloat

    static let propRowHeight: CGFloat = 24

    /// Layer under a content-space y (scroll already added).
    func index(atY y: CGFloat) -> Int? {
        guard y >= 0 else { return nil }
        for i in tops.indices where y < tops[i] + heights[i] { return i }
        return nil
    }

    func top(_ i: Int) -> CGFloat { i < tops.count ? tops[i] : total }
}

extension Store {
    // MARK: - Time

    /// "Now" in a host's own time: clip time for clip effects, composition time otherwise.
    func keyframeTime(for host: EffectHost) -> Double {
        switch host {
        case .clip(let cid, let kid):
            guard cid == activeCompID, let c = clip(kid) else { return 0 }
            return min(c.length, max(0, transport.position - c.start))
        case .track, .composition:
            return transport.position
        }
    }

    /// Composition position of a host-time moment (for jumping the playhead to a keyframe).
    func compositionTime(_ t: Double, for host: EffectHost) -> Double {
        if case .clip(_, let kid) = host, let c = clip(kid) { return c.start + t }
        return t
    }

    func effect(_ id: UUID, in host: EffectHost) -> Effect? { effects(of: host).first { $0.id == id } }

    private func updateEffect(_ id: UUID, in host: EffectHost, live: Bool = false, _ body: @escaping (inout Effect) -> Void) {
        updateEffects(host, live: live) { fx in if let i = fx.firstIndex(where: { $0.id == id }) { body(&fx[i]) } }
    }

    // MARK: - Editing values

    /// Change a parameter. If it's keyframed, this sets (or adds) the keyframe at the playhead, like After Effects.
    func setParam(_ host: EffectHost, effect id: UUID, param: String, value: Double, live: Bool) {
        let t = keyframeTime(for: host)
        updateEffect(id, in: host, live: live) { e in
            if e.isAnimated(param) { e.setKeyframe(param, time: t, value: value) } else { e.params[param] = value }
        }
    }

    /// The stopwatch: start keyframing (first ◆ at the playhead with the current value), or stop and keep the current value.
    func toggleAnimation(_ host: EffectHost, effect id: UUID, param: String) {
        guard let e = effect(id, in: host), let d = EffectRegistry.descriptor(e.kind),
              let def = d.params.first(where: { $0.id == param }) else { return }
        let t = keyframeTime(for: host)
        let current = e.value(of: def, at: t)
        updateEffect(id, in: host) { e in
            if e.isAnimated(param) {
                e.keyframes[param] = nil
                e.params[param] = current
            } else {
                e.keyframes[param] = [Keyframe(time: t, value: current)]
            }
        }
        revealKeyframes(of: host)
    }

    /// ◆ button: add a keyframe at the playhead, or remove the one that's there.
    func toggleKeyframeAtPlayhead(_ host: EffectHost, effect id: UUID, param: String) {
        guard let e = effect(id, in: host), let d = EffectRegistry.descriptor(e.kind),
              let def = d.params.first(where: { $0.id == param }) else { return }
        let t = keyframeTime(for: host)
        let tol = 1.0 / 64
        updateEffect(id, in: host) { e in
            var keys = e.keyframes[param] ?? []
            if let i = keys.firstIndex(where: { abs($0.time - t) <= tol }) {
                keys.remove(at: i)
                if keys.isEmpty { e.params[param] = e.value(of: def, at: t) }
                e.keyframes[param] = keys.isEmpty ? nil : keys
            } else {
                e.setKeyframe(param, time: t, value: e.value(of: def, at: t))
            }
        }
        revealKeyframes(of: host)
    }

    func hasKeyframeAtPlayhead(_ e: Effect, param: String, host: EffectHost) -> Bool {
        let t = keyframeTime(for: host)
        return (e.keyframes[param] ?? []).contains { abs($0.time - t) <= 1.0 / 64 }
    }

    /// ◀ / ▶: jump the playhead to the previous or next keyframe.
    func jumpToKeyframe(_ host: EffectHost, effect id: UUID, param: String, forward: Bool) {
        guard let e = effect(id, in: host) else { return }
        let t = keyframeTime(for: host)
        let keys = (e.keyframes[param] ?? []).map(\.time)
        let target = forward ? keys.first { $0 > t + 1e-6 } : keys.last { $0 < t - 1e-6 }
        if let target { seek(compositionTime(target, for: host)) }
    }

    /// Move one keyframe (live, while dragging its ◆).
    func moveKeyframe(_ prop: AnimatedProperty, key: UUID, time: Double, value: Double) {
        updateEffect(prop.effectID, in: prop.host, live: true) { e in
            guard var keys = e.keyframes[prop.paramID], let i = keys.firstIndex(where: { $0.id == key }) else { return }
            keys[i].time = max(0, time)
            keys[i].value = value
            keys.sort { $0.time < $1.time }
            e.keyframes[prop.paramID] = keys
        }
    }

    func setKeyframeValue(_ prop: AnimatedProperty, key: UUID, value: Double) {
        updateEffect(prop.effectID, in: prop.host) { e in
            guard var keys = e.keyframes[prop.paramID], let i = keys.firstIndex(where: { $0.id == key }) else { return }
            keys[i].value = value
            e.keyframes[prop.paramID] = keys
        }
    }

    func addKeyframe(_ prop: AnimatedProperty, time: Double, value: Double) -> UUID? {
        var newID: UUID?
        updateEffect(prop.effectID, in: prop.host) { e in
            let k = Keyframe(time: max(0, time), value: value)
            newID = k.id
            var keys = e.keyframes[prop.paramID] ?? []
            keys.append(k)
            keys.sort { $0.time < $1.time }
            e.keyframes[prop.paramID] = keys
        }
        return newID
    }

    /// Delete selected ◆s. A property whose last keyframe goes keeps that value as a plain setting.
    func deleteSelectedKeyframes() {
        let ids = selectedKeyframes
        guard !ids.isEmpty else { return }
        edit { p in
            for i in p.assets.indices {
                guard case .composition(var c) = p.assets[i].content else { continue }
                func strip(_ fx: inout [Effect]) {
                    for j in fx.indices {
                        for (pid, keys) in fx[j].keyframes where keys.contains(where: { ids.contains($0.id) }) {
                            let left = keys.filter { !ids.contains($0.id) }
                            if left.isEmpty {
                                fx[j].params[pid] = keys.last?.value
                                fx[j].keyframes[pid] = nil
                            } else {
                                fx[j].keyframes[pid] = left
                            }
                        }
                    }
                }
                strip(&c.effects)
                for t in c.tracks.indices {
                    strip(&c.tracks[t].effects)
                    for k in c.tracks[t].clips.indices { strip(&c.tracks[t].clips[k].effects) }
                }
                p.assets[i].content = .composition(c)
            }
        }
        selectedKeyframes = []
    }

    // MARK: - Timeline rows

    /// Keyframed properties shown under a layer: its own effects, then its clips' effects.
    func animatedProperties(of track: Track, in compID: AssetID) -> [AnimatedProperty] {
        let comp = project.composition(compID)
        let whole = 0...max(1, comp?.length ?? 1)
        var out: [AnimatedProperty] = []
        func add(_ fx: [Effect], host: EffectHost, prefix: String, origin: Double, span: ClosedRange<Double>) {
            for e in fx {
                guard let d = EffectRegistry.descriptor(e.kind) else { continue }
                for def in d.params where e.isAnimated(def.id) {
                    let name = def.name == d.name ? d.name : "\(d.name) · \(def.name)"
                    out.append(AnimatedProperty(host: host, effectID: e.id, paramID: def.id,
                                                label: prefix + name, origin: origin, span: span))
                }
            }
        }
        add(track.effects, host: .track(compID, track.id), prefix: "", origin: 0, span: whole)
        for c in track.clips.sorted(by: { $0.start < $1.start }) {
            let name = project.asset(c.assetID)?.name ?? "Clip"
            add(c.effects, host: .clip(compID, c.id), prefix: "\(name) ▸ ", origin: c.start, span: c.start...c.end)
        }
        return out
    }

    func trackLayout(for comp: Composition) -> TrackLayout {
        var tops: [CGFloat] = [], heights: [CGFloat] = [], props: [[AnimatedProperty]] = []
        var y: CGFloat = 0
        for t in comp.tracks {
            let p = expandedTracks.contains(t.id) ? animatedProperties(of: t, in: activeCompID) : []
            let h = trackHeight + CGFloat(p.count) * TrackLayout.propRowHeight
            tops.append(y)
            heights.append(h)
            props.append(p)
            y += h
        }
        return TrackLayout(tops: tops, heights: heights, props: props, total: y)
    }

    func hasAnimation(_ track: Track) -> Bool {
        track.effects.contains { !$0.keyframes.isEmpty } || track.clips.contains { $0.effects.contains { !$0.keyframes.isEmpty } }
    }

    /// Open the keyframe rows of the layer a host belongs to, so new ◆s are visible right away.
    func revealKeyframes(of host: EffectHost) {
        guard let comp = activeComp else { return }
        switch host {
        case .track(let cid, let tid) where cid == activeCompID: expandedTracks.insert(tid)
        case .clip(let cid, let kid) where cid == activeCompID:
            if let (ti, _) = comp.locate(clip: kid) { expandedTracks.insert(comp.tracks[ti].id) }
        default: break
        }
    }

    // MARK: - Fades

    /// Right-click → Fade In / Fade Out: a Volume effect with two keyframes over the clip's start or end.
    func addFade(clip clipID: UUID, fadeIn: Bool) {
        guard let c = clip(clipID) else { return }
        let host = EffectHost.clip(activeCompID, clipID)
        // A quarter of the clip, at most a bar, so a fade in and a fade out never meet in the middle.
        let len = min(c.length / 4, Double(project.beatsPerBar))
        var fx = effects(of: host)
        var vol = fx.last { $0.kind == "volume" } ?? EffectRegistry.descriptor("volume")!.makeEffect()
        let isNew = !fx.contains { $0.id == vol.id }
        if fadeIn {
            vol.setKeyframe("volume", time: 0, value: -60)
            vol.setKeyframe("volume", time: len, value: 0)
        } else {
            vol.setKeyframe("volume", time: c.length - len, value: 0)
            vol.setKeyframe("volume", time: c.length, value: -60)
        }
        if isNew { fx.append(vol) } else if let i = fx.firstIndex(where: { $0.id == vol.id }) { fx[i] = vol }
        let result = fx
        updateEffects(host) { $0 = result }
        inspector = .clip(activeCompID, clipID)
        revealKeyframes(of: host)
    }
}
