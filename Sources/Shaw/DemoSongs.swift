import ShawCore

extension DemoProject {
    /// A synth pattern. `gain` turns the preset's volume up or down (dB) so parts sit together;
    /// `tweak` overrides any synth parameter (each pattern carries its own copy of the sound).
    static func synthPattern(_ name: String, _ color: Int, _ preset: String, length: Double = 16, gain: Double = 0,
                             tweak: [String: Double] = [:], _ notes: [Note]) -> Asset {
        var inst = Instrument.preset(preset)
        inst.params["volume"] = (inst.params["volume"] ?? -8) + gain
        for (k, v) in tweak { inst.params[k] = v }
        return Asset(name: name, colorIndex: color, content: .notes(NotePattern(length: length, notes: notes, instrument: inst)))
    }

    static func filed(_ p: inout Project, sections: [Asset], patterns: [Asset], beats: [Asset], fx: [Asset]) {
        let s = Folder(name: "Sections"), pa = Folder(name: "Patterns"), b = Folder(name: "Beats"), f = Folder(name: "FX")
        p.folders = [s, pa, b, f]
        func put(_ a: Asset, _ folder: Folder) -> Asset { var a = a; a.folderID = folder.id; return a }
        p.assets += sections.map { put($0, s) } + patterns.map { put($0, pa) } + beats.map { put($0, b) } + fx.map { put($0, f) }
        p.migrateDrumPatterns()
    }

    /// Drum pattern written as hits: (sound, beat, velocity). Exact timing, ghost notes, and rolls.
    static func kitPattern(_ name: String, _ color: Int, _ kit: String, length: Double, _ hits: [(String, Double, Double)]) -> Asset {
        let notes = hits.map { Note(pitch: DrumKits.pitch(of: $0.0), start: $0.1, length: 0.25, velocity: $0.2) }
        return Asset(name: name, colorIndex: color, content: .notes(NotePattern(length: length, notes: notes, instrument: .kit(kit))))
    }
}
