import Foundation
import ShawCore

/// Starter content. `make()` is a complete arranged song that shows off linked
/// compositions, patterns, beats, effects at every level and session clips.
enum DemoProject {
    static func empty() -> Project {
        var p = Project(name: "Untitled", bpm: 124)
        // No tracks: adding an instrument creates its track, so there's nothing to figure out first.
        p.updateComposition(p.mainCompositionID) { c in
            c.length = 32
            c.tracks = []
            // A light master chain, like a finished song: glue the mix together, then bring it up to volume.
            c.effects = [effect("compressor", ["threshold": -14, "ratio": 2, "attack": 30, "release": 150, "makeup": 1]),
                         effect("limiter", ["gain": 3, "ceiling": -0.5])]
        }
        return p
    }

    // MARK: Helpers

    static func effect(_ kind: String, _ params: [String: Double] = [:]) -> Effect {
        var e = EffectRegistry.descriptor(kind)!.makeEffect()
        for (k, v) in params { e.params[k] = v }
        return e
    }

    static func notes(_ list: [(Int, Double, Double)], vel: Double = 0.8) -> [Note] {
        list.map { Note(pitch: $0.0, start: $0.1, length: $0.2, velocity: vel) }
    }

    static func beat(_ kit: String, steps: Int = 16, _ pattern: [String: [Int]],
                     velocities: [String: [Int: Double]] = [:], swing: Double = 0) -> DrumPattern {
        var d = DrumPattern(kit: kit, steps: steps, swing: swing)
        for i in d.rows.indices {
            let s = d.rows[i].sound
            for step in pattern[s] ?? [] where step < steps { d.rows[i].steps[step] = velocities[s]?[step] ?? 0.85 }
        }
        return d
    }

    static func track(_ name: String, _ color: Int, volume: Double = 0, pan: Double = 0, _ clips: [Clip], effects: [Effect] = []) -> Track {
        var t = Track(name: name, colorIndex: color)
        t.volume = volume
        t.pan = pan
        t.clips = clips
        t.effects = effects
        return t
    }

    /// Loops only when the clip is longer than its source (like an Option-dragged edge).
    static func clip(_ a: Asset, at start: Double, length: Double, loops: Bool? = nil) -> Clip {
        let source: Double
        switch a.content {
        case .composition(let c): source = c.length
        case .notes(let n): source = n.length
        case .drums(let d): source = d.length
        case .audio: source = length
        }
        return Clip(assetID: a.id, start: start, length: length, loops: loops ?? (length > source + 1e-9))
    }

    // MARK: Demo songs

    /// The default demo.
    static func make() -> Project { sunroom() }

    static func keyframed(_ kind: String, _ params: [String: Double] = [:], _ param: String, _ points: [(Double, Double)]) -> Effect {
        var e = effect(kind, params)
        e.keyframes[param] = points.map { Keyframe(time: $0.0, value: $0.1) }
        return e
    }
}
