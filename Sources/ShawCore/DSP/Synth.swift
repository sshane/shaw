import Foundation

public enum SynthParams {
    public static let waves = ["Sine", "Triangle", "Saw", "Square"]

    public static let defs: [ParamDef] = [
        .choice("osc1", "Osc 1", waves, 2),
        .choice("osc2", "Osc 2", waves, 2),
        ParamDef("semi2", "Osc 2 Pitch", -24, 24, 0, .semitones),
        ParamDef("fine2", "Osc 2 Fine", -50, 50, 7, .cents),
        ParamDef("mix", "Osc Mix", 0, 1, 0.5, .percent),
        ParamDef("sub", "Sub Osc", 0, 1, 0, .percent),
        ParamDef("noise", "Noise", 0, 1, 0, .percent),
        .choice("unison", "Unison", ["Off", "3 Voices", "5 Voices", "7 Voices"], 0),
        ParamDef("spread", "Unison Spread", 0, 1, 0.3, .percent),
        ParamDef("cutoff", "Cutoff", 20, 20000, 6000, .hz, .log),
        ParamDef("resonance", "Resonance", 0, 1, 0.15, .percent),
        ParamDef("fenv", "Filter Env", -1, 1, 0.3, .percent),
        ParamDef("keytrack", "Key Track", 0, 1, 0.3, .percent),
        ParamDef("a", "Attack", 0.001, 10, 0.004, .seconds, .log),
        ParamDef("d", "Decay", 0.005, 5, 0.3, .seconds, .log),
        ParamDef("s", "Sustain", 0, 1, 0.75, .percent),
        ParamDef("r", "Release", 0.005, 8, 0.25, .seconds, .log),
        ParamDef("fa", "Filter Attack", 0.001, 10, 0.004, .seconds, .log),
        ParamDef("fd", "Filter Decay", 0.005, 5, 0.35, .seconds, .log),
        ParamDef("fs", "Filter Sustain", 0, 1, 0.3, .percent),
        ParamDef("fr", "Filter Release", 0.005, 8, 0.3, .seconds, .log),
        ParamDef("penv", "Pitch Env", 0, 48, 0, .semitones),
        ParamDef("pdecay", "Pitch Decay", 0.005, 1, 0.06, .seconds, .log),
        .choice("mode", "Voice Mode", ["Poly", "Mono", "Legato"], 0),
        ParamDef("glide", "Glide", 0, 1, 0, .seconds),
        ParamDef("drive", "Drive", 0, 1, 0, .percent),
        ParamDef("volume", "Volume", -36, 6, -8, .db),
        ParamDef("osclevel", "Osc Level", 0, 2, 1, .percent),
        // LFO: wobble the filter, add vibrato, or tremolo. Synced to the tempo unless set to Free.
        ParamDef("lforate", "LFO Rate", 0.05, 20, 5, .hz, .log),
        .choice("lfosync", "LFO Sync", ["Free", "1/16", "1/8", "1/8T", "1/4", "1/2", "1 bar"], 0),
        ParamDef("lfocut", "LFO → Filter", 0, 1, 0, .percent),
        ParamDef("lfopitch", "Vibrato", 0, 1, 0, .percent),
        ParamDef("lfoamp", "Tremolo", 0, 1, 0, .percent),
        // Added later, so they sit at the end to keep the indices below stable.
        .choice("ftype", "Filter Type", ["Low-pass", "Low-pass 24", "Band-pass", "High-pass"], 0),
        ParamDef("fm", "FM", 0, 1, 0, .percent),
        .choice("lfoshape", "LFO Shape", ["Sine", "Triangle", "Saw Down", "Saw Up", "Square", "Random"], 0),
        ParamDef("lfofm", "LFO → FM", 0, 1, 0, .percent),
        ParamDef("drift", "Drift", 0, 1, 0.25, .percent),
        // Oscillator levels and two extra oscillators, for building sounds from scratch.
        // Osc 1 and 2 still crossfade with Osc Mix, so older presets sound the same.
        ParamDef("semi1", "Osc 1 Pitch", -24, 24, 0, .semitones),
        ParamDef("lvl1", "Osc 1 Level", 0, 1, 1, .percent),
        ParamDef("lvl2", "Osc 2 Level", 0, 1, 1, .percent),
        .choice("on2", "Osc 2", ["Off", "On"], 1),
        .choice("osc3", "Osc 3", waves, 0),
        ParamDef("semi3", "Osc 3 Pitch", -24, 24, 12, .semitones),
        ParamDef("fine3", "Osc 3 Fine", -50, 50, 0, .cents),
        ParamDef("lvl3", "Osc 3 Level", 0, 1, 0.5, .percent),
        .choice("on3", "Osc 3", ["Off", "On"], 0),
        .choice("osc4", "Osc 4", waves, 0),
        ParamDef("semi4", "Osc 4 Pitch", -24, 24, 19, .semitones),
        ParamDef("fine4", "Osc 4 Fine", -50, 50, 0, .cents),
        ParamDef("lvl4", "Osc 4 Level", 0, 1, 0.5, .percent),
        .choice("on4", "Osc 4", ["Off", "On"], 0),
    ]

    /// Beats per LFO cycle for each `lfosync` choice (0 = free running in Hz).
    static let lfoSyncBeats: [Double] = [0, 0.25, 0.5, 1.0 / 3, 1, 2, 4]

    /// The handful of synth controls shown by default.
    public static let basic = ["cutoff", "resonance", "a", "r", "volume"]

    static let index: [String: Int] = Dictionary(uniqueKeysWithValues: defs.enumerated().map { ($1.id, $0) })

    // Indices into the resolved parameter array.
    static let osc1 = 0, osc2 = 1, semi2 = 2, fine2 = 3, mix = 4, sub = 5, noise = 6, unison = 7, spread = 8
    static let cutoff = 9, res = 10, fenv = 11, keytrack = 12, a = 13, d = 14, s = 15, r = 16
    static let fa = 17, fd = 18, fs = 19, fr = 20, penv = 21, pdecay = 22, mode = 23, glide = 24, drive = 25, volume = 26, oscLevel = 27
    static let lfoRate = 28, lfoSync = 29, lfoCut = 30, lfoPitch = 31, lfoAmp = 32
    static let ftype = 33, fm = 34, lfoShape = 35, lfoFM = 36, drift = 37
    static let semi1 = 38, lvl1 = 39, lvl2 = 40, on2 = 41
    static let osc3 = 42, semi3 = 43, fine3 = 44, lvl3 = 45, on3 = 46
    static let osc4 = 47, semi4 = 48, fine4 = 49, lvl4 = 50, on4 = 51
}

public enum SynthPresets {
    public static let names = [
        "Reese Bass", "Sub Bass", "808 Bass", "Acid", "Wobble Bass", "Pluck Bass", "Deep Bass",
        "Keys", "Electric Piano", "Organ", "Bell", "Music Box",
        "Pluck", "Marimba", "Kalimba", "Stab",
        "Lead", "Supersaw", "Vibrato Lead", "Whistle",
        "Pad", "Warm Pad", "Dark Pad", "Glass Pad",
        "Strings", "Brass", "Pizzicato",
        "Chip Lead", "Chip Bass", "Chip Arp",
        "Noise Riser", "Downlifter", "Laser Zap", "Impact Boom",
        "Future Chords", "Wub Chords", "Dream Pluck", "Shimmer Lead", "Vowel Lead", "Heaven Pad",
        "Growl Bass", "Riddim Bass", "Bass House", "Neuro Reese", "Screech Lead", "Distorted 808", "Hoover",
        "Hyper Lead", "Glitter Pluck", "Hyper Saw", "Bubble Bass", "Digi Bell",
        "Init",
    ]

    public static let categories: [String: String] = {
        var c: [String: String] = [:]
        for n in ["Reese Bass", "Sub Bass", "808 Bass", "Acid", "Wobble Bass", "Pluck Bass", "Deep Bass"] { c[n] = "Bass" }
        for n in ["Keys", "Electric Piano", "Organ", "Bell", "Music Box"] { c[n] = "Keys" }
        for n in ["Pluck", "Marimba", "Kalimba", "Stab"] { c[n] = "Pluck" }
        for n in ["Lead", "Supersaw", "Vibrato Lead", "Whistle"] { c[n] = "Lead" }
        for n in ["Pad", "Warm Pad", "Dark Pad", "Glass Pad"] { c[n] = "Pad" }
        for n in ["Strings", "Brass", "Pizzicato"] { c[n] = "Strings & Brass" }
        for n in ["Chip Lead", "Chip Bass", "Chip Arp"] { c[n] = "Chiptune" }
        for n in ["Noise Riser", "Downlifter", "Laser Zap", "Impact Boom"] { c[n] = "FX" }
        for n in ["Future Chords", "Wub Chords", "Dream Pluck", "Shimmer Lead", "Vowel Lead", "Heaven Pad"] { c[n] = "Future Bass" }
        for n in ["Growl Bass", "Riddim Bass", "Bass House", "Neuro Reese", "Screech Lead", "Distorted 808", "Hoover"] { c[n] = "Dubstep & Bass House" }
        for n in ["Hyper Lead", "Glitter Pluck", "Hyper Saw", "Bubble Bass", "Digi Bell"] { c[n] = "Hyperpop" }
        c["Init"] = "Synth"
        return c
    }()

    // Waves: 0 sine, 1 triangle, 2 saw, 3 square. Unison: 0 off, 1 = 3 voices, 2 = 5, 3 = 7.
    // LFO sync: 0 free, 1 = 1/16, 2 = 1/8, 3 = 1/8T, 4 = 1/4, 5 = 1/2, 6 = 1 bar.
    // LFO shape: 0 sine, 1 triangle, 2 saw down, 3 saw up, 4 square, 5 random.
    // Filter type: 0 low-pass, 1 low-pass 24, 2 band-pass, 3 high-pass.
    public static let overrides: [String: [String: Double]] = [
        "Init": [:],
        // Bass
        "Reese Bass": ["osc1": 2, "osc2": 2, "fine2": 25, "unison": 1, "spread": 0.2, "cutoff": 700, "resonance": 0.2, "fenv": 0.1, "mode": 1, "glide": 0.04, "sub": 0.4, "drive": 0.3, "s": 1, "r": 0.15, "volume": -8],
        "Sub Bass": ["drift": 0, "osc1": 0, "osc2": 0, "mix": 0, "sub": 0, "cutoff": 400, "fenv": 0, "mode": 1, "glide": 0.03, "s": 1, "r": 0.12, "drive": 0.15, "volume": -11],
        "808 Bass": ["drift": 0, "osc1": 0, "osc2": 0, "mix": 0, "cutoff": 2000, "fenv": 0, "penv": 12, "pdecay": 0.04, "a": 0.002, "d": 2.2, "s": 0.0, "r": 0.4, "mode": 2, "glide": 0.06, "drive": 0.45, "volume": -4],
        "Acid": ["osc1": 2, "mix": 0, "cutoff": 400, "resonance": 0.85, "fenv": 0.75, "fd": 0.22, "fs": 0.05, "mode": 2, "glide": 0.06, "s": 0.9, "r": 0.08, "drive": 0.4, "keytrack": 0.5, "volume": -10],
        "Wobble Bass": ["osc1": 2, "osc2": 3, "fine2": 0, "mix": 0.4, "sub": 0.5, "cutoff": 280, "resonance": 0.55, "fenv": 0, "keytrack": 0.2, "mode": 1, "glide": 0.02, "s": 1, "r": 0.1, "drive": 0.5, "lfosync": 2, "lfocut": 0.75, "volume": -7],
        "Pluck Bass": ["osc1": 3, "osc2": 2, "mix": 0.3, "sub": 0.3, "cutoff": 500, "resonance": 0.3, "fenv": 0.6, "fd": 0.15, "fs": 0, "d": 0.35, "s": 0.2, "r": 0.08, "mode": 1, "volume": -6],
        "Deep Bass": ["osc1": 0, "osc2": 1, "semi2": 12, "mix": 0.25, "cutoff": 900, "fenv": 0.1, "s": 0.9, "r": 0.15, "mode": 1, "glide": 0.02, "drive": 0.2, "volume": -10],
        // Keys
        "Keys": ["osc1": 1, "osc2": 0, "semi2": 12, "mix": 0.3, "cutoff": 3000, "fenv": 0.3, "fd": 0.6, "d": 1.4, "s": 0.35, "r": 0.5, "volume": -8],
        "Electric Piano": ["osc1": 0, "osc2": 1, "semi2": 12, "mix": 0.25, "cutoff": 4000, "fenv": 0.2, "fd": 0.4, "keytrack": 0.5, "d": 1.6, "s": 0.25, "r": 0.4, "lforate": 4.5, "lfoamp": 0.25, "volume": -7],
        "Organ": ["osc1": 0, "osc2": 3, "semi2": 12, "mix": 0.35, "sub": 0.4, "cutoff": 3500, "fenv": 0, "a": 0.005, "d": 0.1, "s": 1, "r": 0.08, "lforate": 6, "lfopitch": 0.08, "volume": -12],
        "Bell": ["osc1": 0, "osc2": 1, "semi2": 19, "fine2": 0, "mix": 0.45, "cutoff": 9000, "fenv": 0, "a": 0.001, "d": 2.5, "s": 0, "r": 2, "volume": -8],
        "Music Box": ["osc1": 0, "osc2": 0, "semi2": 24, "fine2": 0, "mix": 0.3, "cutoff": 9000, "fenv": 0, "a": 0.001, "d": 1.2, "s": 0, "r": 0.8, "volume": -6],
        // Pluck
        "Pluck": ["osc2": 3, "semi2": 12, "mix": 0.35, "cutoff": 900, "resonance": 0.25, "fenv": 0.7, "fd": 0.18, "fs": 0, "d": 0.4, "s": 0, "r": 0.3, "keytrack": 0.6, "volume": -5],
        "Marimba": ["osc1": 0, "osc2": 1, "semi2": 24, "fine2": 0, "mix": 0.15, "cutoff": 5000, "fenv": 0, "a": 0.001, "d": 0.35, "s": 0, "r": 0.2, "volume": -4],
        "Kalimba": ["osc1": 1, "osc2": 0, "semi2": 12, "fine2": 0, "mix": 0.3, "cutoff": 3500, "fenv": 0.3, "fd": 0.1, "fs": 0, "d": 0.5, "s": 0, "r": 0.3, "volume": -4],
        "Stab": ["osc1": 2, "osc2": 2, "fine2": 15, "unison": 1, "spread": 0.4, "cutoff": 2500, "resonance": 0.2, "fenv": 0.5, "fd": 0.12, "fs": 0, "d": 0.18, "s": 0, "r": 0.12, "volume": -4],
        // Lead
        "Lead": ["osc1": 3, "osc2": 2, "fine2": 9, "cutoff": 4500, "resonance": 0.3, "fenv": 0.2, "mode": 2, "glide": 0.05, "s": 0.9, "r": 0.2, "drive": 0.2, "volume": -13],
        "Supersaw": ["unison": 3, "spread": 0.45, "fine2": 12, "cutoff": 9000, "fenv": 0.1, "a": 0.01, "s": 0.85, "r": 0.4, "volume": -12],
        "Vibrato Lead": ["osc1": 2, "osc2": 3, "fine2": 6, "cutoff": 5000, "resonance": 0.2, "fenv": 0.15, "a": 0.02, "s": 0.9, "r": 0.25, "mode": 2, "glide": 0.04, "lforate": 5.5, "lfopitch": 0.35, "volume": -10],
        "Whistle": ["osc1": 0, "osc2": 0, "mix": 0, "noise": 0.05, "cutoff": 6000, "fenv": 0, "a": 0.06, "s": 1, "r": 0.2, "mode": 2, "glide": 0.08, "lforate": 5, "lfopitch": 0.25, "volume": -12],
        // Pad
        "Pad": ["unison": 2, "spread": 0.5, "a": 0.9, "d": 1.5, "s": 0.8, "r": 2.2, "cutoff": 2500, "fenv": 0.25, "fa": 1.2, "fd": 2, "fs": 0.4, "volume": -14],
        "Warm Pad": ["osc1": 2, "osc2": 1, "fine2": 9, "unison": 1, "spread": 0.3, "cutoff": 1200, "resonance": 0.1, "fenv": 0.15, "a": 1.2, "d": 2, "s": 0.85, "r": 2.5, "fa": 1.5, "fd": 3, "fs": 0.5, "lforate": 0.3, "lfocut": 0.1, "volume": -12],
        "Dark Pad": ["osc1": 2, "osc2": 2, "unison": 2, "spread": 0.5, "cutoff": 600, "resonance": 0.25, "fenv": 0.3, "a": 1.5, "s": 0.9, "r": 3, "fa": 3, "fd": 4, "fs": 0.3, "volume": -10],
        "Glass Pad": ["osc1": 1, "osc2": 0, "semi2": 12, "fine2": 0, "mix": 0.4, "cutoff": 5000, "fenv": 0, "a": 0.8, "d": 2, "s": 0.7, "r": 2.5, "lforate": 3, "lfoamp": 0.15, "volume": -12],
        // Strings & Brass
        "Strings": ["osc1": 2, "osc2": 2, "fine2": 8, "unison": 2, "spread": 0.25, "cutoff": 3500, "fenv": 0.1, "a": 0.45, "d": 1, "s": 0.9, "r": 0.9, "lforate": 5, "lfopitch": 0.1, "volume": -14],
        "Brass": ["osc1": 2, "osc2": 2, "fine2": 5, "cutoff": 1200, "resonance": 0.15, "fenv": 0.55, "fa": 0.08, "fd": 0.4, "fs": 0.5, "a": 0.04, "d": 0.3, "s": 0.85, "r": 0.2, "keytrack": 0.5, "volume": -10],
        "Pizzicato": ["osc1": 2, "osc2": 1, "mix": 0.3, "cutoff": 2500, "fenv": 0.4, "fd": 0.08, "fs": 0, "a": 0.001, "d": 0.25, "s": 0, "r": 0.15, "volume": -3],
        // Chiptune
        "Chip Lead": ["drift": 0, "osc1": 3, "osc2": 3, "semi2": 12, "fine2": 0, "mix": 0.2, "cutoff": 20000, "resonance": 0, "fenv": 0, "keytrack": 0, "a": 0.001, "d": 0.1, "s": 0.8, "r": 0.05, "mode": 2, "glide": 0.03, "lforate": 7, "lfopitch": 0.2, "volume": -14],
        "Chip Bass": ["drift": 0, "osc1": 1, "osc2": 1, "fine2": 0, "mix": 0, "cutoff": 20000, "resonance": 0, "fenv": 0, "keytrack": 0, "a": 0.001, "s": 1, "r": 0.03, "mode": 1, "volume": -10],
        "Chip Arp": ["drift": 0, "osc1": 3, "osc2": 3, "fine2": 0, "mix": 0, "cutoff": 20000, "resonance": 0, "fenv": 0, "keytrack": 0, "a": 0.001, "d": 0.12, "s": 0.3, "r": 0.05, "volume": -10],
        // FX
        // White noise whose filter opens over ~8 seconds: hold one long note for a build-up.
        "Noise Riser": ["osclevel": 0, "noise": 1, "cutoff": 220, "resonance": 0.35, "fenv": 0.78, "keytrack": 0,
                        "fa": 7.5, "fd": 2, "fs": 1, "fr": 0.8, "a": 6, "d": 1, "s": 1, "r": 0.6, "volume": -10],
        // The reverse: bright noise that sweeps down and fades, for the moment after a drop.
        "Downlifter": ["osclevel": 0, "noise": 1, "cutoff": 12000, "resonance": 0.3, "fenv": -0.8, "keytrack": 0,
                       "fa": 4, "fd": 1, "fs": 1, "fr": 0.5, "a": 0.01, "d": 3, "s": 0, "r": 0.5, "volume": -9],
        // Future Bass: wide, bright, and pumping. Big chords, sparkly plucks, and soaring leads.
        "Future Chords": ["osc1": 2, "osc2": 2, "semi2": 12, "fine2": 0, "mix": 0.3, "unison": 3, "spread": 0.55, "cutoff": 7000, "resonance": 0.1,
                          "fenv": 0.15, "fd": 0.3, "a": 0.005, "d": 0.4, "s": 0.8, "r": 0.35, "volume": -13],
        "Wub Chords": ["osc1": 2, "osc2": 3, "fine2": 6, "mix": 0.35, "unison": 2, "spread": 0.5, "cutoff": 3500, "resonance": 0.2, "fenv": 0,
                       "a": 0.005, "s": 1, "r": 0.25, "lfosync": 3, "lfoshape": 2, "lfocut": 0.35, "lfoamp": 0.7, "volume": -13],
        "Dream Pluck": ["osc1": 2, "osc2": 3, "semi2": 12, "fine2": 0, "mix": 0.35, "unison": 1, "spread": 0.25, "cutoff": 1100, "resonance": 0.25,
                        "fenv": 0.65, "fd": 0.25, "fs": 0, "keytrack": 0.5, "a": 0.001, "d": 0.6, "s": 0, "r": 0.4, "volume": -8],
        "Shimmer Lead": ["osc1": 2, "osc2": 3, "semi2": 12, "fine2": 0, "mix": 0.3, "unison": 1, "spread": 0.15, "cutoff": 6000, "resonance": 0.15,
                         "fenv": 0.15, "a": 0.01, "s": 0.9, "r": 0.3, "mode": 2, "glide": 0.06, "lforate": 5.5, "lfopitch": 0.18, "volume": -13],
        "Vowel Lead": ["osc1": 2, "osc2": 2, "fine2": 10, "mix": 0.5, "ftype": 2, "cutoff": 1100, "resonance": 0.6, "fenv": 0.25, "fa": 0.05,
                       "fd": 0.25, "fs": 0.5, "keytrack": 0.4, "s": 1, "r": 0.2, "mode": 2, "glide": 0.05, "lforate": 4, "lfocut": 0.12, "volume": -7],
        "Heaven Pad": ["osc1": 2, "osc2": 1, "semi2": 12, "fine2": 0, "mix": 0.35, "unison": 3, "spread": 0.6, "cutoff": 4000, "resonance": 0.1,
                       "fenv": 0.2, "fa": 1, "fd": 2, "fs": 0.5, "a": 1.2, "d": 2, "s": 0.85, "r": 3, "volume": -15],
        // Dubstep & Bass House: moving, distorted basses and screeches. Keep these mono and low.
        "Growl Bass": ["osc1": 2, "osc2": 0, "fine2": 0, "mix": 0, "fm": 0.2, "lfofm": 0.6, "ftype": 1, "cutoff": 500, "resonance": 0.45,
                       "fenv": 0, "keytrack": 0.3, "lfosync": 2, "lfoshape": 1, "lfocut": 0.6, "sub": 0.5, "drive": 0.7,
                       "mode": 1, "glide": 0.03, "s": 1, "r": 0.1, "volume": -8],
        "Riddim Bass": ["osc1": 3, "osc2": 2, "semi2": 12, "fine2": 0, "mix": 0.25, "ftype": 1, "cutoff": 350, "resonance": 0.6, "fenv": 0,
                        "keytrack": 0.3, "lfosync": 3, "lfoshape": 2, "lfocut": 0.7, "sub": 0.5, "drive": 0.6,
                        "mode": 1, "glide": 0.02, "s": 1, "r": 0.08, "volume": -9],
        "Bass House": ["osc1": 3, "osc2": 2, "fine2": 15, "mix": 0.5, "sub": 0.35, "ftype": 1, "cutoff": 400, "resonance": 0.4, "fenv": 0.55,
                       "fd": 0.18, "fs": 0.15, "keytrack": 0.3, "d": 0.3, "s": 0.6, "r": 0.08, "mode": 1, "glide": 0.02, "drive": 0.6, "volume": -4],
        "Neuro Reese": ["osc1": 2, "osc2": 2, "fine2": 30, "mix": 0.5, "unison": 1, "spread": 0.3, "fm": 0.08, "ftype": 1, "cutoff": 900,
                        "resonance": 0.35, "fenv": 0, "lfosync": 5, "lfocut": 0.35, "sub": 0.4, "drive": 0.5,
                        "mode": 1, "glide": 0.04, "s": 1, "r": 0.15, "volume": -10],
        "Screech Lead": ["osc1": 2, "osc2": 2, "semi2": 12, "fine2": 0, "mix": 0.2, "fm": 0.5, "lfofm": 0.4, "lfosync": 2, "ftype": 2,
                         "cutoff": 2200, "resonance": 0.55, "fenv": 0, "lfocut": 0.4, "drive": 0.6, "mode": 2, "glide": 0.04,
                         "s": 1, "r": 0.1, "volume": -11],
        "Distorted 808": ["osc1": 0, "osc2": 0, "mix": 0, "cutoff": 3000, "fenv": 0, "penv": 12, "pdecay": 0.05, "a": 0.002, "d": 2.5, "s": 0,
                          "r": 0.3, "mode": 2, "glide": 0.08, "drive": 0.9, "drift": 0, "volume": -7],
        "Hoover": ["osc1": 2, "osc2": 2, "semi2": -12, "fine2": 0, "mix": 0.4, "unison": 3, "spread": 0.9, "cutoff": 3000, "resonance": 0.2,
                   "fenv": 0.2, "penv": 3, "pdecay": 0.1, "s": 1, "r": 0.3, "mode": 2, "glide": 0.08, "volume": -14],
        // Hyperpop: bright, glossy, a little broken on purpose.
        "Hyper Lead": ["osc1": 3, "osc2": 2, "semi2": 12, "fine2": 0, "mix": 0.35, "unison": 1, "spread": 0.2, "cutoff": 9000, "resonance": 0.1,
                       "fenv": 0, "a": 0.002, "s": 0.9, "r": 0.12, "mode": 2, "glide": 0.05, "lforate": 6.5, "lfopitch": 0.25,
                       "drive": 0.3, "drift": 0, "volume": -11],
        "Glitter Pluck": ["osc1": 1, "osc2": 3, "semi2": 24, "fine2": 0, "mix": 0.3, "cutoff": 6000, "fenv": 0.4, "fd": 0.08, "fs": 0,
                          "a": 0.001, "d": 0.25, "s": 0, "r": 0.2, "drift": 0.1, "volume": -7],
        "Hyper Saw": ["osc1": 2, "osc2": 2, "semi2": 12, "fine2": 0, "mix": 0.35, "unison": 3, "spread": 0.7, "cutoff": 12000, "fenv": 0,
                      "a": 0.003, "s": 0.9, "r": 0.25, "drive": 0.4, "volume": -12],
        "Bubble Bass": ["osc1": 1, "osc2": 0, "semi2": -12, "fine2": 0, "mix": 0.3, "cutoff": 1500, "fenv": 0.2, "fd": 0.15, "penv": 7,
                        "pdecay": 0.03, "a": 0.002, "d": 0.6, "s": 0.6, "r": 0.1, "mode": 2, "glide": 0.07, "drive": 0.35, "drift": 0, "volume": -6],
        "Digi Bell": ["osc1": 0, "osc2": 0, "semi2": 19, "fine2": 0, "mix": 0, "fm": 0.35, "cutoff": 12000, "fenv": 0, "a": 0.001, "d": 1.2,
                      "s": 0, "r": 0.8, "drift": 0, "volume": -10],
        "Laser Zap": ["osc1": 3, "osc2": 2, "mix": 0.3, "cutoff": 8000, "fenv": 0, "penv": 36, "pdecay": 0.12, "a": 0.001, "d": 0.25, "s": 0, "r": 0.1, "volume": -8],
        "Impact Boom": ["osc1": 0, "osc2": 0, "mix": 0, "noise": 0.15, "cutoff": 1500, "fenv": 0.3, "fd": 0.2, "fs": 0, "keytrack": 0, "penv": 24, "pdecay": 0.25, "a": 0.001, "d": 2.5, "s": 0, "r": 1, "drive": 0.4, "volume": -11],
    ]

    /// Effects a preset puts on its layer when you add it, so it sounds finished out of the box
    /// (Ableton's presets do the same with audio effect racks). They're ordinary layer effects you can tweak or delete.
    public static func effects(for name: String) -> [Effect] {
        if !isBuiltIn(name), let mine = UserInstruments.named(baseName(name)) {
            return mine.effects.map { var e = $0; e.id = UUID(); return e }
        }
        return presetEffects(name).map { e in
            // Fill in every parameter, like an effect dragged in from the browser.
            var full = EffectRegistry.descriptor(e.kind)?.makeEffect() ?? e
            for (k, v) in e.params { full.params[k] = v }
            return full
        }
    }

    static func presetEffects(_ name: String) -> [Effect] {
        let pump = Effect(kind: "pump", params: ["rate": 2, "depth": 0.8])
        let wide = Effect(kind: "chorus", params: ["depth": 0.4, "mix": 0.3])
        let room = Effect(kind: "reverb", params: ["size": 0.5, "mix": 0.15, "lowcut": 300])
        let hall = Effect(kind: "reverb", params: ["size": 0.8, "mix": 0.28, "lowcut": 300])
        let echo = Effect(kind: "delay", params: ["time": 6, "feedback": 0.35, "mix": 0.18, "lowcut": 400])
        let grit = Effect(kind: "saturator", params: ["drive": 8, "type": 0, "mix": 0.6])
        let glue = Effect(kind: "compressor", params: ["threshold": -20, "ratio": 4, "attack": 15, "release": 120])
        switch name {
        // Existing presets that benefit from some space.
        case "Supersaw", "Stab": return [wide, room]
        case "Pad", "Warm Pad", "Dark Pad", "Glass Pad", "Strings": return [wide, hall]
        case "Pluck", "Kalimba", "Marimba", "Bell", "Music Box", "Electric Piano": return [echo, room]
        case "Lead", "Vibrato Lead", "Whistle", "Brass": return [echo, room]
        case "Reese Bass", "Wobble Bass", "Acid": return [grit]
        // Future Bass
        case "Future Chords": return [pump, wide, hall]
        case "Wub Chords": return [wide, room]
        case "Dream Pluck": return [echo, wide, hall]
        case "Shimmer Lead": return [echo, hall]
        case "Vowel Lead": return [wide, room]
        case "Heaven Pad": return [pump, wide, Effect(kind: "reverb", params: ["size": 0.95, "mix": 0.45, "lowcut": 350])]
        // Dubstep & Bass House
        case "Growl Bass", "Riddim Bass", "Neuro Reese": return [grit, glue]
        case "Bass House": return [Effect(kind: "saturator", params: ["drive": 10, "type": 2, "mix": 0.7]), Effect(kind: "pump", params: ["rate": 2, "depth": 0.6])]
        case "Screech Lead": return [grit, room]
        case "Distorted 808": return [Effect(kind: "saturator", params: ["drive": 12, "type": 2, "tone": 6000, "mix": 0.7])]
        case "Hoover": return [Effect(kind: "chorus", params: ["depth": 0.7, "mix": 0.5]), room]
        // Hyperpop
        case "Hyper Lead": return [Effect(kind: "bitcrusher", params: ["bits": 10, "downsample": 2, "mix": 0.35]), echo, room]
        case "Glitter Pluck": return [Effect(kind: "delay", params: ["time": 2, "feedback": 0.35, "mix": 0.25, "lowcut": 500]), hall]
        case "Hyper Saw": return [Effect(kind: "saturator", params: ["drive": 6, "mix": 0.5]), wide, Effect(kind: "pump", params: ["rate": 2, "depth": 0.6])]
        case "Bubble Bass": return [Effect(kind: "saturator", params: ["drive": 6, "type": 2, "mix": 0.5])]
        case "Digi Bell": return [echo, hall]
        default: return []
        }
    }

    public static func params(for name: String) -> [String: Double] {
        var p = SynthParams.defs.defaults()
        if overrides[name] == nil, let mine = UserInstruments.named(baseName(name)) {
            for (k, v) in mine.params { p[k] = v }
            return p
        }
        for (k, v) in overrides[name] ?? [:] { p[k] = v }
        return p
    }
}

/// Linear-attack, exponential decay/release envelope.
struct ADSR {
    enum Stage { case idle, attack, decay, sustain, release }
    var stage = Stage.idle
    var level: Float = 0
    var aInc: Float = 0, dCoef: Float = 0, rCoef: Float = 0, sus: Float = 1

    mutating func configure(a: Double, d: Double, s: Double, r: Double, sr: Double) {
        aInc = Float(1 / max(1, a * sr))
        dCoef = Float(exp(-4.6 / max(1, d * sr)))
        rCoef = Float(exp(-4.6 / max(1, r * sr)))
        sus = Float(s)
    }

    mutating func gate(on: Bool, retrigger: Bool = true) {
        if on {
            if retrigger || stage == .idle || stage == .release { stage = .attack }
        } else if stage != .idle {
            stage = .release
        }
    }

    @inline(__always) mutating func next() -> Float {
        switch stage {
        case .idle: return 0
        case .attack:
            level += aInc
            if level >= 1 { level = 1; stage = .decay }
        case .decay:
            level = sus + (level - sus) * dCoef
            if abs(level - sus) < 0.0005 { level = sus; stage = .sustain }
        case .sustain:
            level = sus
        case .release:
            level *= rCoef
            if level < 0.00005 { level = 0; stage = .idle }
        }
        return level
    }
}

@inline(__always) func polyBlep(_ t: Double, _ dt: Double) -> Double {
    if t < dt { let x = t / dt; return x + x - x * x - 1 }
    if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
    return 0
}

@inline(__always) func oscillator(_ wave: Int, _ phase: Double, _ dt: Double) -> Double {
    switch wave {
    case 0: return sin(2 * .pi * phase)
    case 1: return phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase
    case 2: return 2 * phase - 1 - polyBlep(phase, dt)
    default:
        var v = phase < 0.5 ? 1.0 : -1.0
        v += polyBlep(phase, dt)
        var t2 = phase + 0.5; if t2 >= 1 { t2 -= 1 }
        v -= polyBlep(t2, dt)
        return v
    }
}

struct SynthVoice {
    var note = -1
    var velocity: Float = 0
    var order = 0
    var freq = 440.0, targetFreq = 440.0
    var phSub = 0.0
    var amp = ADSR(), fenv = ADSR()
    var pitchEnv: Float = 0
    var fL = SVF(), fR = SVF()
    /// Second stage for the 24 dB filter.
    var fL2 = SVF(), fR2 = SVF()
    /// Previous drive input per channel, for the anti-aliased saturator.
    var dzL: Float = 0, dzR: Float = 0
    /// DC blocker state after the drive.
    var dcxL: Float = 0, dcyL: Float = 0, dcxR: Float = 0, dcyR: Float = 0
    /// Stolen to make room for a new note: release over a few milliseconds.
    var quickFade = false
    /// Slow random pitch wander, in semitones, like an analog oscillator.
    var drift = 0.0, driftTarget = 0.0
    var held = false

    var isActive: Bool { amp.stage != .idle }
}

/// Polyphonic subtractive synth. Owned by one pattern instance (or the preview channel).
public final class Synth {
    /// 16 notes at once, plus spare slots so a stolen note can fade out instead of being cut.
    var voices = [SynthVoice](repeating: SynthVoice(), count: Synth.polyphony + 8)
    static let polyphony = 16
    var counter = 0
    var noiseSeed: UInt32 = 22222
    var lastNote = -1
    var heldStack: [Int] = []
    var lfoPhase = 0.0
    var lfoZ: Float = 0
    /// This block's LFO values; render() splits longer requests so it never overflows.
    var lfoBlock = [Float](repeating: 0, count: Synth.maxBlock)
    static let maxBlock = 2048
    let sr: Double
    /// Oscillator phases live outside the voice structs so copying a voice never allocates.
    let ph1: UnsafeMutablePointer<Double>
    let ph2: UnsafeMutablePointer<Double>
    let ph3: UnsafeMutablePointer<Double>
    let ph4: UnsafeMutablePointer<Double>
    static let maxUnison = 7
    static let unisonCounts = [1, 3, 5, 7]

    public init(sampleRate: Double) {
        sr = sampleRate
        heldStack.reserveCapacity(64)
        let n = voices.count * Synth.maxUnison
        ph1 = .allocate(capacity: n)
        ph2 = .allocate(capacity: n)
        ph3 = .allocate(capacity: n)
        ph4 = .allocate(capacity: n)
        // Spread start phases so unison voices don't start in sync, but seeded, so every bounce
        // of a song sounds identical.
        var seed: UInt32 = 0x5EED
        func rnd() -> Double { seed = seed &* 1664525 &+ 1013904223; return Double(seed) / 4294967296 }
        for i in 0..<n {
            ph1[i] = rnd()
            ph2[i] = rnd()
            ph3[i] = rnd()
            ph4[i] = rnd()
        }
    }

    deinit {
        ph1.deallocate()
        ph2.deallocate()
        ph3.deallocate()
        ph4.deallocate()
    }

    static func freq(_ note: Int) -> Double { 440 * pow(2, Double(note - 69) / 12) }

    public func noteOn(_ note: Int, velocity: Float, params p: [Double]) {
        let mode = Int(p[SynthParams.mode])
        counter += 1
        heldStack.removeAll { $0 == note }
        heldStack.append(note)
        if mode > 0 {
            // Mono / legato: one voice, glide from the previous pitch.
            let legato = mode == 2 && voices[0].held && voices[0].isActive
            var v = voices[0]
            let wasActive = v.isActive
            v.note = note
            // Legato keeps the running note's level; jumping it mid-note clicks.
            if !legato { v.velocity = velocity }
            v.targetFreq = Synth.freq(note)
            if !wasActive || p[SynthParams.glide] <= 0 { v.freq = v.targetFreq }
            v.held = true
            v.order = counter
            configure(&v, p)
            if !legato {
                v.amp.gate(on: true, retrigger: true)
                v.fenv.gate(on: true, retrigger: true)
                v.pitchEnv = 1
            }
            voices[0] = v
            for i in 1..<voices.count where voices[i].isActive { voices[i].amp.gate(on: false) }
            lastNote = note
            return
        }
        // Poly: up to 16 notes. Past that, the oldest note (released ones first) fades out over a few
        // milliseconds in its own slot while the new note starts fresh in a spare one. Switching a
        // sounding voice straight to a new pitch clicked, which long pads and big chords hit constantly.
        // Plain loops: this runs on the audio thread, so nothing that allocates.
        var sounding = 0, victim = -1, bestScore = Int.max
        for i in voices.indices where voices[i].isActive && !voices[i].quickFade {
            sounding += 1
            let score = voices[i].order - (voices[i].held ? 0 : 1_000_000)
            if score < bestScore { bestScore = score; victim = i }
        }
        if sounding >= Synth.polyphony, victim >= 0 {
            voices[victim].held = false
            voices[victim].quickFade = true
            voices[victim].amp.gate(on: false)
            voices[victim].fenv.gate(on: false)
        } else {
            victim = -1
        }
        // A free slot, else the quietest fading one, else (never expected) the victim itself.
        var idx = -1
        for i in voices.indices where !voices[i].isActive { idx = i; break }
        if idx < 0 {
            var quietest: Float = .infinity
            for i in voices.indices where voices[i].quickFade && i != victim && voices[i].amp.level < quietest {
                quietest = voices[i].amp.level; idx = i
            }
        }
        if idx < 0 { idx = max(victim, 0) }
        var v = voices[idx]
        v.quickFade = false
        v.note = note
        v.velocity = velocity
        v.freq = Synth.freq(note)
        v.targetFreq = v.freq
        v.order = counter
        v.held = true
        v.pitchEnv = 1
        configure(&v, p)
        v.amp.gate(on: true)
        v.fenv.gate(on: true)
        voices[idx] = v
        lastNote = note
    }

    public func noteOff(_ note: Int, params p: [Double]) {
        heldStack.removeAll { $0 == note }
        let mode = Int(p[SynthParams.mode])
        if mode > 0 {
            if voices[0].note == note {
                if let prev = heldStack.last {
                    // Return to the note still held underneath (classic mono behaviour).
                    voices[0].note = prev
                    voices[0].targetFreq = Synth.freq(prev)
                    if p[SynthParams.glide] <= 0 { voices[0].freq = voices[0].targetFreq }
                } else {
                    voices[0].held = false
                    voices[0].amp.gate(on: false)
                    voices[0].fenv.gate(on: false)
                }
            }
            return
        }
        for i in voices.indices where voices[i].note == note && voices[i].held {
            voices[i].held = false
            voices[i].amp.gate(on: false)
            voices[i].fenv.gate(on: false)
        }
    }

    public func allNotesOff() {
        heldStack.removeAll(keepingCapacity: true)
        for i in voices.indices where voices[i].isActive {
            voices[i].held = false
            voices[i].amp.gate(on: false)
            voices[i].fenv.gate(on: false)
        }
    }

    public func reset() {
        heldStack.removeAll(keepingCapacity: true)
        for i in voices.indices {
            voices[i].amp = ADSR()
            voices[i].fenv = ADSR()
            voices[i].held = false
            voices[i].quickFade = false
            voices[i].fL.reset(); voices[i].fR.reset()
            voices[i].fL2.reset(); voices[i].fR2.reset()
            voices[i].dzL = 0; voices[i].dzR = 0
            voices[i].dcxL = 0; voices[i].dcyL = 0; voices[i].dcxR = 0; voices[i].dcyR = 0
        }
    }

    public var isSilent: Bool { !voices.contains { $0.isActive } }

    private func configure(_ v: inout SynthVoice, _ p: [Double]) {
        v.amp.configure(a: p[SynthParams.a], d: p[SynthParams.d], s: p[SynthParams.s], r: p[SynthParams.r], sr: sr)
        v.fenv.configure(a: p[SynthParams.fa], d: p[SynthParams.fd], s: p[SynthParams.fs], r: p[SynthParams.fr], sr: sr)
    }

    @inline(__always) private func noise() -> Double {
        noiseSeed = noiseSeed &* 1664525 &+ 1013904223
        return Double(Int32(bitPattern: noiseSeed)) / Double(Int32.max)
    }

    /// Adds output into the given pointers.
    /// - Parameter beat: song position of the first frame. Tempo-synced LFOs lock to it,
    ///   so a 1/4 wobble always dips on the beat. Without it the LFO runs freely.
    public func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, frames: Int, params p: [Double],
                       bpm: Double = 120, beat: Double? = nil) {
        if isSilent { return }
        if frames > Synth.maxBlock {
            let bpf = bpm / 60 / sr
            var f = 0
            while f < frames {
                let n = min(Synth.maxBlock, frames - f)
                render(outL + f, outR + f, frames: n, params: p, bpm: bpm, beat: beat.map { $0 + Double(f) * bpf })
                f += n
            }
            return
        }
        let w1 = Int(p[SynthParams.osc1]), w2 = Int(p[SynthParams.osc2])
        let w3 = Int(p[SynthParams.osc3]), w4 = Int(p[SynthParams.osc4])
        let ratio1 = pow(2, p[SynthParams.semi1] / 12)
        let ratio2 = pow(2, (p[SynthParams.semi1] + p[SynthParams.semi2] + p[SynthParams.fine2] / 100) / 12)
        let ratio3 = pow(2, (p[SynthParams.semi1] + p[SynthParams.semi3] + p[SynthParams.fine3] / 100) / 12)
        let ratio4 = pow(2, (p[SynthParams.semi1] + p[SynthParams.semi4] + p[SynthParams.fine4] / 100) / 12)
        // Osc 1 and 2 crossfade with Osc Mix (0.5 each at the middle); osc 3 and 4 add 0.5 at full level.
        let mix0 = p[SynthParams.mix]
        let g1 = p[SynthParams.lvl1] * (1 - mix0)
        let g2 = p[SynthParams.on2] > 0.5 ? p[SynthParams.lvl2] * mix0 : 0
        let g3 = p[SynthParams.on3] > 0.5 ? p[SynthParams.lvl3] * 0.5 : 0
        let g4 = p[SynthParams.on4] > 0.5 ? p[SynthParams.lvl4] * 0.5 : 0
        let sub = p[SynthParams.sub], nz = p[SynthParams.noise]
        let uniCount = Synth.unisonCounts[min(3, max(0, Int(p[SynthParams.unison])))]
        let spread = p[SynthParams.spread]
        let cutoff = p[SynthParams.cutoff], res = Float(p[SynthParams.res])
        let fenvAmt = p[SynthParams.fenv], keytrack = p[SynthParams.keytrack]
        let ftype = Int(p[SynthParams.ftype])
        let fm = p[SynthParams.fm], lfoFM = p[SynthParams.lfoFM]
        let driftAmt = p[SynthParams.drift]
        let penv = p[SynthParams.penv]
        let pdec = Float(exp(-4.6 / max(1, p[SynthParams.pdecay] * sr)))
        let glideCoef = p[SynthParams.glide] > 0 ? exp(-4.6 / (p[SynthParams.glide] * sr)) : 0
        let drive = p[SynthParams.drive]
        let driveGain = Float(1 + drive * 8), driveComp = 1 / Float(1 + drive * 2.5)
        let vol = Float(dbToGain(p[SynthParams.volume]))
        let srF = Float(sr)
        let dcR = Float(exp(-2 * Double.pi * 10 / sr))
        let quickFadeCoef = Float(exp(-4.6 / (0.006 * sr)))
        // One LFO shared by every voice, so chords wobble together.
        let syncBeats = SynthParams.lfoSyncBeats[min(SynthParams.lfoSyncBeats.count - 1, max(0, Int(p[SynthParams.lfoSync])))]
        let lfoHz = syncBeats > 0 ? bpm / 60 / syncBeats : p[SynthParams.lfoRate]
        let lfoInc = lfoHz / sr
        let lfoShape = Int(p[SynthParams.lfoShape])
        let lfoCut = p[SynthParams.lfoCut], lfoPitch = p[SynthParams.lfoPitch], lfoAmp = Float(p[SynthParams.lfoAmp])
        let lfoOn = lfoCut > 0 || lfoPitch > 0 || lfoAmp > 0 || lfoFM > 0
        // Synced and given a song position: lock the phase to the beat grid.
        if let beat, syncBeats > 0 {
            let x = beat / syncBeats
            lfoPhase = x - x.rounded(.down)
        }
        let lfoStart = lfoPhase
        defer { lfoPhase = (lfoPhase + Double(frames) * lfoInc).truncatingRemainder(dividingBy: 1) }
        // Precompute this block's LFO (smoothed, so square and random shapes don't click).
        if lfoOn {
            let smooth = Float(exp(-1 / (0.0015 * sr)))
            for i in 0..<frames {
                let x = lfoStart + Double(i) * lfoInc
                let target = Float(Synth.lfoValue(lfoShape, x))
                lfoZ = target + (lfoZ - target) * smooth
                lfoBlock[i] = lfoZ
            }
        }
        // Drift moves toward a new random target a few times a second.
        let driftCoef = exp(-1 / (0.25 * sr / Double(max(1, frames))))
        let uniNorm = 1 / sqrt(Double(uniCount)) * p[SynthParams.oscLevel]
        // Unison detune is constant for the block; precompute instead of calling pow() per sample.
        var detunes = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        var ratios = (1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
        withUnsafeMutableBytes(of: &detunes) { d in
            withUnsafeMutableBytes(of: &ratios) { r in
                let dp = d.bindMemory(to: Double.self), rp = r.bindMemory(to: Double.self)
                for u in 0..<uniCount {
                    dp[u] = uniCount == 1 ? 0 : (Double(u) / Double(uniCount - 1) * 2 - 1)
                    rp[u] = pow(2, dp[u] * spread * 0.6 / 12)
                }
            }
        }
        let detunesArr = detunes, ratiosArr = ratios

        for vi in voices.indices where voices[vi].isActive {
            var v = voices[vi]
            // Refresh envelope rates every block so knob moves affect held notes.
            v.amp.configure(a: p[SynthParams.a], d: p[SynthParams.d], s: p[SynthParams.s], r: p[SynthParams.r], sr: sr)
            v.fenv.configure(a: p[SynthParams.fa], d: p[SynthParams.fd], s: p[SynthParams.fs], r: p[SynthParams.fr], sr: sr)
            if v.quickFade { v.amp.rCoef = quickFadeCoef }
            if driftAmt > 0 {
                if abs(v.drift - v.driftTarget) < 0.01 || noise() > 0.97 { v.driftTarget = noise() * 0.08 }
                v.drift = v.driftTarget + (v.drift - v.driftTarget) * driftCoef
            }
            let driftRatio = driftAmt > 0 ? pow(2, v.drift * driftAmt / 12) : 1
            let velGain = 0.3 + 0.7 * v.velocity
            let base = vi * Synth.maxUnison
            let detunes = TupleIndex(detunesArr), detuneRatios = TupleIndex(ratiosArr)
            for i in 0..<frames {
                if glideCoef > 0 { v.freq = v.targetFreq + (v.freq - v.targetFreq) * glideCoef } else { v.freq = v.targetFreq }
                var f0 = v.freq * driftRatio
                let lfo = lfoOn ? Double(lfoBlock[i]) : 0
                if lfoPitch > 0 { f0 *= pow(2, lfo * lfoPitch * 0.5 / 12) }
                if penv > 0 {
                    f0 *= pow(2, Double(v.pitchEnv) * penv / 12)
                    v.pitchEnv *= pdec
                }
                // A big pitch envelope on a high note can pass the sample rate; keep oscillators sane.
                f0 = min(f0, sr * 0.45)
                // FM: osc 2 bends osc 1's phase. The LFO can push it for talking, growling basses.
                let fmIndex = max(0, fm + lfoFM * (lfo * 0.5 + 0.5)) * 2.5
                var sl = 0.0, sr2 = 0.0
                for u in 0..<uniCount {
                    let det = detunes[u]
                    let fu = f0 * detuneRatios[u]
                    let dt1 = fu * ratio1 / sr, dt2 = fu * ratio2 / sr
                    let k = base + u
                    let o2 = oscillator(w2, ph2[k], dt2)
                    let o1: Double
                    if fmIndex > 0 {
                        var ph = ph1[k] + fmIndex * o2
                        ph -= ph.rounded(.down)
                        o1 = oscillator(w1, ph, dt1)
                    } else {
                        o1 = oscillator(w1, ph1[k], dt1)
                    }
                    // With FM on, osc 2 is the modulator; its level still lets you hear it.
                    var o = o1 * g1 + o2 * g2
                    ph1[k] += dt1; if ph1[k] >= 1 { ph1[k] -= ph1[k].rounded(.down) }
                    ph2[k] += dt2; if ph2[k] >= 1 { ph2[k] -= ph2[k].rounded(.down) }
                    if g3 > 0 {
                        let dt3 = fu * ratio3 / sr
                        o += oscillator(w3, ph3[k], dt3) * g3
                        ph3[k] += dt3; if ph3[k] >= 1 { ph3[k] -= ph3[k].rounded(.down) }
                    }
                    if g4 > 0 {
                        let dt4 = fu * ratio4 / sr
                        o += oscillator(w4, ph4[k], dt4) * g4
                        ph4[k] += dt4; if ph4[k] >= 1 { ph4[k] -= ph4[k].rounded(.down) }
                    }
                    let pan = uniCount == 1 ? 0.5 : 0.5 + det * 0.45
                    sl += o * (1 - pan) * 2
                    sr2 += o * pan * 2
                }
                sl *= uniNorm; sr2 *= uniNorm
                if sub > 0 {
                    let s = sin(2 * .pi * v.phSub) * sub * p[SynthParams.oscLevel]
                    v.phSub += f0 * 0.5 / sr; if v.phSub >= 1 { v.phSub -= 1 }
                    sl += s; sr2 += s
                }
                if nz > 0 { let n = noise() * nz * 0.5; sl += n; sr2 += n }

                let fe = Double(v.fenv.next())
                if i & 7 == 0 {
                    let kt = pow(f0 / 261.6, keytrack)
                    let c = min(cutoff * kt * pow(2, fenvAmt * fe * 7 + lfo * lfoCut * 4), sr * 0.45)
                    if ftype == 1 {
                        // Two stages: a Butterworth-ish first stage, resonance on the second.
                        v.fL.set(cutoff: Float(c), resonance: 0.08, sampleRate: srF)
                        v.fL2.set(cutoff: Float(c), resonance: res, sampleRate: srF)
                        v.fR2.copyCoefficients(v.fL2)
                    } else {
                        v.fL.set(cutoff: Float(c), resonance: res, sampleRate: srF)
                    }
                    v.fR.copyCoefficients(v.fL)
                }
                var l: Float, r: Float
                switch ftype {
                case 1:
                    l = v.fL2.process(v.fL.process(Float(sl)).0).0
                    r = v.fR2.process(v.fR.process(Float(sr2)).0).0
                case 2:
                    // Band-pass scaled by k keeps the peak near unity at any resonance.
                    l = v.fL.process(Float(sl)).1 * v.fL.k
                    r = v.fR.process(Float(sr2)).1 * v.fR.k
                case 3:
                    l = v.fL.process(Float(sl)).2
                    r = v.fR.process(Float(sr2)).2
                default:
                    l = v.fL.process(Float(sl)).0
                    r = v.fR.process(Float(sr2)).0
                }
                if drive > 0 {
                    l = adaaTanh(l * driveGain, &v.dzL) * driveComp * 1.5
                    r = adaaTanh(r * driveGain, &v.dzR) * driveComp * 1.5
                    // Drive on a lopsided wave adds DC offset; a 10 Hz high-pass removes it.
                    let yl = l - v.dcxL + dcR * v.dcyL; v.dcxL = l; v.dcyL = yl; l = yl
                    let yr = r - v.dcxR + dcR * v.dcyR; v.dcxR = r; v.dcyR = yr; r = yr
                }
                var a = v.amp.next() * velGain * vol
                if lfoAmp > 0 { a *= 1 - lfoAmp * Float(0.5 - 0.5 * lfo) }
                outL[i] += l * a
                outR[i] += r * a
                if v.amp.stage == .idle { break }
            }
            voices[vi] = v
        }
    }

    /// LFO shapes in -1...1 for a phase `x` (whole cycles; the fraction is the position).
    static func lfoValue(_ shape: Int, _ x: Double) -> Double {
        let ph = x - x.rounded(.down)
        switch shape {
        case 1: return ph < 0.5 ? 4 * ph - 1 : 3 - 4 * ph
        case 2: return 1 - 2 * ph
        case 3: return 2 * ph - 1
        case 4: return ph < 0.5 ? 1 : -1
        case 5:
            // Sample and hold: one random value per cycle, the same every time the song plays.
            var h = UInt32(truncatingIfNeeded: Int64(x.rounded(.down)) &* 2654435761)
            h ^= h >> 15; h = h &* 2246822519; h ^= h >> 13
            return Double(h) / Double(UInt32.max) * 2 - 1
        default: return sin(2 * .pi * ph)
        }
    }
}

/// tanh with first-order antiderivative anti-aliasing: much less harsh fizz when driven hard.
@inline(__always) func adaaTanh(_ x: Float, _ prev: inout Float) -> Float {
    let x1 = prev
    prev = x
    let d = x - x1
    if abs(d) < 1e-4 { return tanhf(0.5 * (x + x1)) }
    return (logCosh(x) - logCosh(x1)) / d
}

@inline(__always) func logCosh(_ x: Float) -> Float {
    let a = abs(x)
    return a + log1pf(expf(-2 * a)) - 0.6931472
}

/// Allocation-free indexable view over a 7-element tuple.
struct TupleIndex {
    let t: (Double, Double, Double, Double, Double, Double, Double)
    init(_ t: (Double, Double, Double, Double, Double, Double, Double)) { self.t = t }
    @inline(__always) subscript(i: Int) -> Double {
        switch i {
        case 0: return t.0
        case 1: return t.1
        case 2: return t.2
        case 3: return t.3
        case 4: return t.4
        case 5: return t.5
        default: return t.6
        }
    }
}
