import ShawCore
import SwiftUI

struct BrowserPanel: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.textDim)
                TextField("Search effects, instruments, kits…", text: $search)
                    .textFieldStyle(.plain).font(Theme.small).focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(Color.black.opacity(0.15))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let fx = EffectRegistry.search(search)
                    if !fx.isEmpty {
                        SectionHeader(title: "Audio Effects")
                        ForEach(fx) { d in
                            BrowserRow(icon: icon(for: d.category), title: d.name, subtitle: d.summary,
                                       payload: .effect(d.id)) {
                                if let host = store.currentEffectHost { store.addEffect(d.id, to: host) }
                            }
                        }
                    }
                    let presets = SynthPresets.names.filter { matches($0) || matches(SynthPresets.categories[$0] ?? "") || matches("synth instrument") }
                    if !presets.isEmpty {
                        SectionHeader(title: "Instruments · Shaw Synth")
                        ForEach(presets, id: \.self) { name in
                            BrowserRow(icon: "pianokeys", title: name, subtitle: SynthPresets.categories[name] ?? "Synth",
                                       payload: .preset(name)) {
                                applyPreset(name)
                            }
                        }
                    }
                    let kits = DrumKits.kits.filter { matches($0.name) || matches($0.summary) || matches("drum kit beat") }
                    if !kits.isEmpty {
                        SectionHeader(title: "Drum Kits")
                        ForEach(kits) { k in
                            BrowserRow(icon: "circle.grid.3x3.fill", title: k.name, subtitle: k.summary, payload: .kit(k.id)) {
                                applyKit(k.id)
                            }
                        }
                    }
                    Text("Drag onto a clip, track, composition tab or empty timeline. Double-click to apply to the current selection.")
                        .font(Theme.tiny).foregroundStyle(Theme.textFaint)
                        .padding(10)
                }
            }
        }
    }

    private func matches(_ s: String) -> Bool {
        search.isEmpty || s.localizedCaseInsensitiveContains(search) || search.lowercased().split(separator: " ").allSatisfy { s.lowercased().contains($0) }
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Space": return "sparkles"
        case "Modulation": return "waveform.path"
        case "Dynamics": return "gauge.with.dots.needle.33percent"
        case "EQ & Filter": return "slider.horizontal.below.square.filled.and.square"
        case "Distortion": return "flame"
        default: return "dial.medium"
        }
    }

    private func applyPreset(_ name: String) {
        if case .asset(let id)? = store.inspector, store.project.asset(id)?.kind == .notes {
            store.edit { $0.updateNotes(id) { $0.instrument = .preset(name) } }
        } else if let id = store.pianoRollAsset, store.workspace.isVisible(.pianoRoll) {
            store.edit { $0.updateNotes(id) { $0.instrument = .preset(name) } }
        } else {
            let id = store.newPattern(preset: name)
            store.open(asset: id)
        }
        store.engine.previewNoteOn(60, instrument: .preset(name))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.engine.previewNoteOff(60) }
    }

    private func applyKit(_ kit: String) {
        if let id = store.beatAsset, store.workspace.isVisible(.beatMaker) {
            store.edit { $0.updateDrums(id) { $0.kit = kit } }
        } else {
            store.open(asset: store.newBeat(kit: kit))
        }
        store.engine.previewDrum(kit: kit, sound: "kick")
    }
}

struct BrowserRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let payload: DragPayload
    let onActivate: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.small).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.tiny).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(hover ? Color.white.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onActivate)
        .shawDraggable(payload, preview: title)
        .help("Drag onto a target, or double-click")
    }
}
