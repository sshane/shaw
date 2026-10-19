import Foundation

/// A real instrument that comes with Shaw, recorded a few notes apart and played by the sampler.
public struct RecordedInstrument {
    public let name: String
    /// Its folder in Resources/Sounds/Instruments.
    public let folder: String
    public let summary: String
    /// How the Browser shows it off: chords, an arpeggio, or a melody.
    public let style: Style
    /// Sampler settings that suit it (`SamplerParams`).
    let settings: [String: Double]

    public enum Style { case chords, arpeggio, melody, bassline }

    public var path: String { SampleLibrary.bundledPrefix + "Instruments/" + folder }
}

/// Public domain (CC0) recordings, so Shaw can ship them: the Versilian Community Sample Library by
/// Versilian Studios, and Karoryfer's Growlybass for the bass guitar. See Resources/Sounds/CREDITS.txt.
public enum RecordedInstruments {
    public static let category = "Real Instruments"

    // Struck and plucked instruments ring out on their own (One-Shot). Pianos, the organ, and the
    // sax stop when the note ends, after a release like a damper or a breath.
    private static let held: [String: Double] = ["playmode": 0]
    private static let rings: [String: Double] = ["playmode": 1]

    public static let all: [RecordedInstrument] = [
        RecordedInstrument(name: "Grand Piano", folder: "Grand Piano", summary: "A Kawai concert grand",
                           style: .chords, settings: held.merging(["r": 0.45]) { $1 }),
        RecordedInstrument(name: "Upright Piano", folder: "Upright Piano", summary: "A warm old upright, good for lo-fi",
                           style: .chords, settings: held.merging(["r": 0.4]) { $1 }),
        RecordedInstrument(name: "FM Piano", folder: "FM Piano", summary: "A Yamaha TX81Z electric piano",
                           style: .chords, settings: held.merging(["r": 0.35]) { $1 }),
        RecordedInstrument(name: "Vibraphone", folder: "Vibraphone", summary: "Soft metal bars with a long ring",
                           style: .arpeggio, settings: held.merging(["r": 1.2]) { $1 }),
        RecordedInstrument(name: "Concert Marimba", folder: "Marimba", summary: "Warm wooden bars",
                           style: .arpeggio, settings: rings),
        RecordedInstrument(name: "Kenyan Kalimba", folder: "Kalimba", summary: "A plucked thumb piano",
                           style: .arpeggio, settings: rings),
        // Every glockenspiel note is a sharp spike, so it sits lower to leave room for chords.
        RecordedInstrument(name: "Glockenspiel", folder: "Glockenspiel", summary: "Bright, bell-like bars",
                           style: .arpeggio, settings: rings.merging(["volume": -6]) { $1 }),
        RecordedInstrument(name: "Harp", folder: "Harp", summary: "A plucked concert harp",
                           style: .arpeggio, settings: rings),
        RecordedInstrument(name: "Tenor Sax", folder: "Tenor Sax", summary: "A breathy jazz tenor saxophone",
                           style: .melody, settings: held.merging(["r": 0.12]) { $1 }),
        RecordedInstrument(name: "Bass Guitar", folder: "Bass Guitar", summary: "A Squier Jazz Bass, played with fingers",
                           style: .bassline, settings: held.merging(["r": 0.12]) { $1 }),
        RecordedInstrument(name: "Pipe Organ", folder: "Pipe Organ", summary: "A church organ",
                           style: .chords, settings: held.merging(["r": 0.25]) { $1 }),
    ]

    public static let names = all.map(\.name)

    public static func named(_ name: String) -> RecordedInstrument? { all.first { $0.name == name } }

    public static func instrument(_ r: RecordedInstrument) -> Instrument {
        var p = SamplerParams.defs.defaults()
        for (k, v) in r.settings { p[k] = v }
        return Instrument(preset: r.name, params: p, sample: r.path)
    }
}
