import AVFoundation
import Foundation
import os

public struct TransportSnapshot {
    public var playing: Bool
    public var position: Double
    /// Session clock (see `SessionClock`); session launch beats are on this clock.
    public var sessionBeat: Double
    public var sessions: [UUID: SessionInfo]
}

public struct SessionInfo: Equatable {
    public var playing: Int?
    public var queued: Int?
    public var launchBeat: Double
}

/// Real-time engine. A single AVAudioSourceNode pulls the whole render graph.
///
/// Threading: everything the audio thread touches is guarded by one unfair lock.
/// The audio thread holds it for the duration of a render; the main thread takes
/// it briefly to swap graphs or change transport state.
public final class AudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    public private(set) var sampleRate: Double = 48000
    public private(set) var isRunning = false

    private let lockPtr: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    // Guarded by lock.
    private var graph: RenderGraph?
    private var playing = false
    private var position = 0.0
    private var playStart = 0.0
    private var bpm = 120.0
    private var beatsPerBar = 4
    private var loopOn = false
    private var loopStart = 0.0
    private var loopEnd = 16.0
    private var metronomeOn = false
    private var masterGain: Float = 1
    private var idleFrames = Int.max
    private var sessionList: [SessionTrackState] = []
    private let sessionClock = SessionClock()
    private var clickFrames = 0
    private var clickFreq = 1000.0
    private var clickPhase = 0.0

    private let master = StereoBuffer()
    private var limiter: LimiterFX
    private let limiterParams = LimiterFX.params.resolve(["ceiling": -0.3, "release": 60])
    private var previewSynth: Synth
    private var previewParams = SynthParams.defs.resolve([:])
    /// Effects the preview synth plays through (a browser preset's own effects), and how long its tail may still ring.
    private var previewChain: EffectChain?
    private var previewEffects: [Effect] = []
    private let previewBuf = StereoBuffer()
    private var previewTail = 0
    /// A short phrase the browser plays when you click an instrument, timed to the sample.
    private var phrase: [PhraseEvent] = []
    private var phraseIndex = 0
    private var phraseClock = 0
    private var phraseKit: String?
    private var phraseBPM = 120.0
    private let previewDrums = DrumPlayer()
    /// Notes played by hand on a sampler pattern (through the layer's effects, like the synth).
    private var previewSampler: Sampler
    private var previewSamplerParams = SamplerParams.defs.resolve([:])
    /// A file clicked in the Samples browser, played once as is.
    private var previewFilePlayer: Sampler
    private let previewFileParams = SamplerParams.defs.resolve(["playmode": 1, "root": 60, "a": 0.0005])
    /// Main thread only: browser previews aren't in the sample cache, so keep each one alive until
    /// it has surely finished, and the audio thread never frees one.
    private var previewKeepAlive: [(sample: MipSample, until: Date)] = []

    // Main-thread only.
    private var meters: [UUID: LevelMeter] = [:]
    private var sessions: [UUID: SessionTrackState] = [:]
    private var project: Project?
    private var rootID: AssetID?
    public let masterMeter = LevelMeter()
    public let compMeter = LevelMeter()

    public init() {
        limiter = LimiterFX(sampleRate: 48000)
        previewSynth = Synth(sampleRate: 48000)
        previewSampler = Sampler(sampleRate: 48000)
        previewFilePlayer = Sampler(sampleRate: 48000)
        _ = TrackNode.scratch
    }

    deinit {
        engine.stop()
        lockPtr.deallocate()
    }

    @inline(__always) private func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(lockPtr)
        defer { os_unfair_lock_unlock(lockPtr) }
        return body()
    }

    // MARK: Lifecycle

    public func start() {
        let hw = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = hw.sampleRate > 0 ? hw.sampleRate : 48000
        let sampler = Sampler(sampleRate: sampleRate), filePlayer = Sampler(sampleRate: sampleRate)
        let masterLimiter = LimiterFX(sampleRate: sampleRate)
        locked {
            previewSynth = Synth(sampleRate: sampleRate)
            previewSampler = sampler
            previewFilePlayer = filePlayer
            limiter = masterLimiter
        }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let node = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frameCount, abl -> OSStatus in
            self.render(Int(frameCount), abl)
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            NSLog("Shaw: audio engine failed to start: \(error)")
        }
        DrumKits.warm(sampleRate: sampleRate)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartAfterConfigChange()
        }
    }

    private func restartAfterConfigChange() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    // MARK: Graph

    /// Rebuild the render graph for `root`. Call after every project change.
    public func update(project: Project, root: AssetID) {
        self.project = project
        self.rootID = root
        guard let comp = project.composition(root) else { return }
        for t in comp.tracks {
            if meters[t.id] == nil { meters[t.id] = LevelMeter() }
            if sessions[t.id] == nil { sessions[t.id] = SessionTrackState(clock: sessionClock) }
        }
        let old = locked { graph?.states ?? [:] }
        var builder = GraphBuilder(project: project, sampleRate: sampleRate, previous: old, samples: SampleLibrary.shared,
                                   meters: { [meters] in meters[$0] }, session: { [sessions] in sessions[$0] },
                                   compMeter: compMeter)
        let g = builder.build(root: root)
        let list = comp.tracks.compactMap { sessions[$0.id] }
        var retired: RenderGraph? = locked {
            let prev = graph
            graph = g
            bpm = project.bpm
            beatsPerBar = project.beatsPerBar
            masterGain = Float(dbToGain(project.masterVolume))
            sessionList = list
            return prev
        }
        // Release the previous graph here on the main thread, not on the audio thread.
        retired = nil
        _ = retired
    }

    public func meter(for track: UUID) -> LevelMeter? { meters[track] }

    // MARK: Transport

    public func play(from beat: Double? = nil) {
        locked {
            if let b = beat { position = b }
            if !loopOn, let len = graph?.rootLength, position >= len - 1e-6 { position = 0 }
            if loopOn, position >= loopEnd || position < loopStart - 1e-9 { position = loopStart }
            playStart = position
            playing = true
            idleFrames = 0
            sessionClock.beat = position
        }
    }

    /// Stops and returns the playhead to where playback started.
    public func stop(returnToStart: Bool = true) {
        locked {
            if playing && returnToStart { position = playStart }
            playing = false
            idleFrames = 0
            for s in sessionList { s.playing = nil; s.queued = nil }
            for (_, s) in sessions { s.playing = nil; s.queued = nil }
        }
    }

    public func seek(_ beat: Double) {
        locked {
            position = max(0, beat)
            playStart = position
        }
    }

    public func setLoop(enabled: Bool, start: Double, end: Double) {
        locked {
            loopOn = enabled
            loopStart = start
            loopEnd = max(end, start + 0.25)
        }
    }

    public func setMetronome(_ on: Bool) { locked { metronomeOn = on } }

    public func snapshot() -> TransportSnapshot {
        locked {
            var info: [UUID: SessionInfo] = [:]
            for (id, s) in sessions where s.playing != nil || s.queued != nil {
                info[id] = SessionInfo(playing: s.playing, queued: s.queued, launchBeat: s.launchBeat)
            }
            return TransportSnapshot(playing: playing, position: position, sessionBeat: sessionClock.beat, sessions: info)
        }
    }

    // MARK: Session

    private func nextBar(after pos: Double) -> Double {
        let bar = Double(beatsPerBar)
        return (pos / bar - 1e-6).rounded(.up) * bar
    }

    public func launch(track: UUID, scene: Int) {
        guard let s = sessions[track] else { return }
        locked {
            let wasPlaying = startForSessionLocked()
            launchLocked(s, scene, immediately: !wasPlaying)
        }
    }

    /// Starts the transport if needed. Returns whether it was already playing.
    private func startForSessionLocked() -> Bool {
        if playing { return true }
        playing = true
        playStart = position
        idleFrames = 0
        sessionClock.beat = position
        return false
    }

    private func launchLocked(_ s: SessionTrackState, _ scene: Int, immediately: Bool) {
        if immediately {
            if let p = s.playing, p != scene { s.queued = scene; s.queuedBeat = sessionClock.beat; return }
            s.playing = scene
            s.launchBeat = sessionClock.beat
            s.queued = nil
        } else {
            s.queued = scene
            s.queuedBeat = nextBar(after: sessionClock.beat)
        }
    }

    public func launchScene(_ scene: Int, tracks: [UUID: Bool]) {
        // `tracks` maps each track in the composition to whether it has a clip in this scene.
        locked {
            // Decide once, so every track in the scene starts on the same beat.
            let wasPlaying = startForSessionLocked()
            for (id, has) in tracks {
                guard let s = sessions[id] else { continue }
                if has { launchLocked(s, scene, immediately: !wasPlaying) } else if s.playing != nil {
                    s.queued = -1
                    s.queuedBeat = nextBar(after: sessionClock.beat)
                }
            }
        }
    }

    public func stopTrack(_ track: UUID) {
        guard let s = sessions[track] else { return }
        locked {
            if playing {
                s.queued = -1
                s.queuedBeat = nextBar(after: sessionClock.beat)
            } else {
                s.playing = nil
                s.queued = nil
            }
        }
    }

    public func stopAllSession() {
        locked {
            for (_, s) in sessions where s.playing != nil {
                s.queued = -1
                s.queuedBeat = playing ? nextBar(after: sessionClock.beat) : sessionClock.beat
            }
        }
    }

    // MARK: Preview

    public func previewNoteOn(_ pitch: Int, velocity: Double = 0.8, instrument: Instrument) {
        if let kit = instrument.kit {
            if let v = DrumKits.voice(atPitch: pitch) {
                previewDrum(kit: kit, sound: v.id, velocity: velocity, file: instrument.kitSamples?[v.id])
            }
            return
        }
        if let file = instrument.sample {
            // Still loading the first time: silent until it's ready (the pattern asked for it already).
            guard let sample = SampleLibrary.shared.mipmapped(for: file) else { return }
            let p = SamplerParams.defs.resolve(instrument.params)
            locked {
                previewSamplerParams = p
                phrase = []
                phraseBPM = bpm
                previewSampler.noteOn(pitch, velocity: Float(velocity), params: p, sample: sample)
                idleFrames = 0
            }
            return
        }
        let p = SynthParams.defs.resolve(instrument.params)
        locked {
            previewParams = p
            // Notes played by hand follow the song's tempo (a phrase uses its own).
            phrase = []
            phraseBPM = bpm
            previewSynth.noteOn(pitch, velocity: Float(velocity), params: p)
            idleFrames = 0
        }
    }

    /// Play a short phrase on `instrument` (main thread). Replaces any phrase still playing.
    public func playPhrase(_ notes: [PhraseNote], instrument: Instrument, effects: [Effect] = [], bpm tempo: Double) {
        guard !instrument.isSampler else { return } // phrases are for synth presets and kits
        setPreviewEffects(instrument.isDrumKit ? [] : effects)
        let spb = sampleRate * 60 / tempo
        var ev: [PhraseEvent] = []
        for n in notes {
            let on = Int(n.beat * spb)
            ev.append(PhraseEvent(frame: on, on: true, pitch: n.pitch, velocity: Float(n.velocity)))
            if instrument.kit == nil {
                ev.append(PhraseEvent(frame: on + max(1, Int(n.length * spb)), on: false, pitch: n.pitch, velocity: 0))
            }
        }
        // Note-offs first at the same frame, so repeated notes retrigger.
        ev.sort { $0.frame != $1.frame ? $0.frame < $1.frame : (!$0.on && $1.on) }
        let p = SynthParams.defs.resolve(instrument.params)
        let kit = instrument.kit
        if let kit { _ = DrumKits.sample(kit: kit, voice: "kick", sampleRate: sampleRate) } // generate off the audio thread
        locked {
            previewSynth.allNotesOff()
            previewParams = p
            phrase = ev
            phraseIndex = 0
            phraseClock = 0
            phraseKit = kit
            phraseBPM = tempo
            idleFrames = 0
        }
    }

    /// Route preview notes through these effects (main thread). Pass [] for a dry preview.
    public func setPreviewEffects(_ effects: [Effect]) {
        let same = effects.count == previewEffects.count && zip(effects, previewEffects).allSatisfy { $0.kind == $1.kind && $0.params == $1.params }
        if same { return }
        previewEffects = effects
        let sr = sampleRate
        let slots = effects.compactMap { e -> EffectSlot? in
            guard let d = EffectRegistry.descriptor(e.kind) else { return nil }
            return EffectSlot(processor: d.make(sr), params: d.params.resolve(e.params))
        }
        let chain = slots.isEmpty ? nil : EffectChain(slots)
        locked { previewChain = chain }
    }

    public func previewNoteOff(_ pitch: Int) {
        locked {
            previewSynth.noteOff(pitch, params: previewParams)
            previewSampler.noteOff(pitch)
        }
    }

    public func previewAllOff() {
        locked {
            previewSynth.allNotesOff()
            previewSampler.allNotesOff()
        }
    }

    /// Play an audio file once, as it is (clicking a file in the Samples browser). Main thread.
    /// Replaces the file preview that's still playing.
    public func previewSample(_ sample: MipSample) {
        let now = Date()
        previewKeepAlive.removeAll { $0.until < now }
        previewKeepAlive.append((sample, now.addingTimeInterval(sample.duration + 2)))
        locked {
            previewFilePlayer.cutAll()
            previewFilePlayer.noteOn(60, velocity: 1, params: previewFileParams, sample: sample)
            idleFrames = 0
        }
    }

    public func stopSamplePreview() {
        locked { previewFilePlayer.cutAll() }
    }

    /// - Parameter file: your own sample for this drum sound (`Instrument.kitSamples`); silent while it loads.
    public func previewDrum(kit: String, sound: String, velocity: Double = 0.9, pitch: Double = 0, volume: Double = 0,
                            file: String? = nil) {
        let s = file.map { SampleLibrary.shared.data(for: $0) } ?? DrumKits.sample(kit: kit, voice: sound, sampleRate: sampleRate)
        let g = Float(dbToGain(volume))
        let row = DrumRowInfo(sample: s, gainL: g, gainR: g, rate: pow(2, pitch / 12), choke: DrumKits.choke(sound))
        locked {
            previewDrums.trigger(row, velocity: Float(velocity), outputRate: sampleRate)
            idleFrames = 0
        }
    }

    // MARK: Render (audio thread)

    /// Preview synth and drums, splitting the block at phrase events so they land on the exact sample.
    private func renderPreview(_ n: Int) {
        let chain = previewChain
        if !previewSynth.isSilent || !previewSampler.isSilent || phraseIndex < phrase.count { previewTail = Int(sampleRate * 4) }
        let wet = chain != nil && previewTail > 0
        if wet { previewBuf.clear(n) }
        let outL = wet ? previewBuf.l : master.l, outR = wet ? previewBuf.r : master.r
        // Stopped, previews keep their own clock at the phrase tempo, so a sidechain pump or a
        // synced wobble moves instead of freezing at the paused song position.
        let pbpm = playing ? bpm : phraseBPM
        let bpf = pbpm / 60 / sampleRate
        let beat0 = playing ? position : Double(phraseClock) * bpf
        var f = 0
        while phraseIndex < phrase.count && phrase[phraseIndex].frame < phraseClock + n {
            let e = phrase[phraseIndex]
            let ef = min(n, max(f, e.frame - phraseClock))
            if ef > f {
                previewSynth.render(outL + f, outR + f, frames: ef - f, params: previewParams, bpm: pbpm, beat: beat0 + Double(f) * bpf)
                previewDrums.render(master.l + f, master.r + f, frames: ef - f)
                f = ef
            }
            if let kit = phraseKit {
                if e.on, let v = DrumKits.voice(atPitch: e.pitch),
                   let smp = DrumKits.cachedSample(kit: kit, voice: v.id, sampleRate: sampleRate) {
                    previewDrums.trigger(DrumRowInfo(sample: smp, gainL: 1, gainR: 1, rate: 1, choke: v.choke),
                                         velocity: e.velocity, outputRate: sampleRate)
                }
            } else if e.on {
                previewSynth.noteOn(e.pitch, velocity: e.velocity, params: previewParams)
            } else {
                previewSynth.noteOff(e.pitch, params: previewParams)
            }
            phraseIndex += 1
        }
        if f < n {
            previewSynth.render(outL + f, outR + f, frames: n - f, params: previewParams, bpm: pbpm, beat: beat0 + Double(f) * bpf)
            previewDrums.render(master.l + f, master.r + f, frames: n - f)
        }
        // Sampler notes played by hand go through the layer's effects; browser file previews stay dry.
        previewSampler.render(outL, outR, frames: n, params: previewSamplerParams)
        previewFilePlayer.render(master.l, master.r, frames: n, params: previewFileParams)
        phraseClock += n
        if wet, let chain {
            chain.process(previewBuf, frames: n, ctx: RenderContext(sampleRate: sampleRate, bpm: pbpm), beat: beat0, time: 0)
            previewBuf.mix(into: master, n)
            previewTail -= n
        }
    }

    private func render(_ total: Int, _ abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard buffers.count >= 2,
              let outL = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let outR = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        os_unfair_lock_lock(lockPtr)
        var done = 0
        while done < total {
            let n = min(512, total - done)
            renderBlock(n)
            (outL + done).update(from: master.l, count: n)
            (outR + done).update(from: master.r, count: n)
            done += n
        }
        os_unfair_lock_unlock(lockPtr)
    }

    var lockPtrForTesting: UnsafeMutablePointer<os_unfair_lock> { lockPtr }
    var masterForTesting: StereoBuffer { master }
    func renderBlockForTesting(_ n: Int) { renderBlock(n) }

    private func renderBlock(_ n: Int) {
        master.clear(n)
        let ctx = RenderContext(sampleRate: sampleRate, bpm: bpm)
        let bps = ctx.beatsPerSample
        if let g = graph, let root = g.root {
            if playing {
                var f = 0
                while f < n {
                    var seg = n - f
                    if loopOn {
                        if position >= loopEnd { position = loopStart }
                        seg = min(seg, framesUntil(loopEnd - position, bps))
                    }
                    root.render(beat: position, frames: seg, l: master.l + f, r: master.r + f, ctx: ctx, songBeat: position)
                    if metronomeOn { metronome(from: position, frames: seg, offset: f, bps: bps) }
                    position += Double(seg) * bps
                    sessionClock.beat += Double(seg) * bps
                    // Land exactly on the loop start (the sub-sample overshoot is dropped).
                    if loopOn && position >= loopEnd - 1e-9 { position = loopStart }
                    f += seg
                }
                if !loopOn && position >= g.rootLength && !sessionList.contains(where: { $0.isActive }) {
                    playing = false
                    position = g.rootLength
                    idleFrames = 0
                }
            } else if idleFrames < Int(sampleRate * 15) {
                // Let reverbs, delays and releases ring out after stopping.
                root.renderTail(frames: n, l: master.l, r: master.r, ctx: ctx, songBeat: position)
                idleFrames += n
            }
        }
        renderPreview(n)
        if clickFrames > 0 && !metronomeOn { clickFrames = 0 }
        master.scale(n, masterGain)
        limiter.process(master, frames: n, params: limiterParams, ctx: ctx, beat: position)
        masterMeter.update(master, n)
    }

    private func metronome(from beat: Double, frames: Int, offset: Int, bps: Double) {
        var f = 0
        let end = beat + Double(frames) * bps
        var next = beat.rounded(.up)
        if next - beat < 1e-9 { next = beat }
        while f < frames {
            if next < end {
                let nf = max(0, Int(((next - beat) / bps).rounded(.down)))
                if nf > f { renderClick(offset + f, nf - f); f = nf }
                clickFrames = Int(sampleRate * 0.03)
                clickFreq = Int(next.rounded()) % beatsPerBar == 0 ? 1600 : 1000
                clickPhase = 0
                next += 1
            } else {
                renderClick(offset + f, frames - f)
                f = frames
            }
        }
    }

    private func renderClick(_ at: Int, _ n: Int) {
        guard clickFrames > 0 else { return }
        let total = sampleRate * 0.03
        for i in 0..<n where clickFrames > 0 {
            let env = Float(Double(clickFrames) / total)
            let v = Float(sin(2 * .pi * clickPhase)) * env * env * 0.35
            clickPhase += clickFreq / sampleRate
            master.l[at + i] += v
            master.r[at + i] += v
            clickFrames -= 1
        }
    }
}

// MARK: - Offline export

public enum OfflineRenderer {
    /// Renders a composition to a 24-bit WAV file. Runs synchronously; call from a background queue.
    public static func export(project: Project, composition id: AssetID, to url: URL, sampleRate: Double = 48000,
                              tailSeconds: Double = 2, progress: ((Double) -> Void)? = nil) throws {
        // Make sure every audio file (clips, samplers, and drum sounds) is decoded before rendering.
        SampleLibrary.shared.preload(project)
        var builder = GraphBuilder(project: project, sampleRate: sampleRate, previous: [:], samples: SampleLibrary.shared)
        let graph = builder.build(root: id)
        guard let root = graph.root else { return }
        let ctx = RenderContext(sampleRate: sampleRate, bpm: project.bpm)
        let lengthFrames = Int(graph.rootLength * ctx.samplesPerBeat)
        let tailFrames = Int(tailSeconds * sampleRate)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let block = 1024
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(block)) else { return }
        let buf = StereoBuffer()
        let limiter = LimiterFX(sampleRate: sampleRate)
        let lp = LimiterFX.params.resolve(["ceiling": -0.3])
        let gain = Float(dbToGain(project.masterVolume))
        var done = 0
        let bps = ctx.beatsPerSample
        // The limiter's lookahead delays its output, so render that much longer and drop the
        // start: the file begins exactly on beat 1.
        var skip = limiter.latency
        let total = lengthFrames + tailFrames + skip
        while done < total {
            let n = min(block, total - done)
            buf.clear(n)
            let beat = Double(done) * bps
            if done < lengthFrames {
                let m = min(n, lengthFrames - done)
                root.render(beat: beat, frames: m, l: buf.l, r: buf.r, ctx: ctx, songBeat: beat)
                if m < n { root.renderTail(frames: n - m, l: buf.l + m, r: buf.r + m, ctx: ctx, songBeat: beat) }
            } else {
                root.renderTail(frames: n, l: buf.l, r: buf.r, ctx: ctx, songBeat: beat)
            }
            buf.scale(n, gain)
            limiter.process(buf, frames: n, params: lp, ctx: ctx, beat: beat)
            let s = min(skip, n)
            skip -= s
            if s < n {
                pcm.frameLength = AVAudioFrameCount(n - s)
                pcm.floatChannelData![0].update(from: buf.l + s, count: n - s)
                pcm.floatChannelData![1].update(from: buf.r + s, count: n - s)
                try file.write(from: pcm)
            }
            done += n
            progress?(Double(done) / Double(total))
        }
    }
}

extension SampleLibrary {
    /// Decode synchronously (used by export).
    public func loadSync(_ path: String) -> SampleData? {
        if let d = data(for: path) { return d }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        for _ in 0..<500 {
            Thread.sleep(forTimeInterval: 0.02)
            if let d = data(for: path) { return d }
        }
        return nil
    }

    /// Prepare a sampler file synchronously (used by export).
    public func mipmappedSync(_ path: String) -> MipSample? {
        if let m = mipmapped(for: path) { return m }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        for _ in 0..<500 {
            Thread.sleep(forTimeInterval: 0.02)
            if let m = mipmapped(for: path) { return m }
        }
        return nil
    }

    /// Load every file a project plays before an offline render: audio clips, samplers, and custom drum sounds.
    public func preload(_ project: Project) {
        for a in project.assets {
            switch a.content {
            case .audio(let ref): _ = loadSync(ref.path)
            case .notes(let p):
                if p.instrument.isSampler, let file = p.instrument.sample { _ = mipmappedSync(file) }
                if p.instrument.isDrumKit { for file in p.instrument.samplePaths { _ = loadSync(file) } }
            default: break
            }
        }
    }
}

extension OfflineRenderer {
    /// Render a composition into memory (left channel + right channel). Used by tests and bouncing.
    public static func renderToMemory(project: Project, composition id: AssetID, beats: Double,
                                      sampleRate: Double = 48000) -> ([Float], [Float]) {
        SampleLibrary.shared.preload(project)
        var builder = GraphBuilder(project: project, sampleRate: sampleRate, previous: [:], samples: SampleLibrary.shared)
        let graph = builder.build(root: id)
        let ctx = RenderContext(sampleRate: sampleRate, bpm: project.bpm)
        let total = Int(beats * ctx.samplesPerBeat)
        var outL = [Float](repeating: 0, count: total), outR = outL
        guard let root = graph.root else { return (outL, outR) }
        let buf = StereoBuffer()
        var done = 0
        while done < total {
            let n = min(512, total - done)
            buf.clear(n)
            let beat = Double(done) * ctx.beatsPerSample
            root.render(beat: beat, frames: n, l: buf.l, r: buf.r, ctx: ctx, songBeat: beat)
            for i in 0..<n { outL[done + i] = buf.l[i]; outR[done + i] = buf.r[i] }
            done += n
        }
        return (outL, outR)
    }
}

extension AudioEngine {
    /// Runs the real-time render path without an audio device (tests only).
    func renderForTesting(frames: Int) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(frames)
        var done = 0
        os_unfair_lock_lock(lockPtrForTesting)
        while done < frames {
            let n = min(512, frames - done)
            renderBlockForTesting(n)
            out += Array(UnsafeBufferPointer(start: masterForTesting.l, count: n))
            done += n
        }
        os_unfair_lock_unlock(lockPtrForTesting)
        return out
    }

    func sessionStateForTesting(_ track: UUID) -> SessionInfo? { snapshot().sessions[track] }
}

public struct PhraseNote {
    public var beat: Double, length: Double, pitch: Int, velocity: Double
    public init(_ beat: Double, _ length: Double, _ pitch: Int, _ velocity: Double = 0.8) {
        self.beat = beat; self.length = length; self.pitch = pitch; self.velocity = velocity
    }
}

struct PhraseEvent {
    let frame: Int
    let on: Bool
    let pitch: Int
    let velocity: Float
}
