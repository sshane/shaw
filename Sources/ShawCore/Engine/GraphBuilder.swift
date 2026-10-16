import Foundation

/// The root of a built graph plus the state objects it uses.
final class RenderGraph {
    let root: CompNode?
    let rootLength: Double
    let states: [String: AnyObject]
    init(root: CompNode?, rootLength: Double, states: [String: AnyObject]) {
        self.root = root
        self.rootLength = rootLength
        self.states = states
    }
}

/// Builds a `RenderGraph` from a project snapshot, reusing state objects from the
/// previous graph by path so playback continues seamlessly across edits.
struct GraphBuilder {
    let project: Project
    let sampleRate: Double
    let previous: [String: AnyObject]
    let samples: SampleLibrary
    /// Meters and session state for the top-level composition's tracks.
    let meters: (UUID) -> LevelMeter?
    let session: (UUID) -> SessionTrackState?
    let compMeter: LevelMeter?

    private(set) var states: [String: AnyObject] = [:]
    static let maxDepth = 16

    init(project: Project, sampleRate: Double, previous: [String: AnyObject], samples: SampleLibrary,
         meters: @escaping (UUID) -> LevelMeter? = { _ in nil },
         session: @escaping (UUID) -> SessionTrackState? = { _ in nil },
         compMeter: LevelMeter? = nil) {
        self.project = project
        self.sampleRate = sampleRate
        self.previous = previous
        self.samples = samples
        self.meters = meters
        self.session = session
        self.compMeter = compMeter
    }

    mutating func state<T: AnyObject>(_ key: String, _ make: () -> T) -> T {
        if let s = states[key] as? T { return s }
        let s = (previous[key] as? T) ?? make()
        states[key] = s
        return s
    }

    mutating func build(root id: AssetID) -> RenderGraph {
        let node = buildComp(id, path: "c:\(id)", depth: 0, top: true)
        return RenderGraph(root: node, rootLength: project.composition(id)?.length ?? 0, states: states)
    }

    mutating func chain(_ effects: [Effect], path: String) -> EffectChain {
        var slots: [EffectSlot] = []
        for e in effects where e.enabled {
            guard let d = EffectRegistry.descriptor(e.kind) else { continue }
            let sr = sampleRate
            let proc: EffectProcessor = state("\(path)/fx:\(e.id):\(e.kind)") { EffectBox(d.make(sr)) }.processor
            var animated: [AnimatedParam] = []
            for (pid, keys) in e.keyframes where !keys.isEmpty {
                guard let i = d.params.firstIndex(where: { $0.id == pid }) else { continue }
                let def = d.params[i]
                animated.append(AnimatedParam(index: i, keys: keys.map { var k = $0; k.value = def.clamp(k.value); return k },
                                              hold: def.choices != nil))
            }
            slots.append(EffectSlot(processor: proc, params: d.params.resolve(e.params), animated: animated))
        }
        return EffectChain(slots)
    }

    mutating func buildComp(_ id: AssetID, path: String, depth: Int, top: Bool) -> CompNode? {
        guard depth < GraphBuilder.maxDepth, let comp = project.composition(id) else { return nil }
        let anySolo = comp.hasSolo
        var tracks: [TrackNode] = []
        for t in comp.tracks {
            let tp = "\(path)/t:\(t.id)"
            var clips: [ClipNode] = []
            for c in t.clips {
                if let node = buildClip(assetID: c.assetID, start: c.start, length: c.length, offset: c.offset,
                                        loops: c.loops, gainDb: c.gain, muted: c.mute, effects: c.effects,
                                        path: "\(tp)/k:\(c.id)", depth: depth) {
                    clips.append(node)
                }
            }
            var slots: [Int: ClipNode] = [:]
            if top {
                for (scene, sc) in t.slots {
                    if let node = buildClip(assetID: sc.assetID, start: 0, length: 1e12, offset: 0, loops: true,
                                            gainDb: 0, muted: false, effects: [], path: "\(tp)/slot:\(sc.id)", depth: depth) {
                        slots[scene] = node
                    }
                }
            }
            let (pl, pr) = panGains(t.pan)
            let g = Float(dbToGain(t.volume))
            let audible = !t.mute && (!anySolo || t.solo)
            tracks.append(TrackNode(clips: clips, slots: slots, chain: chain(t.effects, path: tp),
                                    gainL: pl * g, gainR: pr * g, audible: audible,
                                    state: state("\(tp)/state") { TrackState() },
                                    meter: top ? meters(t.id) : nil,
                                    session: top ? session(t.id) : nil))
        }
        return CompNode(tracks: tracks, chain: chain(comp.effects, path: path), gain: Float(dbToGain(comp.volume)),
                        state: state("\(path)/state") { CompState() }, meter: top ? compMeter : nil)
    }

    mutating func buildClip(assetID: AssetID, start: Double, length: Double, offset: Double, loops: Bool, gainDb: Double,
                            muted: Bool, effects: [Effect], path: String, depth: Int) -> ClipNode? {
        guard let asset = project.asset(assetID) else { return nil }
        let sp = "\(path)/s"
        let sr = sampleRate
        let source: SourceNode
        switch asset.content {
        case .composition:
            source = buildComp(assetID, path: sp, depth: depth + 1, top: false) ?? SilentSource()
        case .audio(let ref):
            source = AudioSourceNode(data: samples.data(for: ref.path), state: state(sp) { AudioState() })
        case .notes(let p):
            if let kit = p.instrument.kit {
                source = KitNoteSourceNode(pattern: p, kit: kit, sampleRate: sr, player: state("\(sp):kit") { DrumPlayer() })
            } else {
                source = NoteSourceNode(pattern: p, state: state("\(sp):notes") { NoteState(sampleRate: sr) })
            }
        case .drums(let p):
            source = DrumSourceNode(pattern: p, sampleRate: sr, player: state("\(sp):drums") { DrumPlayer() })
        }
        return ClipNode(start: start, length: length, offset: offset, loops: loops,
                        sourceLength: project.sourceLength(of: assetID), gain: Float(dbToGain(gainDb)), muted: muted,
                        source: source, chain: chain(effects, path: path), state: state("\(path)/state") { ClipState() })
    }
}

/// Class box so protocol-typed processors can live in the state cache.
final class EffectBox {
    let processor: EffectProcessor
    init(_ p: EffectProcessor) { processor = p }
}
