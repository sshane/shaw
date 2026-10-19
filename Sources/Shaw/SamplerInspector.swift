import ShawCore
import SwiftUI

/// Effect Controls for a sampler pattern: the file, a small waveform with its start marker,
/// the main controls, and the rest behind "Show all".
struct SamplerInspector: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let asset: Asset
    let pattern: NotePattern
    /// Shown inside a clip or slot inspector, with a smaller header.
    var compact = false
    @State private var showAll = false

    static let groups: [(String, [String])] = [
        ("Playback", ["playmode", "root", "fine", "start"]),
        ("Loop", ["loop", "loopstart", "loopend"]),
        ("Envelope", ["a", "d", "s", "r"]),
        ("Filter", ["cutoff", "resonance"]),
        ("Output", ["volume"]),
    ]

    var body: some View {
        let inst = pattern.instrument
        let file = inst.sample ?? ""
        let missing = !SampleLibrary.exists(file)
        // One of the real instruments that come with Shaw (a folder of recorded notes, not one file).
        let recorded = RecordedInstruments.named(inst.preset)?.path == file
        let value: (String) -> Double = { id in
            let def = SamplerParams.defs.first { $0.id == id }
            return def.map { $0.clamp(inst.params[id] ?? $0.defaultValue) } ?? 0
        }
        let kind = recorded ? "Real Instrument" : "Sampler"
        if compact {
            SectionHeader(title: "Sound · \(kind)")
        } else {
            InspectorTitle(icon: recorded ? "music.note" : "waveform", kind: "Pattern · \(kind)", name: asset.name,
                           color: Theme.label(asset.colorIndex))
        }
        PropertyRow(label: recorded ? "Instrument" : "Sample") {
            Menu(inst.preset) {
                if recorded {
                    ForEach(RecordedInstruments.names, id: \.self) { n in
                        Button(n) {
                            store.replaceInstrument(ofAsset: assetID, with: .synth(n))
                            if !store.transport.playing { store.previewInstrument(.synth(n)) }
                        }
                    }
                    Divider()
                    Button("Play an Audio File Instead…") { store.chooseSampleFile(for: assetID) }
                } else {
                    Button("Choose Another File…") { store.chooseSampleFile(for: assetID) }
                    if !SampleLibrary.isBundled(file) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) }
                            .disabled(missing)
                    }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(recorded ? (RecordedInstruments.named(inst.preset)?.summary ?? "") : file)
        }
        if !recorded {
            SampleWaveform(path: file, start: value("start"),
                           loop: value("loop") > 0.5 && value("playmode") < 0.5 ? (value("loopstart"), value("loopend")) : nil,
                           onStart: { v in store.live { $0.updateNotes(assetID) { $0.instrument.params["start"] = v } } },
                           onEnd: { store.endGesture() })
                .frame(height: 40)
                .padding(.horizontal, 10).padding(.vertical, 4)
        }
        if missing {
            Text(recorded ? "Shaw can't find its recordings of this instrument. Reinstall Shaw to get them back."
                          : "Shaw can't find this file. Choose it again to hear this pattern.")
                .font(Theme.tiny).foregroundStyle(Theme.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.bottom, 4)
        }
        if !compact {
            PropertyRow(label: "Length") {
                DragNumber(value: pattern.length / Double(store.project.beatsPerBar), range: 0.25...64, step: 0.25, sensitivity: 0.05,
                           format: { String(format: $0 == $0.rounded() ? "%.0f bars" : "%.2f bars", $0) },
                           onChange: { v in store.live { $0.updateNotes(assetID) { $0.length = v * Double(store.project.beatsPerBar) } } },
                           onEnd: { store.endGesture() })
            }
        }
        if showAll {
            ForEach(Self.groups, id: \.0) { group in
                SectionHeader(title: group.0)
                ForEach(group.1, id: \.self) { pid in paramRow(pid, value(pid)) }
            }
        } else {
            // Where the file starts means nothing for a real instrument's many recordings.
            ForEach(SamplerParams.basic.filter { !recorded || $0 != "start" }, id: \.self) { pid in paramRow(pid, value(pid)) }
        }
        Button(showAll ? "Show fewer sampler controls" : "Show all sampler controls (\(SamplerParams.defs.count - SamplerParams.basic.count) more)") {
            showAll.toggle()
        }
        .buttonStyle(.plain)
        .font(Theme.tiny).foregroundStyle(Theme.accent)
        .padding(.horizontal, 10).padding(.vertical, 4)
    }

    @ViewBuilder private func paramRow(_ pid: String, _ v: Double) -> some View {
        if let def = SamplerParams.defs.first(where: { $0.id == pid }) {
            ParamRow(def: def, value: v,
                     onChange: { nv in
                         // Root Note is a key, not a slider position between keys.
                         let x = def.unit == .note ? nv.rounded() : nv
                         store.live { $0.updateNotes(assetID) { $0.instrument.params[pid] = x } }
                     },
                     onEnd: { store.endGesture() })
            .padding(.horizontal, 10)
        }
    }
}

/// A small overview of a sample. The part before Start is shaded; drag to move Start.
struct SampleWaveform: View {
    @Environment(Store.self) private var store
    let path: String
    let start: Double
    /// Loop start and end (fractions of the file) when looping.
    var loop: (Double, Double)?
    let onStart: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        let _ = store.samplesLoaded // redraw once the file has loaded
        let peaks = SampleLibrary.shared.peaks(for: path) ?? []
        GeometryReader { geo in
            Canvas { ctx, size in
                let box = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
                ctx.fill(box, with: .color(Color.black.opacity(0.25)))
                guard !peaks.isEmpty, size.width > 2 else { return }
                if let (a, b) = loop {
                    let x0 = CGFloat(min(a, b)) * size.width, x1 = CGFloat(max(a, b)) * size.width
                    ctx.fill(Path(CGRect(x: x0, y: 0, width: max(1, x1 - x0), height: size.height)), with: .color(Theme.accent.opacity(0.14)))
                }
                // Scaled to the loudest point, so quiet samples are still readable.
                let top = max(peaks.max() ?? 1, 0.05)
                let cols = Int(size.width)
                let mid = size.height / 2
                var wave = Path()
                for c in 0..<cols {
                    let i0 = c * peaks.count / cols, i1 = max(i0 + 1, (c + 1) * peaks.count / cols)
                    var m: Float = 0
                    for i in i0..<min(i1, peaks.count) { m = max(m, peaks[i]) }
                    let h = CGFloat(m / top) * (size.height / 2 - 3)
                    wave.addRect(CGRect(x: CGFloat(c), y: mid - h, width: 1, height: max(0.5, h * 2)))
                }
                ctx.fill(wave, with: .color(Theme.textDim))
                let sx = CGFloat(start) * size.width
                ctx.fill(Path(CGRect(x: 0, y: 0, width: sx, height: size.height)), with: .color(Color.black.opacity(0.45)))
                ctx.fill(Path(CGRect(x: max(0, sx - 0.75), y: 0, width: 1.5, height: size.height)), with: .color(Theme.accent))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in onStart(min(1, max(0, Double(g.location.x / max(1, geo.size.width))))) }
                .onEnded { _ in onEnd() })
        }
        .help("Drag to set where the sample starts")
    }
}

/// Drum sounds playing your own files, each with a way back to the built-in sound.
struct KitSamplesSection: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let kit: String
    let files: [String: String]

    var body: some View {
        let mine = DrumKits.voices.filter { files[$0.id] != nil }
        if mine.isEmpty {
            Text("Drag an audio file onto a sound's name in the piano roll to use your own sample.")
                .font(Theme.tiny).foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 4)
        } else {
            ForEach(mine, id: \.id) { v in
                let file = files[v.id] ?? ""
                let there = SampleLibrary.exists(file)
                PropertyRow(label: v.name) {
                    Text(Instrument.sampleName(file))
                        .font(Theme.small).foregroundStyle(there ? Theme.text : Theme.textFaint)
                        .strikethrough(!there)
                        .lineLimit(1).truncationMode(.middle)
                        .help(there ? file : "Shaw can't find \(file)")
                    Spacer(minLength: 4)
                    Button { store.setKitSample(nil, voice: v.id, pattern: assetID) } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim)
                    .help("Use the built-in \(DrumKits.kitName(kit)) \(v.name) again")
                }
            }
        }
    }
}
