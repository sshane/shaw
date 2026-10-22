import Foundation

/// Pitch correction for a recorded voice or instrument, saved with the recording. Natural by default:
/// it moves only the center of each sung note toward the key and eases into it, keeping the vibrato
/// and the slides between notes, the way the good pitch editors do. Turned all the way, it's the hard,
/// stepping "robot" sound.
public struct VocalTune: Codable, Equatable, Hashable {
    public enum Scale: String, Codable, CaseIterable {
        /// From the song's own notes (or the take's, if the song has none).
        case auto
        case major, minor
        /// Every semitone: just in tune, no key.
        case chromatic
    }

    /// A key: its root (0 = C ... 11 = B) and whether it's minor.
    public struct Key: Codable, Equatable, Hashable {
        public var root: Int
        public var minor: Bool
        public init(root: Int, minor: Bool) { self.root = root; self.minor = minor }
        public static let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        public var name: String { "\(Self.noteNames[((root % 12) + 12) % 12]) \(minor ? "minor" : "major")" }
    }

    public var enabled = true
    /// How far each note's center moves to the nearest note in the key (0...1).
    public var amount = 0.8
    /// How long the correction takes to settle at the start of a note, ms (0: instant, the hard sound).
    public var speed = 40.0
    /// Vibrato and other quick movement: 1 keeps it as sung, 0 flattens it, above 1 deepens it.
    public var vibrato = 1.0
    /// Slow wander within a note: 0 keeps it, 1 straightens the note completely.
    public var straighten = 0.3
    public var scale: Scale = .auto
    /// The key's root (0 = C ... 11 = B), for major and minor. Nil with auto.
    public var root: Int?

    public init() {}

    public static let natural = VocalTune()
    public static var tight: VocalTune { var t = VocalTune(); t.amount = 1; t.speed = 15; t.straighten = 0.6; return t }
    public static var robot: VocalTune { var t = VocalTune(); t.amount = 1; t.speed = 0; t.straighten = 1; t.vibrato = 0; return t }

    /// The same correction style as `preset`, keeping this one's key and on/off.
    public func styled(like preset: VocalTune) -> VocalTune {
        var t = preset
        t.enabled = enabled; t.scale = scale; t.root = root
        return t
    }

    /// True when the style settings (everything but the key) match `preset`'s.
    public func hasStyle(of preset: VocalTune) -> Bool { styled(like: preset) == self }

    // Older or newer projects may lack some settings: missing ones take their defaults.
    enum CodingKeys: String, CodingKey { case enabled, amount, speed, vibrato, straighten, scale, root }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VocalTune()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? d.amount
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        vibrato = try c.decodeIfPresent(Double.self, forKey: .vibrato) ?? d.vibrato
        straighten = try c.decodeIfPresent(Double.self, forKey: .straighten) ?? d.straighten
        scale = (try? c.decodeIfPresent(Scale.self, forKey: .scale)) ?? d.scale
        root = try c.decodeIfPresent(Int.self, forKey: .root)
    }

    /// The key notes snap to: the chosen one, or with auto the song's (or else the take's own). Nil: chromatic.
    public func key(song: Key?, take: Key?) -> Key? {
        switch scale {
        case .chromatic: return nil
        case .major: return Key(root: root ?? 0, minor: false)
        case .minor: return Key(root: root ?? 0, minor: true)
        case .auto: return song ?? take
        }
    }

    /// The notes a pitch can snap to, as pitch classes (every semitone without a key).
    public static func pitchClasses(_ key: Key?) -> Set<Int> {
        key.map { scale($0.root, minor: $0.minor) } ?? Set(0..<12)
    }

    /// The most likely key for notes that sound for `weights[pc]` (beats or seconds per pitch class),
    /// by how well they fit each key's typical profile (Krumhansl and Kessler's). Nil without notes.
    public static func detectKey(_ weights: [Double]) -> Key? {
        guard weights.count == 12, weights.reduce(0, +) > 0 else { return nil }
        let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        func fit(_ profile: [Double], _ root: Int) -> Double {
            let a = (0..<12).map { weights[($0 + root) % 12] }
            let ma = a.reduce(0, +) / 12, mp = profile.reduce(0, +) / 12
            var num = 0.0, da = 0.0, dp = 0.0
            for i in 0..<12 { num += (a[i] - ma) * (profile[i] - mp); da += (a[i] - ma) * (a[i] - ma); dp += (profile[i] - mp) * (profile[i] - mp) }
            return num / max(1e-12, sqrt(da * dp))
        }
        var best = Key(root: 0, minor: false), bv = -Double.infinity
        for root in 0..<12 {
            for (minor, profile) in [(false, major), (true, minor)] {
                let v = fit(profile, root)
                if v > bv { bv = v; best = Key(root: root, minor: minor) }
            }
        }
        return best
    }

    /// The key a take is sung in, from its notes.
    public static func key(of notes: [SungNote]) -> Key? {
        var w = [Double](repeating: 0, count: 12)
        for n in notes { w[((Int(n.center.rounded()) % 12) + 12) % 12] += Double(n.end - n.start) }
        return detectKey(w)
    }

    public static func scale(_ root: Int, minor: Bool) -> Set<Int> {
        Set((minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]).map { ($0 + root) % 12 })
    }

    /// Where a note sung at `midi` belongs: the nearest note of the key within 60 cents. A note sung
    /// clearly on a semitone outside the key (a passing note, a blue note) is kept on that semitone,
    /// just in tune, rather than dragged to a different note.
    public static func snap(_ midi: Double, to classes: Set<Int>) -> Double {
        let nearest = midi.rounded()
        guard !classes.isEmpty, !classes.contains(((Int(nearest) % 12) + 12) % 12) else { return nearest }
        var best = nearest, bd = 0.6
        for k in Int(nearest) - 2...Int(nearest) + 2 where classes.contains(((k % 12) + 12) % 12) {
            let d = abs(Double(k) - midi)
            if d < bd { bd = d; best = Double(k) }
        }
        return best
    }

    /// How far to move the pitch at each frame of `track`, in cents.
    public func corrections(_ track: PitchTrack, notes: [SungNote], classes: Set<Int>) -> [Float] {
        let n = track.pitch.count
        var center = [Float](repeating: 0, count: n), shape = [Float](repeating: 0, count: n)
        let driftScale = Float(1 - straighten), modScale = Float(vibrato)
        for note in notes {
            let move = Float(amount * (Self.snap(note.center, to: classes) - note.center) * 100)
            for k in note.start..<min(note.end, n) {
                let i = k - note.start
                center[k] = move
                // A stray frame far from the note (a misheard octave) is left alone rather than "corrected" by an octave.
                guard abs(note.drift[i] + note.modulation[i]) < 2 else { continue }
                shape[k] = ((driftScale - 1) * note.drift[i] + (modScale - 1) * note.modulation[i]) * 100
            }
            // Hold the note's correction through the gap after it, so a legato change glides to the next.
            var k = note.end
            while k < n && track.pitch[k] == 0 && k < note.end + Int(0.04 / track.frameSeconds) { center[k] = move; k += 1 }
        }
        // Speed: ease the center move in, frame by frame (instant at 0).
        if speed > 0 {
            let a = Float(1 - exp(-track.frameSeconds / (speed / 1000)))
            var y: Float = 0
            for k in 0..<n { y += (center[k] - y) * a; center[k] = y }
        }
        return (0..<n).map { center[$0] + shape[$0] }
    }

    /// The tuned take: track it, find its notes, and shift each moment by its correction.
    public func render(_ x: [Float], sampleRate: Double, classes: Set<Int>, analysis: (PitchTrack, [SungNote])? = nil) -> [Float] {
        let (track, notes) = analysis ?? {
            let t = PitchTracker.track(x, sampleRate: sampleRate)
            return (t, NoteFinder.notes(in: t))
        }()
        return PitchShifter.shift([x], track: track, cents: corrections(track, notes: notes, classes: classes))[0]
    }
}

extension Project {
    /// The key the song's notes are in (drums aside), weighted by how long each note sounds. Nil
    /// when the song has no notes yet.
    public var songKey: VocalTune.Key? {
        var w = [Double](repeating: 0, count: 12)
        for a in assets {
            guard case .notes(let p) = a.content, !p.instrument.isDrumKit else { continue }
            for n in p.notes { w[((n.pitch % 12) + 12) % 12] += n.length }
        }
        return VocalTune.detectKey(w)
    }
}
