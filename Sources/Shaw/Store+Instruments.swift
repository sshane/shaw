import AppKit
import ShawCore

/// My Instruments: saving an edited sound, building one from scratch, and managing the library.
extension Store {
    // MARK: Library on disk

    static var libraryURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shaw")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Instruments.json")
    }

    static func loadLibrary() -> [CustomInstrument] {
        guard let data = try? Data(contentsOf: libraryURL) else { return [] }
        return (try? JSONDecoder().decode([CustomInstrument].self, from: data)) ?? []
    }

    static func saveLibrary(_ items: [CustomInstrument]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(items) { try? data.write(to: libraryURL, options: .atomic) }
    }

    // MARK: Status

    func instrument(of asset: AssetID) -> Instrument? {
        guard case .notes(let p)? = project.asset(asset)?.content, !p.instrument.isDrumKit else { return nil }
        return p.instrument
    }

    func instrumentStatus(_ asset: AssetID) -> InstrumentStatus? {
        instrument(of: asset).map(SynthPresets.status(of:))
    }

    /// The name to show for a pattern's sound (without the old "*" marker).
    func instrumentName(_ asset: AssetID) -> String {
        guard let i = instrument(of: asset) else { return "" }
        return SynthPresets.baseName(i.preset)
    }

    /// A name nothing else uses: not a built-in preset, not one of yours.
    func uniqueInstrumentName(_ base: String, excluding: UUID? = nil) -> String {
        func taken(_ n: String) -> Bool {
            SynthPresets.isBuiltIn(n) || customInstruments.contains { $0.name == n && $0.id != excluding }
        }
        if !taken(base) { return base }
        var i = 2
        while taken("\(base) \(i)") { i += 1 }
        return "\(base) \(i)"
    }

    // MARK: Saving

    /// Save the pattern's current sound to My Instruments as a new instrument, and switch the pattern to it.
    /// Asks for a name (prefilled with "Strings copy"); `name` skips the prompt.
    @discardableResult
    func saveInstrumentAsNew(from asset: AssetID, name: String? = nil, includeEffects: Bool? = nil) -> CustomInstrument? {
        guard let inst = instrument(of: asset) else { return nil }
        let old = SynthPresets.baseName(inst.preset)
        let status = SynthPresets.status(of: inst)
        let suggestion = uniqueInstrumentName(status == .unsaved ? old : "\(old) copy")
        let fx = layerEffects(for: asset)
        let chosen: (String, Bool)
        if let name {
            chosen = (name, includeEffects ?? !fx.isEmpty)
        } else if let answer = askInstrumentName(title: "Save to My Instruments", suggestion: suggestion, effects: fx) {
            chosen = answer
        } else {
            return nil
        }
        let finalName = uniqueInstrumentName(chosen.0.trimmingCharacters(in: .whitespaces).isEmpty ? suggestion : chosen.0)
        let basedOn = SynthPresets.isBuiltIn(old) ? old : UserInstruments.named(old)?.basedOn
        let saved = CustomInstrument(name: finalName, params: SynthParams.defs.defaults().merging(inst.params) { $1 },
                                     effects: chosen.1 ? fx.map { var e = $0; e.id = UUID(); return e } : [],
                                     basedOn: basedOn)
        customInstruments.append(saved)
        renameSound(of: asset, from: old, to: finalName)
        return saved
    }

    /// Overwrite one of your instruments with the pattern's current sound.
    func saveInstrument(from asset: AssetID) {
        guard let inst = instrument(of: asset),
              let i = customInstruments.firstIndex(where: { $0.name == SynthPresets.baseName(inst.preset) }) else { return }
        customInstruments[i].params = SynthParams.defs.defaults().merging(inst.params) { $1 }
        // Clear an old "*" marker now that it matches.
        if inst.preset.hasSuffix("*") { edit { $0.updateNotes(asset) { $0.instrument.preset = SynthPresets.baseName(inst.preset) } } }
    }

    /// Back to the saved sound of the preset or instrument the pattern is named after.
    func revertInstrument(_ asset: AssetID) {
        guard let inst = instrument(of: asset) else { return }
        let name = SynthPresets.baseName(inst.preset)
        edit { $0.updateNotes(asset) { $0.instrument = .preset(name) } }
    }

    /// Point the pattern (and the asset and layers named after the old sound) at a new instrument name.
    private func renameSound(of asset: AssetID, from old: String, to new: String) {
        let cid = activeCompID
        let assetName = project.asset(asset)?.name ?? ""
        let renameAsset = Store.baseName(assetName) == old
        let newAssetName = renameAsset ? project.uniqueName(new, excluding: asset) : assetName
        edit { p in
            p.updateNotes(asset) { $0.instrument.preset = new }
            p.updateAsset(asset) { $0.name = newAssetName }
            p.updateComposition(cid) { c in
                for ti in c.tracks.indices where c.tracks[ti].clips.contains(where: { $0.assetID == asset }) && c.tracks[ti].name == old {
                    c.tracks[ti].name = new
                }
            }
        }
    }

    // MARK: Building from scratch

    /// A new layer with a plain sine wave, open in the Instrument Editor.
    func newInstrumentFromScratch() {
        let name = uniqueInstrumentName("New Instrument")
        let bar = Double(project.beatsPerBar)
        let id = newPattern(preset: name, bars: 1)
        edit { $0.updateNotes(id) { $0.instrument = Instrument(preset: name, params: SynthPresets.scratch()) } }
        let at = loopEnabled && hasContentIn(activeCompID) ? loopStart : 0
        let track = addTrack(name: name)
        if let c = addClip(asset: id, at: (at / bar).rounded(.down) * bar, track: track) {
            selectedClips = [c]
            open(asset: id, clip: c)
        }
        openInstrumentEditor(id)
    }

    /// Play the browser phrase with this pattern's current (maybe edited) sound and its layer's effects.
    func auditionPattern(_ asset: AssetID) {
        guard let inst = instrument(of: asset) else { return }
        let (notes, bpm) = Store.phrase(forPreset: SynthPresets.baseName(inst.preset))
        engine.playPhrase(notes, instrument: inst, effects: layerEffects(for: asset), bpm: bpm)
    }

    func openInstrumentEditor(_ asset: AssetID) {
        instrumentEditorAsset = asset
        openEditorRequest += 1
    }

    // MARK: Managing My Instruments

    func renameCustomInstrument(_ id: UUID) {
        guard let i = customInstruments.firstIndex(where: { $0.id == id }) else { return }
        let old = customInstruments[i].name
        guard let (name, _) = askInstrumentName(title: "Rename Instrument", suggestion: old, effects: [], button: "Rename") else { return }
        let new = uniqueInstrumentName(name.trimmingCharacters(in: .whitespaces).isEmpty ? old : name, excluding: id)
        customInstruments[i].name = new
        // Patterns in this project that use it follow the new name.
        edit { p in
            for a in p.assets {
                if case .notes(let pat) = a.content, SynthPresets.baseName(pat.instrument.preset) == old {
                    p.updateNotes(a.id) { $0.instrument.preset = new }
                }
            }
        }
    }

    func duplicateCustomInstrument(_ id: UUID) {
        guard let c = customInstruments.first(where: { $0.id == id }) else { return }
        var copy = c
        copy.id = UUID()
        copy.name = uniqueInstrumentName("\(c.name) copy")
        customInstruments.insert(copy, at: (customInstruments.firstIndex { $0.id == id } ?? customInstruments.count - 1) + 1)
    }

    func deleteCustomInstrument(_ id: UUID) {
        guard let c = customInstruments.first(where: { $0.id == id }) else { return }
        guard headless || confirm("Delete \u{201C}\(c.name)\u{201D}?",
                                  "It's removed from My Instruments. Layers already using it keep their sound.") else { return }
        customInstruments.removeAll { $0.id == id }
    }

    // MARK: Prompt

    /// Name prompt with an optional "include effects" checkbox. Returns nil if cancelled.
    func askInstrumentName(title: String, suggestion: String, effects: [Effect], button: String = "Save") -> (String, Bool)? {
        if headless { return (suggestion, !effects.isEmpty) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Your instruments show up in the Browser under My Instruments, in every project."
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: suggestion)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(field)
        var box: NSButton?
        if !effects.isEmpty {
            let names = effects.compactMap { EffectRegistry.descriptor($0.kind)?.name }
            let b = NSButton(checkboxWithTitle: "Include this layer's effects (\(names.joined(separator: ", ")))", target: nil, action: nil)
            b.state = .on
            stack.addArrangedSubview(b)
            box = b
        }
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: box == nil ? 24 : 52)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (field.stringValue, box?.state == .on)
    }
}
