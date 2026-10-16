import Foundation

public enum ParamUnit: Equatable {
    case none, db, hz, ms, percent, ratio, semitones, cents, seconds
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
        case .none: return String(format: "%.2f", v)
        }
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
