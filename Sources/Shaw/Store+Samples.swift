import AppKit
import ShawCore

/// One audio file in a sample folder.
struct SampleFile: Identifiable, Equatable {
    let path: String
    /// File name without its extension.
    let name: String
    /// Subfolder inside the folder you added ("Drums / Kicks"), or "" at the top.
    let folder: String
    var id: String { path }
}

/// Your own sounds: the Samples browser, sampler patterns, and drum sounds played from files.
extension Store {
    static let maxSamplesPerFolder = 20_000

    /// Sample folders that come with Shaw (public domain recordings), listed above yours.
    static let builtInSampleFolders = ["Percussion", "Acoustic Kit"].map { SampleLibrary.bundledPrefix + $0 }

    var allSampleFolders: [String] { Store.builtInSampleFolders + sampleFolders }

    /// A folder's name in the Browser.
    static func sampleFolderName(_ folder: String) -> String {
        SampleLibrary.isBundled(folder) ? String(folder.dropFirst(SampleLibrary.bundledPrefix.count)) : URL(fileURLWithPath: folder).lastPathComponent
    }

    // MARK: Sample folders

    func addSampleFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Folder"
        panel.message = "Choose a folder of samples. Shaw lists the audio files inside it, subfolders included."
        if panel.runModal() == .OK { for url in panel.urls { addSampleFolder(url) } }
    }

    func addSampleFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        if !sampleFolders.contains(path) { sampleFolders.append(path) }
        browserTab = .samples
        rescanSamples(path)
    }

    func removeSampleFolder(_ path: String) {
        sampleFolders.removeAll { $0 == path }
        sampleIndex[path] = nil
    }

    /// Scan folders that haven't been scanned yet (the Samples tab calls this when it appears).
    func scanSampleFoldersIfNeeded() {
        for f in allSampleFolders where sampleIndex[f] == nil && !scanningFolders.contains(f) { rescanSamples(f) }
    }

    /// Look for audio files again in one folder (or all of them), off the main thread.
    func rescanSamples(_ path: String? = nil) {
        for folder in path.map({ [$0] }) ?? allSampleFolders where !scanningFolders.contains(folder) {
            scanningFolders.insert(folder)
            DispatchQueue.global(qos: .userInitiated).async {
                var files = Store.scanSampleFolder(SampleLibrary.fileURL(folder))
                // Shaw's own sounds are saved in projects the portable way, so they survive moving the app.
                if SampleLibrary.isBundled(folder) {
                    files = files.map { SampleFile(path: SampleLibrary.portablePath($0.path), name: $0.name, folder: $0.folder) }
                }
                DispatchQueue.main.async {
                    self.scanningFolders.remove(folder)
                    guard self.allSampleFolders.contains(folder) else { return }
                    self.sampleIndex[folder] = files
                }
            }
        }
    }

    /// Every audio file under `root`, sorted by subfolder then name (numbers in natural order).
    static func scanSampleFolder(_ root: URL, limit: Int = maxSamplesPerFolder) -> [SampleFile] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var out: [SampleFile] = []
        for case let url as URL in e where SampleLibrary.isAudioFile(url) {
            let dirParts = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
            let rel = dirParts.starts(with: rootParts) ? Array(dirParts.dropFirst(rootParts.count)) : []
            out.append(SampleFile(path: url.path, name: url.deletingPathExtension().lastPathComponent,
                                  folder: rel.joined(separator: " / ")))
            if out.count >= limit { break }
        }
        return out.sorted { a, b in
            if a.folder != b.folder {
                // Files at the top of the folder come first, then subfolders.
                if a.folder.isEmpty || b.folder.isEmpty { return a.folder.isEmpty }
                return a.folder.localizedStandardCompare(b.folder) == .orderedAscending
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: Listening

    /// Play a file once, as it is (clicking it in the Samples browser).
    func previewSampleFile(_ path: String) {
        samplePreviewToken += 1
        let token = samplePreviewToken
        SampleLibrary.shared.loadForPreview(path) { [weak self] sample in
            guard let self, token == self.samplePreviewToken else { return }
            guard let sample else { NSSound.beep(); return }
            self.engine.previewSample(sample)
        }
    }

    func stopSamplePreview() {
        samplePreviewToken += 1
        engine.stopSamplePreview()
    }

    // MARK: Sampler patterns

    /// A sampler for `path`, or nil (with an alert) if it isn't readable audio.
    func samplerInstrument(_ path: String) -> Instrument? {
        let path = SampleLibrary.portablePath(path)
        guard let ref = try? SampleLibrary.probe(SampleLibrary.fileURL(path)) else {
            showAlert("Couldn't use that file", "Shaw couldn't read \(URL(fileURLWithPath: path).lastPathComponent) as audio.")
            return nil
        }
        _ = SampleLibrary.shared.mipmapped(for: path) // start loading now
        return .sampler(path, duration: ref.duration)
    }

    /// Add a new layer that plays `path` from a sampler pattern, looped and open in the piano roll.
    @discardableResult
    func addSampler(_ path: String, at start: Double? = nil, track: UUID? = nil) -> AssetID? {
        guard let inst = samplerInstrument(path) else { return nil }
        let bar = Double(project.beatsPerBar)
        let pattern = NotePattern(length: bar, instrument: inst)
        let asset = Asset(name: project.uniqueName(inst.preset), colorIndex: nextColor(), content: .notes(pattern))
        edit { $0.assets.append(asset) }
        let at = start ?? (loopEnabled && hasContentIn(activeCompID) ? loopStart : 0)
        let trackID = track ?? addTrack(name: inst.preset)
        if let c = addClip(asset: asset.id, at: (at / bar).rounded(.down) * bar, track: trackID) {
            selectedClips = [c]
            open(asset: asset.id, clip: c)
        }
        return asset.id
    }

    /// Make a pattern play `path` with the sampler, keeping its notes. Drum kits take files per sound instead.
    @discardableResult
    func useSample(_ path: String, forPattern id: AssetID) -> Bool {
        guard case .notes(let pat)? = project.asset(id)?.content, !pat.instrument.isDrumKit else { NSSound.beep(); return false }
        guard var inst = samplerInstrument(path) else { return false }
        if pat.instrument.isSampler {
            // A new file keeps your settings, except where in the old file it started and looped.
            var kept = pat.instrument.params
            for k in ["start", "loopstart", "loopend", "playmode"] { kept[k] = inst.params[k] }
            inst.params = kept
        }
        let ok = setSound(of: id, to: inst)
        if ok && !transport.playing { previewSampleFile(path) }
        return ok
    }

    /// Pick a file for a pattern's sampler (or, for a drum kit, for one of its sounds).
    func chooseSampleFile(for id: AssetID, voice: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Use Sample"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let voice { setKitSample(url.path, voice: voice, pattern: id) } else { useSample(url.path, forPattern: id) }
    }

    /// The file behind an audio asset in the Project panel.
    func audioPath(of asset: AssetID) -> String? {
        if case .audio(let ref)? = project.asset(asset)?.content { return ref.path }
        return nil
    }

    // MARK: Drum sounds from files

    /// Play your own file for one sound of a drum kit (nil goes back to the built-in sound).
    func setKitSample(_ path: String?, voice: String, pattern id: AssetID) {
        guard case .notes(let pat)? = project.asset(id)?.content, pat.instrument.isDrumKit else { NSSound.beep(); return }
        let path = path.map(SampleLibrary.portablePath)
        if let path {
            guard (try? SampleLibrary.probe(SampleLibrary.fileURL(path))) != nil else {
                showAlert("Couldn't use that file", "Shaw couldn't read \(URL(fileURLWithPath: path).lastPathComponent) as audio.")
                return
            }
            _ = SampleLibrary.shared.data(for: path)
        }
        edit { p in
            p.updateNotes(id) { n in
                var files = n.instrument.kitSamples ?? [:]
                files[voice] = path
                n.instrument.kitSamples = files.isEmpty ? nil : files
            }
        }
        guard !transport.playing else { return }
        if let path { previewSampleFile(path) } else {
            engine.previewDrum(kit: pat.instrument.kit ?? DrumKits.defaultKit, sound: voice)
        }
    }

    /// Fill drum sounds with files, starting at `voice` and moving down the rows (several files dropped at once).
    func setKitSamples(_ paths: [String], startingAt voice: String, pattern id: AssetID) {
        guard let first = DrumKits.voices.firstIndex(where: { $0.id == voice }) else { return }
        // Rows are drawn highest pitch first, so "down" is toward the kick.
        for (i, path) in paths.enumerated() where first - i >= 0 {
            setKitSample(path, voice: DrumKits.voices[first - i].id, pattern: id)
        }
    }
}
