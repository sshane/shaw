import Foundation

// The render graph is rebuilt on the main thread from an immutable `Project`
// snapshot whenever something changes. Nodes are cheap and disposable; anything
// with DSP state (voices, reverb tails, filter memory) lives in "state" objects
// that are looked up by a path key, so they survive rebuilds and a reverb keeps
// ringing while you drag a slider.
//
// A linked composition used three times gets three separate render subtrees
// (different paths) built from the same composition data. That is what makes
// edits propagate everywhere while each instance still has its own tail.

/// Frames needed to cover `beats`, rounded up, but forgiving floating-point noise so a
/// boundary that is mathematically exact never spills one frame late.
@inline(__always) func framesUntil(_ beats: Double, _ bps: Double) -> Int {
    max(1, Int((beats / bps - 1e-4).rounded(.up)))
}

protocol SourceNode: AnyObject {
    /// Add source output for the source-local range starting at `beat`.
    func render(beat: Double, frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                ctx: RenderContext, songBeat: Double)
    /// Keep releasing voices / effect tails with no new events.
    func renderTail(frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                    ctx: RenderContext, songBeat: Double)
    /// Hard stop: the clip went inactive.
    func stop()
    /// Whether `renderTail` can produce sound.
    var hasTail: Bool { get }
    /// Whether the source is raw audio (gets declick fades at clip edges).
    var isAudio: Bool { get }
}

// MARK: - Effects

struct AnimatedParam {
    let index: Int
    let keys: [Keyframe]
    let hold: Bool
}

final class EffectSlot {
    let processor: EffectProcessor
    let params: [Double]
    let animated: [AnimatedParam]
    /// Scratch copy of `params` with keyframed values filled in each block (owned, so no allocation).
    var live: [Double]

    init(processor: EffectProcessor, params: [Double], animated: [AnimatedParam] = []) {
        self.processor = processor
        self.params = params
        self.animated = animated
        self.live = params
    }
}

final class EffectChain {
    let slots: [EffectSlot]
    init(_ slots: [EffectSlot]) { self.slots = slots }
    var isEmpty: Bool { slots.isEmpty }

    /// - Parameters:
    ///   - beat: song position (for tempo-synced effects)
    ///   - time: the host's own time, where its keyframes live (clip time or composition time)
    @inline(__always) func process(_ buf: StereoBuffer, frames: Int, ctx: RenderContext, beat: Double, time: Double) {
        for s in slots {
            if s.animated.isEmpty {
                s.processor.process(buf, frames: frames, params: s.params, ctx: ctx, beat: beat)
            } else {
                for a in s.animated { s.live[a.index] = Keyframe.interpolate(a.keys, at: time, hold: a.hold) }
                s.processor.process(buf, frames: frames, params: s.live, ctx: ctx, beat: beat)
            }
        }
    }

    func reset() { for s in slots { s.processor.reset() } }
}

// MARK: - Meters

public final class LevelMeter {
    public var peakL: Float = 0
    public var peakR: Float = 0
    public init() {}

    func update(_ buf: StereoBuffer, _ n: Int) {
        var a: Float = 0, b: Float = 0
        for i in 0..<n {
            a = max(a, abs(buf.l[i]))
            b = max(b, abs(buf.r[i]))
        }
        // Instant attack, ~300 ms fall at typical block sizes.
        peakL = max(a, peakL * 0.93)
        peakR = max(b, peakR * 0.93)
    }

    public func decay() { peakL *= 0.9; peakR *= 0.9 }
}

// MARK: - Clip

final class ClipState {
    var active = false
    var silentFrames = 0
    var tailFrames = 0
    let buffer = StereoBuffer()
}

final class ClipNode {
    let start: Double, end: Double, offset: Double
    let loops: Bool
    let sourceLength: Double
    let gain: Float
    let muted: Bool
    let source: SourceNode
    let chain: EffectChain
    let state: ClipState

    init(start: Double, length: Double, offset: Double, loops: Bool, sourceLength: Double, gain: Float, muted: Bool,
         source: SourceNode, chain: EffectChain, state: ClipState) {
        self.start = start
        self.end = start + length
        self.offset = offset
        self.loops = loops
        self.sourceLength = max(sourceLength, 1e-6)
        self.gain = gain
        self.muted = muted
        self.source = source
        self.chain = chain
        self.state = state
    }

    func deactivate() {
        guard state.active else { return }
        state.active = false
        source.stop()
        chain.reset()
    }

    /// Render the clip for local beats [b0, b0 + frames*bps) and mix into `out`.
    func render(b0: Double, frames: Int, ctx: RenderContext, songBeat: Double, into out: StereoBuffer, tail: Bool) {
        if muted { deactivate(); return }
        let bps = ctx.beatsPerSample
        let bEnd = b0 + Double(frames) * bps
        let buf = state.buffer
        let inRange = !tail && bEnd > start && b0 < end

        if !inRange {
            guard state.active else { return }
            if !source.hasTail && chain.isEmpty { deactivate(); return }
            buf.clear(frames)
            source.renderTail(frames: frames, l: buf.l, r: buf.r, ctx: ctx, songBeat: songBeat)
            chain.process(buf, frames: frames, ctx: ctx, beat: songBeat, time: b0 - start)
            trackTail(frames, ctx)
            buf.mix(into: out, frames, gainL: gain, gainR: gain)
            return
        }

        state.active = true
        state.tailFrames = 0
        state.silentFrames = 0
        buf.clear(frames)
        var f = 0
        while f < frames {
            let b = b0 + Double(f) * bps
            let sb = songBeat + Double(f) * bps
            let l = buf.l + f, r = buf.r + f
            if b < start {
                f += min(frames - f, framesUntil(start - b, bps))
                continue
            }
            if b >= end {
                source.renderTail(frames: frames - f, l: l, r: r, ctx: ctx, songBeat: sb)
                break
            }
            var src = offset + (b - start)
            var segEnd = end
            if loops {
                src = src.truncatingRemainder(dividingBy: sourceLength)
                // A frame within half a sample of the end *is* the wrap point (floating-point error).
                if sourceLength - src < bps * 0.5 { src = 0 }
                segEnd = min(end, b + (sourceLength - src))
            } else if src >= sourceLength - bps * 0.5 {
                // Past the end of the content: silence (but let notes and tails ring).
                let n = min(frames - f, framesUntil(end - b, bps))
                source.renderTail(frames: n, l: l, r: r, ctx: ctx, songBeat: sb)
                f += n
                continue
            } else {
                segEnd = min(end, b + (sourceLength - src))
            }
            let n = min(frames - f, framesUntil(segEnd - b, bps))
            source.render(beat: src, frames: n, l: l, r: r, ctx: ctx, songBeat: sb)
            f += n
        }
        if source.isAudio { declickEnd(b0: b0, frames: frames, bps: bps) }
        chain.process(buf, frames: frames, ctx: ctx, beat: songBeat, time: b0 - start)
        buf.mix(into: out, frames, gainL: gain, gainR: gain)
    }

    /// ~3 ms fade before the clip end so trimmed audio never clicks.
    private func declickEnd(b0: Double, frames: Int, bps: Double) {
        let fade = 128.0 * bps
        let fadeStart = end - fade
        let bEnd = b0 + Double(frames) * bps
        guard bEnd > fadeStart, b0 < end else { return }
        let buf = state.buffer
        for i in 0..<frames {
            let b = b0 + Double(i) * bps
            if b >= fadeStart && b < end {
                let g = Float((end - b) / fade)
                buf.l[i] *= g; buf.r[i] *= g
            } else if b >= end {
                if !source.hasTail { buf.l[i] = 0; buf.r[i] = 0 }
            }
        }
    }

    private func trackTail(_ frames: Int, _ ctx: RenderContext) {
        state.tailFrames += frames
        if state.buffer.peak(frames) < 0.00002 { state.silentFrames += frames } else { state.silentFrames = 0 }
        if state.silentFrames > Int(ctx.sampleRate * 0.4) || state.tailFrames > Int(ctx.sampleRate * 12) {
            deactivate()
        }
    }
}

// MARK: - Session (clip launcher)

/// Monotonic beat counter for session clips. Unlike the transport position it
/// never jumps on loop wraps or seeks, so launched clips stay in phase.
public final class SessionClock {
    public var beat = 0.0
    public init() {}
}

/// Launch state for one track's session slots. Mutated on the main thread
/// only while holding the engine's render lock. Beats are on the session clock.
public final class SessionTrackState {
    public var playing: Int?        // scene index
    public var launchBeat: Double = 0
    public var queued: Int?         // scene index, or -1 = stop
    public var queuedBeat: Double = 0
    let clock: SessionClock
    public init(clock: SessionClock) { self.clock = clock }

    public var isActive: Bool { playing != nil || (queued ?? -1) >= 0 }
}

// MARK: - Track

final class TrackState {
    let buffer = StereoBuffer()
}

final class TrackNode {
    let clips: [ClipNode]
    let slots: [Int: ClipNode]
    let chain: EffectChain
    let gainL: Float, gainR: Float
    let audible: Bool
    let state: TrackState
    let meter: LevelMeter?
    let session: SessionTrackState?

    init(clips: [ClipNode], slots: [Int: ClipNode], chain: EffectChain, gainL: Float, gainR: Float, audible: Bool,
         state: TrackState, meter: LevelMeter?, session: SessionTrackState?) {
        self.clips = clips
        self.slots = slots
        self.chain = chain
        self.gainL = gainL
        self.gainR = gainR
        self.audible = audible
        self.state = state
        self.meter = meter
        self.session = session
    }

    func render(b0: Double, frames: Int, ctx: RenderContext, songBeat: Double, into out: StereoBuffer, tail: Bool) {
        guard audible else {
            meter?.decay()
            return
        }
        let buf = state.buffer
        buf.clear(frames)
        if let s = session, !tail, s.isActive || s.queued != nil {
            renderSession(s, frames: frames, ctx: ctx, songBeat: songBeat, into: buf)
            // Arrangement clips that are still ringing out keep their tails.
            for c in clips where c.state.active {
                c.render(b0: b0, frames: frames, ctx: ctx, songBeat: songBeat, into: buf, tail: true)
            }
        } else {
            for c in clips {
                c.render(b0: b0, frames: frames, ctx: ctx, songBeat: songBeat, into: buf, tail: tail)
            }
            for (_, c) in slots where c.state.active {
                c.render(b0: 0, frames: frames, ctx: ctx, songBeat: songBeat, into: buf, tail: true)
            }
        }
        chain.process(buf, frames: frames, ctx: ctx, beat: songBeat, time: b0)
        meter?.update(buf, frames)
        buf.mix(into: out, frames, gainL: gainL, gainR: gainR)
    }

    private func renderSession(_ s: SessionTrackState, frames: Int, ctx: RenderContext, songBeat: Double,
                               into buf: StereoBuffer) {
        let bps = ctx.beatsPerSample
        // The slot was removed (or its asset deleted) while playing.
        if let p = s.playing, slots[p] == nil { s.playing = nil }
        var f = 0
        while f < frames {
            let b = s.clock.beat + Double(f) * bps
            var n = frames - f
            if let q = s.queued {
                let qf = Int(((s.queuedBeat - b) / bps - 1e-4).rounded(.up))
                if qf <= 0 {
                    // Switch now.
                    if let p = s.playing, let old = slots[p] { old.deactivate() }
                    if q >= 0, slots[q] != nil {
                        s.playing = q
                        s.launchBeat = s.queuedBeat
                    } else {
                        s.playing = nil
                    }
                    s.queued = nil
                    continue
                }
                n = min(n, qf)
            }
            if let p = s.playing, let node = slots[p] {
                renderSlot(node, local: b - s.launchBeat, frames: n, f: f, ctx: ctx, songBeat: songBeat + Double(f) * bps, buf: buf)
            }
            f += n
        }
        // Other slots that were just stopped ring out.
        for (i, c) in slots where i != s.playing && c.state.active {
            c.render(b0: 0, frames: frames, ctx: ctx, songBeat: songBeat, into: buf, tail: true)
        }
    }

    private func renderSlot(_ node: ClipNode, local: Double, frames: Int, f: Int, ctx: RenderContext, songBeat: Double, buf: StereoBuffer) {
        if f == 0 {
            node.render(b0: local, frames: frames, ctx: ctx, songBeat: songBeat, into: buf, tail: false)
        } else {
            // Render into a temporary view starting at frame f.
            let tmp = TrackNode.scratch
            tmp.clear(frames)
            node.render(b0: local, frames: frames, ctx: ctx, songBeat: songBeat, into: tmp, tail: false)
            for i in 0..<frames { buf.l[f + i] += tmp.l[i]; buf.r[f + i] += tmp.r[i] }
        }
    }

    // Only used on the audio thread, never re-entered (session tracks are top-level only).
    static let scratch = StereoBuffer()
}

// MARK: - Composition

final class CompState {
    let buffer = StereoBuffer()
}

final class CompNode: SourceNode {
    let tracks: [TrackNode]
    let chain: EffectChain
    let gain: Float
    let state: CompState
    let meter: LevelMeter?
    var lastBeat = 0.0

    init(tracks: [TrackNode], chain: EffectChain, gain: Float, state: CompState, meter: LevelMeter?) {
        self.tracks = tracks
        self.chain = chain
        self.gain = gain
        self.state = state
        self.meter = meter
    }

    var hasTail: Bool { true }
    var isAudio: Bool { false }

    func renderComp(beat: Double, frames: Int, ctx: RenderContext, songBeat: Double, tail: Bool) -> StereoBuffer {
        let buf = state.buffer
        buf.clear(frames)
        for t in tracks {
            t.render(b0: beat, frames: frames, ctx: ctx, songBeat: songBeat, into: buf, tail: tail)
        }
        // Composition effects run after everything inside it, like an adjustment on a precomp.
        chain.process(buf, frames: frames, ctx: ctx, beat: songBeat, time: beat)
        meter?.update(buf, frames)
        return buf
    }

    func render(beat: Double, frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                ctx: RenderContext, songBeat: Double) {
        lastBeat = beat + Double(frames) * ctx.beatsPerSample
        let buf = renderComp(beat: beat, frames: frames, ctx: ctx, songBeat: songBeat, tail: false)
        buf.mix(into: l, r, frames, gainL: gain, gainR: gain)
    }

    func renderTail(frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                    ctx: RenderContext, songBeat: Double) {
        let buf = renderComp(beat: lastBeat, frames: frames, ctx: ctx, songBeat: songBeat, tail: true)
        buf.mix(into: l, r, frames, gainL: gain, gainR: gain)
    }

    func stop() {
        for t in tracks {
            for c in t.clips { c.deactivate() }
            t.chain.reset()
        }
        chain.reset()
    }
}

// MARK: - Audio source

final class AudioState {
    var expected = -1.0
    var ramp: Float = 1
}

final class AudioSourceNode: SourceNode {
    let data: SampleData?
    let state: AudioState

    init(data: SampleData?, state: AudioState) {
        self.data = data
        self.state = state
    }

    var hasTail: Bool { false }
    var isAudio: Bool { true }

    func render(beat: Double, frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                ctx: RenderContext, songBeat: Double) {
        guard let d = data else { return }
        let bps = ctx.beatsPerSample
        if abs(beat - state.expected) > bps * 1.5 { state.ramp = 0 }
        state.expected = beat + Double(frames) * bps
        let step = d.sampleRate / ctx.sampleRate
        var pos = beat * 60 / ctx.bpm * d.sampleRate
        let last = d.frames - 1
        let rampInc: Float = 1 / 96
        for i in 0..<frames {
            let idx = Int(pos)
            if idx >= 0 && idx < last {
                let fr = Float(pos - Double(idx))
                var vl = d.l[idx] + (d.l[idx + 1] - d.l[idx]) * fr
                var vr = d.r[idx] + (d.r[idx + 1] - d.r[idx]) * fr
                if state.ramp < 1 {
                    state.ramp = min(1, state.ramp + rampInc)
                    vl *= state.ramp; vr *= state.ramp
                }
                l[i] += vl
                r[i] += vr
            }
            pos += step
        }
    }

    func renderTail(frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, ctx: RenderContext, songBeat: Double) {
        state.expected = -1
    }

    func stop() { state.expected = -1 }
}

// MARK: - Note (piano roll) source

struct NoteEvent {
    let beat: Double
    let on: Bool
    let pitch: Int
    let velocity: Float
}

final class NoteState {
    let synth: Synth
    var expected = -1.0
    init(sampleRate: Double) { synth = Synth(sampleRate: sampleRate) }
}

final class NoteSourceNode: SourceNode {
    let events: [NoteEvent]
    let notes: [Note]
    let length: Double
    let params: [Double]
    let state: NoteState

    init(pattern: NotePattern, state: NoteState) {
        let len = pattern.length
        var ev: [NoteEvent] = []
        for n in pattern.notes where n.start < len {
            ev.append(NoteEvent(beat: n.start, on: true, pitch: n.pitch, velocity: Float(n.velocity)))
            ev.append(NoteEvent(beat: min(n.end, len), on: false, pitch: n.pitch, velocity: 0))
        }
        // Note-offs sort before note-ons at the same time so repeated notes retrigger.
        ev.sort { $0.beat != $1.beat ? $0.beat < $1.beat : (!$0.on && $1.on) }
        events = ev
        notes = pattern.notes
        length = len
        params = SynthParams.defs.resolve(pattern.instrument.params)
        self.state = state
    }

    var hasTail: Bool { true }
    var isAudio: Bool { false }

    func firstEvent(atOrAfter beat: Double) -> Int {
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].beat < beat { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    func render(beat: Double, frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                ctx: RenderContext, songBeat: Double) {
        let synth = state.synth
        let bps = ctx.beatsPerSample
        // Events are collected from a window shifted one sample early. Loop wraps and clip
        // starts land up to a sample *after* the exact beat (frame rounding), and without
        // this a note sitting on beat 1 would count as already past and be skipped.
        let w0 = beat - bps, w1 = beat + Double(frames) * bps - bps
        if abs(beat - state.expected) > bps * 1.5 {
            // Jumped (seek, loop wrap): release what was playing and pick up notes already in progress.
            synth.allNotesOff()
            for n in notes where n.start < w0 && min(n.end, length) > beat + bps {
                synth.noteOn(n.pitch, velocity: Float(n.velocity), params: params)
            }
        }
        state.expected = beat + Double(frames) * bps
        var idx = firstEvent(atOrAfter: w0)
        var f = 0
        while idx < events.count {
            let e = events[idx]
            if e.beat >= w1 { break }
            let ef = min(frames - 1, max(0, Int(((e.beat - beat) / bps).rounded(.down))))
            if ef > f {
                synth.render(l + f, r + f, frames: ef - f, params: params)
                f = ef
            }
            if e.on { synth.noteOn(e.pitch, velocity: e.velocity, params: params) } else { synth.noteOff(e.pitch, params: params) }
            idx += 1
        }
        if f < frames { synth.render(l + f, r + f, frames: frames - f, params: params) }
    }

    func renderTail(frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, ctx: RenderContext, songBeat: Double) {
        if state.expected >= 0 {
            state.synth.allNotesOff()
            state.expected = -1
        }
        state.synth.render(l, r, frames: frames, params: params)
    }

    func stop() {
        state.synth.reset()
        state.expected = -1
    }
}

// MARK: - Drum (beat maker) source

struct DrumHit {
    let beat: Double
    let row: Int
    let velocity: Float
}

struct DrumRowInfo {
    let sample: SampleData?
    let gainL: Float, gainR: Float
    let rate: Double
    let choke: Int
}

struct DrumVoice {
    var sample: SampleData?
    var pos = 0.0
    var rate = 1.0
    var gainL: Float = 0, gainR: Float = 0
    var choke = 0
    var fade: Float = 1
    var fading = false
}

final class DrumPlayer {
    var voices = [DrumVoice](repeating: DrumVoice(), count: 32)
    var next = 0
    var expected = -1.0

    func trigger(_ row: DrumRowInfo, velocity: Float, outputRate: Double) {
        guard let s = row.sample else { return }
        if row.choke > 0 {
            for i in voices.indices where voices[i].sample != nil && voices[i].choke == row.choke { voices[i].fading = true }
        }
        let vel = velocity * velocity
        voices[next] = DrumVoice(sample: s, pos: 0, rate: row.rate * s.sampleRate / outputRate,
                                 gainL: row.gainL * vel, gainR: row.gainR * vel, choke: row.choke)
        next = (next + 1) % voices.count
    }

    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, frames: Int) {
        for vi in voices.indices {
            guard let s = voices[vi].sample else { continue }
            var v = voices[vi]
            let last = s.frames - 1
            for i in 0..<frames {
                let idx = Int(v.pos)
                if idx >= last { v.sample = nil; break }
                let fr = Float(v.pos - Double(idx))
                var x = s.l[idx] + (s.l[idx + 1] - s.l[idx]) * fr
                if v.fading {
                    v.fade -= 1 / 200
                    if v.fade <= 0 { v.sample = nil; break }
                    x *= v.fade
                }
                l[i] += x * v.gainL
                r[i] += x * v.gainR
                v.pos += v.rate
            }
            voices[vi] = v
        }
    }

    func reset() {
        for i in voices.indices { voices[i].sample = nil }
        expected = -1
    }

    var isSilent: Bool { !voices.contains { $0.sample != nil } }
}

final class DrumSourceNode: SourceNode {
    let hits: [DrumHit]
    let rows: [DrumRowInfo]
    let player: DrumPlayer

    init(pattern: DrumPattern, sampleRate: Double, player: DrumPlayer) {
        let stepLen = 1.0 / Double(pattern.stepsPerBeat)
        let anySolo = false
        var info: [DrumRowInfo] = []
        var hits: [DrumHit] = []
        for (ri, row) in pattern.rows.enumerated() {
            let (pl, pr) = panGains(row.pan)
            let g = Float(dbToGain(row.volume))
            info.append(DrumRowInfo(sample: DrumKits.sample(kit: pattern.kit, voice: row.sound, sampleRate: sampleRate),
                                    gainL: pl * g, gainR: pr * g, rate: pow(2, row.pitch / 12),
                                    choke: DrumKits.choke(row.sound)))
            guard !row.mute, !anySolo else { continue }
            for (si, v) in row.steps.prefix(pattern.steps).enumerated() where v > 0 {
                let swing = si % 2 == 1 ? pattern.swing * stepLen * 0.5 : 0
                hits.append(DrumHit(beat: Double(si) * stepLen + swing, row: ri, velocity: Float(v)))
            }
        }
        hits.sort { $0.beat < $1.beat }
        self.hits = hits
        self.rows = info
        self.player = player
    }

    var hasTail: Bool { true }
    var isAudio: Bool { false }

    func render(beat: Double, frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                ctx: RenderContext, songBeat: Double) {
        let bps = ctx.beatsPerSample
        player.expected = beat + Double(frames) * bps
        // Same one-sample-early window as notes, so hits on beat 1 survive loop wraps.
        let w0 = beat - bps, w1 = beat + Double(frames) * bps - bps
        var lo = 0, hi = hits.count
        while lo < hi { let m = (lo + hi) / 2; if hits[m].beat < w0 { lo = m + 1 } else { hi = m } }
        var idx = lo, f = 0
        while idx < hits.count {
            let h = hits[idx]
            if h.beat >= w1 { break }
            let hf = min(frames - 1, max(0, Int(((h.beat - beat) / bps).rounded(.down))))
            if hf > f { player.render(l + f, r + f, frames: hf - f); f = hf }
            player.trigger(rows[h.row], velocity: h.velocity, outputRate: ctx.sampleRate)
            idx += 1
        }
        if f < frames { player.render(l + f, r + f, frames: frames - f) }
    }

    func renderTail(frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, ctx: RenderContext, songBeat: Double) {
        player.render(l, r, frames: frames)
    }

    func stop() { player.reset() }
}

// MARK: - Drum kit played from notes (piano roll drums)

final class KitNoteSourceNode: SourceNode {
    let hits: [DrumHit]
    let rows: [DrumRowInfo]
    let player: DrumPlayer

    init(pattern: NotePattern, kit: String, sampleRate: Double, player: DrumPlayer) {
        rows = DrumKits.voices.map { v in
            DrumRowInfo(sample: DrumKits.sample(kit: kit, voice: v.id, sampleRate: sampleRate), gainL: 1, gainR: 1, rate: 1, choke: v.choke)
        }
        hits = pattern.notes
            .filter { $0.start < pattern.length && DrumKits.voice(atPitch: $0.pitch) != nil }
            .map { DrumHit(beat: $0.start, row: $0.pitch - DrumKits.basePitch, velocity: Float($0.velocity)) }
            .sorted { $0.beat < $1.beat }
        self.player = player
    }

    var hasTail: Bool { true }
    var isAudio: Bool { false }

    func render(beat: Double, frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                ctx: RenderContext, songBeat: Double) {
        let bps = ctx.beatsPerSample
        let w0 = beat - bps, w1 = beat + Double(frames) * bps - bps
        var lo = 0, hi = hits.count
        while lo < hi { let m = (lo + hi) / 2; if hits[m].beat < w0 { lo = m + 1 } else { hi = m } }
        var idx = lo, f = 0
        while idx < hits.count {
            let h = hits[idx]
            if h.beat >= w1 { break }
            let hf = min(frames - 1, max(0, Int(((h.beat - beat) / bps).rounded(.down))))
            if hf > f { player.render(l + f, r + f, frames: hf - f); f = hf }
            player.trigger(rows[h.row], velocity: h.velocity, outputRate: ctx.sampleRate)
            idx += 1
        }
        if f < frames { player.render(l + f, r + f, frames: frames - f) }
    }

    func renderTail(frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, ctx: RenderContext, songBeat: Double) {
        player.render(l, r, frames: frames)
    }

    func stop() { player.reset() }
}

// MARK: - Silent placeholder

final class SilentSource: SourceNode {
    var hasTail: Bool { false }
    var isAudio: Bool { false }
    func render(beat: Double, frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, ctx: RenderContext, songBeat: Double) {}
    func renderTail(frames: Int, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, ctx: RenderContext, songBeat: Double) {}
    func stop() {}
}
