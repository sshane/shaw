import Foundation

public typealias AssetID = UUID

/// A Shaw project. Everything is a value type so the whole project can be
/// snapshotted for undo and handed to the audio engine safely.
public struct Project: Codable, Equatable {
    public var name: String
    public var bpm: Double
    public var beatsPerBar: Int
    /// Everything in the Project panel, in display order.
    public var assets: [Asset]
    public var folders: [Folder]
    /// The composition that opens by default (like a main sequence).
    public var mainCompositionID: AssetID
    public var masterVolume: Double // dB

    public init(name: String = "Untitled", bpm: Double = 120, beatsPerBar: Int = 4) {
        self.name = name
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        let main = Asset(name: "Main", colorIndex: 0, content: .composition(Composition(length: 64)))
        self.assets = [main]
        self.folders = []
        self.mainCompositionID = main.id
        self.masterVolume = 0
    }

    // MARK: Lookup

    public func index(of id: AssetID) -> Int? { assets.firstIndex { $0.id == id } }

    public func asset(_ id: AssetID) -> Asset? {
        guard let i = index(of: id) else { return nil }
        return assets[i]
    }

    public func composition(_ id: AssetID) -> Composition? {
        if case .composition(let c)? = asset(id)?.content { return c }
        return nil
    }

    /// Mutate a composition in place. Returns false if `id` is not a composition.
    @discardableResult
    public mutating func updateComposition(_ id: AssetID, _ body: (inout Composition) -> Void) -> Bool {
        guard let i = index(of: id), case .composition(var c) = assets[i].content else { return false }
        body(&c)
        assets[i].content = .composition(c)
        return true
    }

    @discardableResult
    public mutating func updateNotes(_ id: AssetID, _ body: (inout NotePattern) -> Void) -> Bool {
        guard let i = index(of: id), case .notes(var p) = assets[i].content else { return false }
        body(&p)
        assets[i].content = .notes(p)
        return true
    }

    @discardableResult
    public mutating func updateDrums(_ id: AssetID, _ body: (inout DrumPattern) -> Void) -> Bool {
        guard let i = index(of: id), case .drums(var p) = assets[i].content else { return false }
        body(&p)
        assets[i].content = .drums(p)
        return true
    }

    public mutating func updateAsset(_ id: AssetID, _ body: (inout Asset) -> Void) {
        guard let i = index(of: id) else { return }
        body(&assets[i])
    }

    /// Natural length of an asset in beats (what a clip shows before trimming or looping).
    public func sourceLength(of id: AssetID) -> Double {
        guard let a = asset(id) else { return 4 }
        switch a.content {
        case .composition(let c): return c.length
        case .notes(let p): return p.length
        case .drums(let p): return p.length
        case .audio(let f): return max(f.duration * bpm / 60, 1.0 / 64)
        }
    }

    // MARK: Graph queries

    /// True if `container` (directly or through nesting) uses composition `target`.
    /// Used to refuse edits that would make a composition contain itself.
    public func composition(_ container: AssetID, contains target: AssetID, visited: Set<AssetID> = []) -> Bool {
        if container == target { return true }
        guard !visited.contains(container), let comp = composition(container) else { return false }
        var seen = visited
        seen.insert(container)
        for track in comp.tracks {
            for id in track.referencedAssetIDs where composition(id) != nil {
                if composition(id, contains: target, visited: seen) { return true }
            }
        }
        return false
    }

    /// Number of places an asset is used (timeline clips and session slots).
    public func usageCount(of id: AssetID) -> Int {
        var n = 0
        for a in assets {
            guard case .composition(let c) = a.content else { continue }
            for t in c.tracks { n += t.referencedAssetIDs.filter { $0 == id }.count }
        }
        return n
    }

    /// Next unused name such as "Pattern 3".
    public func uniqueName(_ base: String, excluding: AssetID? = nil) -> String {
        let names = Set(assets.filter { $0.id != excluding }.map(\.name))
        if !names.contains(base) { return base }
        var i = 2
        while names.contains("\(base) \(i)") { i += 1 }
        return "\(base) \(i)"
    }

    public var secondsPerBeat: Double { 60 / bpm }
}

public struct Folder: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var expanded = true
    public init(name: String) { self.name = name }
}

public struct Asset: Codable, Equatable, Identifiable {
    public var id: AssetID
    public var name: String
    public var colorIndex: Int
    public var folderID: UUID?
    public var content: AssetContent

    public init(id: AssetID = UUID(), name: String, colorIndex: Int, folderID: UUID? = nil, content: AssetContent) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.folderID = folderID
        self.content = content
    }

    public var kind: AssetKind {
        switch content {
        case .composition: return .composition
        case .audio: return .audio
        case .notes: return .notes
        case .drums: return .drums
        }
    }
}

public enum AssetKind: String, Codable {
    case composition, audio, notes, drums

    public var label: String {
        switch self {
        case .composition: return "Composition"
        case .audio: return "Audio"
        case .notes: return "Pattern"
        case .drums: return "Beat"
        }
    }
}

public enum AssetContent: Codable, Equatable {
    case composition(Composition)
    case audio(AudioFileRef)
    case notes(NotePattern)
    case drums(DrumPattern)
}

// MARK: - Composition

/// A composition is a container of tracks, exactly like an After Effects comp.
/// Dropping it into another composition creates a *linked* clip: editing the
/// composition changes every place it is used.
public struct Composition: Codable, Equatable {
    public var length: Double // beats
    public var tracks: [Track]
    public var effects: [Effect]
    public var volume: Double // dB
    public var sceneCount: Int

    public init(length: Double, tracks: [Track] = [], effects: [Effect] = [], volume: Double = 0, sceneCount: Int = 8) {
        self.length = length
        self.tracks = tracks
        self.effects = effects
        self.volume = volume
        self.sceneCount = sceneCount
    }

    public func trackIndex(_ id: UUID) -> Int? { tracks.firstIndex { $0.id == id } }

    /// Locate a clip by id: (track index, clip index).
    public func locate(clip id: UUID) -> (Int, Int)? {
        for (ti, t) in tracks.enumerated() {
            if let ci = t.clips.firstIndex(where: { $0.id == id }) { return (ti, ci) }
        }
        return nil
    }

    public mutating func updateClip(_ id: UUID, _ body: (inout Clip) -> Void) {
        guard let (ti, ci) = locate(clip: id) else { return }
        body(&tracks[ti].clips[ci])
    }

    public var hasSolo: Bool { tracks.contains { $0.solo } }

    /// End of the last clip, for sizing the view.
    public var contentEnd: Double { tracks.flatMap(\.clips).map(\.end).max() ?? 0 }
}

public struct Track: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var colorIndex: Int
    public var volume: Double = 0 // dB
    public var pan: Double = 0    // -1 ... 1
    public var mute = false
    public var solo = false
    public var effects: [Effect] = []
    public var clips: [Clip] = []
    /// Session (clip launcher) slots, indexed by scene.
    public var slots: [Int: SessionClip] = [:]

    public init(name: String, colorIndex: Int) {
        self.name = name
        self.colorIndex = colorIndex
    }

    public var referencedAssetIDs: [AssetID] {
        clips.map(\.assetID) + slots.values.map(\.assetID)
    }
}

/// One placement of an asset on a timeline track. The clip only stores *where*
/// and *how much* of the asset plays; the content itself stays in the asset.
public struct Clip: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var assetID: AssetID
    /// Position on the track, in beats.
    public var start: Double
    /// Visible length, in beats.
    public var length: Double
    /// How far into the source the clip begins, in beats (trimmed head).
    public var offset: Double = 0
    /// When true, content repeats past its natural end instead of going silent.
    public var loops = false
    public var gain: Double = 0 // dB
    public var mute = false
    public var effects: [Effect] = []

    public init(assetID: AssetID, start: Double, length: Double, offset: Double = 0, loops: Bool = false) {
        self.assetID = assetID
        self.start = start
        self.length = length
        self.offset = offset
        self.loops = loops
    }

    public var end: Double { start + length }
}

public struct SessionClip: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var assetID: AssetID
    public init(assetID: AssetID) { self.assetID = assetID }
}

// MARK: - Effects

public struct Effect: Codable, Equatable, Identifiable {
    public var id = UUID()
    /// Identifier into `EffectRegistry`, e.g. "reverb".
    public var kind: String
    public var enabled = true
    public var params: [String: Double]
    public var expanded = true
    /// Keyframes per parameter id, sorted by time. A parameter with keyframes is animated
    /// (like a property with its stopwatch on in After Effects) and ignores `params`.
    /// Times are beats: clip time for clip effects, composition time for track/composition effects.
    public var keyframes: [String: [Keyframe]] = [:]

    public init(kind: String, params: [String: Double] = [:]) {
        self.kind = kind
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case id, kind, enabled, params, expanded, keyframes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        params = try c.decodeIfPresent([String: Double].self, forKey: .params) ?? [:]
        expanded = try c.decodeIfPresent(Bool.self, forKey: .expanded) ?? true
        keyframes = try c.decodeIfPresent([String: [Keyframe]].self, forKey: .keyframes) ?? [:]
    }

    public func isAnimated(_ param: String) -> Bool { !(keyframes[param] ?? []).isEmpty }

    /// The parameter's value at a moment (its keyframed value if animated).
    public func value(of def: ParamDef, at time: Double) -> Double {
        if let keys = keyframes[def.id], !keys.isEmpty {
            return def.clamp(Keyframe.interpolate(keys, at: time, hold: def.choices != nil))
        }
        return def.clamp(params[def.id] ?? def.defaultValue)
    }

    /// Set a value at a time on an animated parameter: updates the keyframe there, or adds one.
    public mutating func setKeyframe(_ param: String, time: Double, value: Double, tolerance: Double = 1.0 / 128) {
        var keys = keyframes[param] ?? []
        if let i = keys.firstIndex(where: { abs($0.time - time) <= tolerance }) {
            keys[i].value = value
        } else {
            keys.append(Keyframe(time: max(0, time), value: value))
            keys.sort { $0.time < $1.time }
        }
        keyframes[param] = keys
    }
}

/// One After Effects-style keyframe (a ◆ on the timeline).
public struct Keyframe: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var time: Double  // beats
    public var value: Double

    public init(time: Double, value: Double) {
        self.time = time
        self.value = value
    }

    /// Linear between keyframes, held before the first and after the last. `hold` steps instead (for choices).
    public static func interpolate(_ keys: [Keyframe], at t: Double, hold: Bool) -> Double {
        guard let first = keys.first else { return 0 }
        if t <= first.time { return first.value }
        var lo = 0, hi = keys.count - 1
        if t >= keys[hi].time { return keys[hi].value }
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if keys[mid].time <= t { lo = mid } else { hi = mid }
        }
        let a = keys[lo], b = keys[hi]
        if hold || b.time <= a.time { return a.value }
        return a.value + (b.value - a.value) * (t - a.time) / (b.time - a.time)
    }
}

// MARK: - Audio files

public struct AudioFileRef: Codable, Equatable {
    public var path: String
    public var duration: Double // seconds
    public var sampleRate: Double
    public var channels: Int

    public init(path: String, duration: Double, sampleRate: Double, channels: Int) {
        self.path = path
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

// MARK: - Note patterns (piano roll)

public struct Note: Codable, Equatable, Identifiable, Hashable {
    public var id = UUID()
    public var pitch: Int      // MIDI note number
    public var start: Double   // beats
    public var length: Double  // beats
    public var velocity: Double // 0...1

    public init(pitch: Int, start: Double, length: Double, velocity: Double = 0.8) {
        self.pitch = pitch
        self.start = start
        self.length = length
        self.velocity = velocity
    }

    public var end: Double { start + length }
}

/// A piano-roll pattern. It carries its own instrument so it sounds the same
/// wherever it is placed.
public struct NotePattern: Codable, Equatable {
    public var length: Double
    public var notes: [Note]
    public var instrument: Instrument

    public init(length: Double = 16, notes: [Note] = [], instrument: Instrument = Instrument()) {
        self.length = length
        self.notes = notes
        self.instrument = instrument
    }
}

/// What a pattern sounds like: the Shaw Synth with a preset, or a drum kit.
/// With a kit, each note pitch is a drum sound (see `DrumKits.pitch(of:)`), like Ableton's Drum Rack.
public struct Instrument: Codable, Equatable {
    public var preset: String
    public var params: [String: Double]
    /// Drum kit id; nil means the synth.
    public var kit: String?

    public init(preset: String = "Init", params: [String: Double] = [:], kit: String? = nil) {
        self.preset = preset
        self.params = params
        self.kit = kit
    }

    public static func preset(_ name: String) -> Instrument {
        Instrument(preset: name, params: SynthPresets.params(for: name))
    }

    public static func kit(_ id: String) -> Instrument {
        Instrument(preset: DrumKits.kitName(id), params: [:], kit: id)
    }

    public var isDrumKit: Bool { kit != nil }
}

// MARK: - Drum patterns (beat maker)

public struct DrumPattern: Codable, Equatable {
    public var kit: String
    public var steps: Int
    public var stepsPerBeat: Int
    public var swing: Double // 0...1
    public var rows: [DrumRow]

    public init(kit: String = DrumKits.defaultKit, steps: Int = 16, stepsPerBeat: Int = 4, swing: Double = 0, rows: [DrumRow]? = nil) {
        self.kit = kit
        self.steps = steps
        self.stepsPerBeat = stepsPerBeat
        self.swing = swing
        self.rows = rows ?? DrumKits.voices.map { DrumRow(sound: $0.id, steps: steps) }
    }

    public var length: Double { Double(steps) / Double(stepsPerBeat) }

    public mutating func resize(steps newCount: Int) {
        let n = max(1, min(newCount, 128))
        for i in rows.indices {
            if rows[i].steps.count < n {
                // Repeat existing content so growing a 1-bar beat to 2 bars keeps the groove.
                let old = rows[i].steps
                rows[i].steps = (0..<n).map { $0 < old.count ? old[$0] : (old.isEmpty ? 0 : old[$0 % old.count]) }
            } else {
                rows[i].steps = Array(rows[i].steps.prefix(n))
            }
        }
        steps = n
    }
}

public struct DrumRow: Codable, Equatable, Identifiable {
    public var id = UUID()
    /// Sound identifier inside the kit, e.g. "kick".
    public var sound: String
    /// Velocity per step; 0 means off.
    public var steps: [Double]
    public var volume: Double = 0 // dB
    public var pitch: Double = 0  // semitones
    public var pan: Double = 0
    public var mute = false

    public init(sound: String, steps: Int) {
        self.sound = sound
        self.steps = Array(repeating: 0, count: steps)
    }
}

// MARK: - Migration

extension DrumPattern {
    /// The same beat as a piano-roll pattern played by a drum kit.
    public func asNotePattern() -> NotePattern {
        let stepLen = 1.0 / Double(stepsPerBeat)
        var notes: [Note] = []
        for row in rows where !row.mute {
            let pitch = DrumKits.pitch(of: row.sound)
            let gain = dbToGain(row.volume)
            for (s, v) in row.steps.prefix(steps).enumerated() where v > 0 {
                let swingOffset = s % 2 == 1 ? swing * stepLen * 0.5 : 0
                notes.append(Note(pitch: pitch, start: Double(s) * stepLen + swingOffset, length: stepLen * 0.9,
                                  velocity: min(1, v * gain)))
            }
        }
        return NotePattern(length: length, notes: notes, instrument: .kit(kit))
    }
}

extension Project {
    /// Turn every step-sequencer beat into a drum-kit piano-roll pattern (same ids, same clips).
    public mutating func migrateDrumPatterns() {
        for i in assets.indices {
            if case .drums(let d) = assets[i].content { assets[i].content = .notes(d.asNotePattern()) }
        }
    }
}

// MARK: - Helpers

@inline(__always) public func dbToGain(_ db: Double) -> Double { db <= -96 ? 0 : pow(10, db / 20) }
@inline(__always) public func gainToDb(_ g: Double) -> Double { g <= 0.0000158 ? -96 : 20 * log10(g) }
