import Foundation

/// An instrument you saved yourself: a synth sound (and optionally its layer effects) with a name.
/// Patterns keep their own copy of the sound, so a project still plays the same without your library.
public struct CustomInstrument: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var params: [String: Double]
    public var effects: [Effect]
    /// The preset it started from, if any ("Strings").
    public var basedOn: String?

    public init(name: String, params: [String: Double], effects: [Effect] = [], basedOn: String? = nil) {
        self.name = name
        self.params = params
        self.effects = effects
        self.basedOn = basedOn
    }
}

/// The user's saved instruments, readable from anywhere a preset name is looked up.
/// The app keeps this in sync with the library on disk (main thread only).
public enum UserInstruments {
    public static var items: [CustomInstrument] = []

    public static func named(_ name: String) -> CustomInstrument? { items.first { $0.name == name } }
}

/// Where a pattern's sound stands compared with the instrument it's named after.
public enum InstrumentStatus: Equatable {
    case builtIn, custom, edited, unsaved
}

extension SynthPresets {
    public static func isBuiltIn(_ name: String) -> Bool { overrides[name] != nil }

    /// Older projects marked edited sounds with a trailing "*". Now "edited" is worked out by comparing.
    public static func baseName(_ name: String) -> String {
        name.hasSuffix("*") ? String(name.dropLast()) : name
    }

    /// Whether `instrument` still sounds exactly like the preset or saved instrument it's named after.
    public static func status(of instrument: Instrument) -> InstrumentStatus {
        let name = baseName(instrument.preset)
        let builtIn = isBuiltIn(name)
        guard builtIn || UserInstruments.named(name) != nil else { return .unsaved }
        let saved = SynthParams.defs.resolve(params(for: name))
        let mine = SynthParams.defs.resolve(instrument.params)
        let same = zip(saved, mine).allSatisfy { abs($0 - $1) < 1e-9 }
        return same ? (builtIn ? .builtIn : .custom) : .edited
    }

    /// A plain sine wave with a quick, clean envelope: the blank canvas for building a sound.
    public static func scratch() -> [String: Double] {
        var p = SynthParams.defs.defaults()
        for (k, v) in ["osc1": 0, "mix": 0.5, "lvl1": 1, "on2": 0, "lvl2": 0.6, "osc2": 0, "semi2": 12, "fine2": 0, "fenv": 0,
                       "cutoff": 20000, "resonance": 0, "keytrack": 0, "a": 0.005, "d": 0.3, "s": 0.8, "r": 0.3,
                       "drift": 0.15, "volume": -6] as [String: Double] {
            p[k] = v
        }
        return p
    }
}

/// The instrument editor shows every oscillator with its own level (0–1, where 1 adds 0.5 to the mix).
/// Osc 1 and 2 actually crossfade with Osc Mix; this converts to and from that, keeping the sound identical.
public enum OscillatorLevels {
    /// Effective levels of osc 1–4 (0 when an oscillator is off).
    public static func levels(_ p: [String: Double]) -> [Double] {
        func v(_ k: String) -> Double { p[k] ?? SynthParams.defs.first { $0.id == k }!.defaultValue }
        let mix = v("mix")
        return [v("lvl1") * (1 - mix) * 2,
                v("on2") > 0.5 ? v("lvl2") * mix * 2 : 0,
                v("on3") > 0.5 ? v("lvl3") : 0,
                v("on4") > 0.5 ? v("lvl4") : 0]
    }

    /// Rewrite `p` so Osc Mix sits in the middle and each lvl is the effective level (scaled to fit
    /// 0–1, with Osc Level making up the difference before the filter and drive). Sounds identical.
    public static func normalized(_ p: [String: Double]) -> [String: Double] {
        var q = p
        var lv = levels(p)
        let k = max(1, lv.max() ?? 1)
        if k > 1 {
            // Osc Level scales every oscillator and the sub, so divide those and raise it.
            lv = lv.map { $0 / k }
            q["osclevel"] = (p["osclevel"] ?? 1) * k
            q["sub"] = (p["sub"] ?? 0) / k
        }
        q["mix"] = 0.5
        q["lvl1"] = lv[0]
        q["lvl2"] = lv[1]
        if (q["on3"] ?? 0) > 0.5 { q["lvl3"] = lv[2] }
        if (q["on4"] ?? 0) > 0.5 { q["lvl4"] = lv[3] }
        return q
    }
}
