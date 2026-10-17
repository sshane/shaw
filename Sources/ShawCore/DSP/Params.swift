import Foundation

public enum ParamUnit: Equatable {
    case none, db, hz, ms, percent, ratio, semitones, cents, seconds
    /// A MIDI note number, shown as a name ("C4" is 60, like the piano roll).
    case note
    case choice([String])
}

public enum ParamScale: Equatable { case linear, log }

public struct ParamDef: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let min: Double
    public let max: Double
    public let defaultValue: Double
    public let unit: ParamUnit
    public let scale: ParamScale

    public init(_ id: String, _ name: String, _ min: Double, _ max: Double, _ def: Double,
                _ unit: ParamUnit = .none, _ scale: ParamScale = .linear) {
        self.id = id
        self.name = name
        self.min = min
        self.max = max
        self.defaultValue = def
        self.unit = unit
        self.scale = scale
    }

    public static func choice(_ id: String, _ name: String, _ options: [String], _ def: Int = 0) -> ParamDef {
        ParamDef(id, name, 0, Double(options.count - 1), Double(def), .choice(options))
    }

    public var choices: [String]? {
        if case .choice(let c) = unit { return c }
        return nil
    }

    public func clamp(_ v: Double) -> Double { Swift.min(max, Swift.max(min, v)) }

    /// The same parameter with a different label (editors that already say which section it's in).
    public func renamed(_ newName: String) -> ParamDef {
        ParamDef(id, newName, min, max, defaultValue, unit, scale)
    }

    /// Map value to 0...1 for slider display.
    public func normalized(_ v: Double) -> Double {
        let v = clamp(v)
        switch scale {
        case .linear: return (v - min) / (max - min)
        case .log: return log(v / min) / log(max / min)
        }
    }

    public func value(fromNormalized n: Double) -> Double {
        let n = Swift.min(1, Swift.max(0, n))
        var v: Double
        switch scale {
        case .linear: v = min + n * (max - min)
        case .log: v = min * pow(max / min, n)
        }
        if choices != nil { v = v.rounded() }
        return v
    }

    public func format(_ v: Double) -> String {
        switch unit {
        case .choice(let c): return c[Swift.max(0, Swift.min(c.count - 1, Int(v.rounded())))]
        case .db: return v <= -96 || (id == "volume" && v <= -59.9) ? "-inf dB" : String(format: "%.1f dB", v)
        case .hz: return v >= 1000 ? String(format: "%.2f kHz", v / 1000) : String(format: "%.0f Hz", v)
        case .ms: return String(format: "%.0f ms", v)
        case .seconds: return String(format: "%.2f s", v)
        case .percent: return String(format: "%.0f%%", v * 100)
        case .ratio: return String(format: "%.1f:1", v)
        case .semitones: return String(format: "%+.0f st", v)
        case .cents: return String(format: "%+.0f ct", v)
        case .note: return ParamDef.noteName(Int(v.rounded()))
        case .none: return String(format: "%.2f", v)
        }
    }

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// 60 → "C4".
    public static func noteName(_ pitch: Int) -> String {
        let p = Swift.max(0, Swift.min(127, pitch))
        return "\(noteNames[p % 12])\(p / 12 - 1)"
    }

    /// "C4", "f#2", "Db3", or a plain number ("60") → MIDI note.
    public static func parseNote(_ text: String) -> Double? {
        let s = text.trimmingCharacters(in: .whitespaces).uppercased()
        if let n = Double(s) { return n }
        guard let letter = s.first, let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(letter)] else { return nil }
        var rest = s.dropFirst()
        var semi = base
        if rest.first == "#" { semi += 1; rest = rest.dropFirst() } else if rest.first == "B" && rest.count > 1 { semi -= 1; rest = rest.dropFirst() }
        guard let octave = Int(rest) else { return nil }
        return Double((octave + 1) * 12 + semi)
    }
}

public extension Array where Element == ParamDef {
    /// Resolve stored params (which may be missing keys) into a dense array in definition order.
    func resolve(_ stored: [String: Double]) -> [Double] {
        map { $0.clamp(stored[$0.id] ?? $0.defaultValue) }
    }

    func defaults() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: map { ($0.id, $0.defaultValue) })
    }
}

/// Note divisions used by tempo-synced parameters, as beats.
public enum SyncDivision {
    public static let names = ["1/32", "1/16T", "1/16", "1/16D", "1/8T", "1/8", "1/8D", "1/4T", "1/4", "1/4D", "1/2", "1 bar"]
    public static let beats: [Double] = [0.125, 1.0 / 6, 0.25, 0.375, 1.0 / 3, 0.5, 0.75, 2.0 / 3, 1, 1.5, 2, 4]
}
