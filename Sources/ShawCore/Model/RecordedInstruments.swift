import Foundation

/// A real instrument that comes with Shaw, recorded a few notes apart and played by the sampler.
public struct RecordedInstrument {
    public let name: String
    /// Its folder in Resources/Sounds/Instruments.
    public let folder: String
    public let summary: String
    /// How the Browser shows it off: chords, an arpeggio, a melody, or rhythmic stabs.
    public let style: Style
    /// Sampler settings that suit it (`SamplerParams`).
    let settings: [String: Double]

    public enum Style { case chords, arpeggio, melody, bassline, strum, stabs }

    public var path: String { SampleLibrary.bundledPrefix + "Instruments/" + folder }
}

/// Public domain (CC0) recordings, so Shaw can ship them: the Versilian Community Sample Library and
/// VSCO 2 Community Edition by Versilian Studios, Karoryfer Samples for the bass and the guitars, and singers on Freesound for the
/// vocals. See Resources/Sounds/CREDITS.txt.
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
        // Cellos low, violas in the middle, and violins on top, so a chord sounds like a whole section.
        RecordedInstrument(name: "String Section", folder: "String Section", summary: "Cellos, violas, and violins with vibrato, for disco string pads and swells",
                           style: .chords, settings: held.merging(["r": 0.6]) { $1 }),
        // Short bowed and blown notes play out whole, however short the note, like the stab they are.
        RecordedInstrument(name: "String Stabs", folder: "String Stabs", summary: "Short, bouncing spiccato strings, for disco stabs and fast runs",
                           style: .stabs, settings: rings),
        RecordedInstrument(name: "Brass Stabs", folder: "Brass Stabs", summary: "Trumpets and trombones playing short, punchy hits, for disco and funk horn stabs",
                           style: .stabs, settings: rings),
        RecordedInstrument(name: "Tenor Sax", folder: "Tenor Sax", summary: "A breathy jazz tenor saxophone",
                           style: .melody, settings: held.merging(["r": 0.12]) { $1 }),
        RecordedInstrument(name: "Bass Guitar", folder: "Bass Guitar", summary: "A Squier Jazz Bass, played with fingers",
                           style: .bassline, settings: held.merging(["r": 0.12]) { $1 }),
        // Guitars stop when the note ends, like a hand muting the strings.
        RecordedInstrument(name: "Jangle Guitar", folder: "Jangle Guitar", summary: "A Gretsch hollow-body electric, bright and jangly",
                           style: .strum, settings: held.merging(["r": 0.25]) { $1 }),
        RecordedInstrument(name: "Hollow-Body Guitar", folder: "Hollow-Body Guitar", summary: "A Höfner Club hollow-body, warm and round",
                           style: .strum, settings: held.merging(["r": 0.25]) { $1 }),
        RecordedInstrument(name: "Clean Electric Guitar", folder: "Clean Electric Guitar", summary: "An Epiphone solid-body, recorded clean with no amp",
                           style: .strum, settings: held.merging(["r": 0.25]) { $1 }),
        RecordedInstrument(name: "Acoustic Archtop", folder: "Acoustic Archtop", summary: "An archtop guitar through a microphone, close to an acoustic",
                           style: .strum, settings: held.merging(["r": 0.3]) { $1 }),
        RecordedInstrument(name: "Jazz Guitar", folder: "Jazz Guitar", summary: "The same archtop through its pickup, warm and round",
                           style: .strum, settings: held.merging(["r": 0.3]) { $1 }),
        RecordedInstrument(name: "Pipe Organ", folder: "Pipe Organ", summary: "A church organ",
                           style: .chords, settings: held.merging(["r": 0.25]) { $1 }),
        // A singer's "ah", "oh", and "eh", cut short for chopped vocal hooks. Her takes are loud, so
        // the voices start 8 dB down, where chords of them don't clip.
        RecordedInstrument(name: "Vocal Chops", folder: "Vocal Chops", summary: "A woman singing \"ah\", \"oh\", and \"eh\", for chopped vocal hooks",
                           style: .melody, settings: held.merging(["r": 0.06, "volume": -8]) { $1 }),
        // One long "ooh", played as chords: it fades in and lingers like a choir.
        RecordedInstrument(name: "Ooh Pad", folder: "Ooh Pad", summary: "A woman singing \"ooh\", for soft vocal chords",
                           style: .chords, settings: held.merging(["a": 0.25, "r": 1.2, "volume": -8]) { $1 }),
    ]

    public static let names = all.map(\.name)

    public static func named(_ name: String) -> RecordedInstrument? { all.first { $0.name == name } }

    public static func instrument(_ r: RecordedInstrument) -> Instrument {
        var p = SamplerParams.defs.defaults()
        for (k, v) in r.settings { p[k] = v }
        return Instrument(preset: r.name, params: p, sample: r.path)
    }
}
