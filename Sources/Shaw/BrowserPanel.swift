import ShawCore
import SwiftUI

enum BrowserTab: String, CaseIterable { case instruments = "Instruments", effects = "Effects", samples = "Samples" }

struct BrowserPanel: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var selected: String?
    @FocusState private var searchFocused: Bool
    @State private var pulse = false
    @State private var collapsedFolders: Set<String> = []

    private var placeholder: String {
        switch store.browserTab {
        case .instruments: return "Search instruments (drums, bass, pad…)"
        case .effects: return "Search effects (reverb, delay…)"
        case .samples: return "Search samples (kick, vocal…)"
        }
    }

    var body: some View {
        let empty = !store.hasContent
        VStack(spacing: 0) {
            tabs(empty: empty)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.textDim)
                TextField(placeholder, text: $search)
                    .textFieldStyle(.plain).font(Theme.small).focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(Color.black.opacity(0.15))
            if store.browserTab == .samples {
                // Lazy, since a sample library can hold thousands of files.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) { samples }
                }
                .onAppear { store.scanSampleFoldersIfNeeded() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch store.browserTab {
                        case .instruments: instruments(empty: empty)
                        default: effects
                        }
                    }
                }
            }
        }
        .overlay {
            // When the project is empty, this is the one place to start, so make it obvious.
            if empty && store.browserTab == .instruments {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.accent, lineWidth: 2)
                    .opacity(pulse ? 0.9 : 0.25)
                    .allowsHitTesting(false)
                    .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true } }
            }
        }
        .onChange(of: store.focusBrowserSearch) { _, _ in searchFocused = true }
        .onChange(of: store.browserTab) { old, _ in
            search = ""
            selected = nil
            if old == .samples { store.stopSamplePreview() }
        }
    }

    private func tabs(empty: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(BrowserTab.allCases, id: \.self) { tab in
                let disabled = tab == .effects && empty
                let active = store.browserTab == tab
                Button {
                    store.browserTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .foregroundStyle(disabled ? Theme.textFaint.opacity(0.6) : (active ? Theme.text : Theme.textDim))
                        .background(active ? Theme.panel : Color.black.opacity(0.12))
                        .overlay(alignment: .bottom) { if active { Rectangle().fill(Theme.accent).frame(height: 2) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help(disabled ? "Add an instrument first. Effects go on clips, layers, and compositions." : "")
            }
        }
    }

    // MARK: Instruments

    @ViewBuilder private func instruments(empty: Bool) -> some View {
        if empty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Start here").font(Theme.header).foregroundStyle(Theme.accent)
                Text("Click an instrument to hear it. Double-click (or drag it right) to add it.")
                    .font(Theme.tiny).foregroundStyle(Theme.textDim)
            }
            .padding(10)
        }
        let all = InstrumentChoice.all.filter { matches($0.name) || matches($0.category) }
        // Re-read when the library changes (InstrumentChoice.all reads the engine's copy).
        let _ = store.customInstruments
        ForEach(InstrumentChoice.categoryOrder, id: \.self) { cat in
            let items = all.filter { $0.category == cat }
            if cat == "My Instruments" {
                if search.isEmpty || !items.isEmpty { myInstruments(items) }
            } else if !items.isEmpty {
                SectionHeader(title: cat)
                ForEach(items) { item in row(item) }
            }
        }
    }

    private func row(_ item: InstrumentChoice) -> some View {
        BrowserRow(icon: item.icon, title: item.name, subtitle: subtitle(item), payload: item.payload,
                   selected: selected == item.id, actionLabel: "Add",
                   onSelect: {
                       selected = item.id
                       store.previewInstrument(item)
                   },
                   onActivate: { store.addInstrument(item) })
    }

    /// Your saved instruments, with a + to build one from scratch.
    @ViewBuilder private func myInstruments(_ items: [InstrumentChoice]) -> some View {
        HStack(spacing: 4) {
            SectionHeader(title: "My Instruments")
            Button { store.newInstrumentFromScratch() } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .padding(.top, 6).padding(.trailing, 8)
            .help("Build a new instrument from scratch")
        }
        if items.isEmpty {
            Text("Change a sound and click Save as New Instrument, or click + to build one from scratch.")
                .font(Theme.tiny).foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 8).padding(.bottom, 4)
        }
        ForEach(items) { item in
            row(item).contextMenu {
                if let c = store.customInstruments.first(where: { $0.name == item.name }) {
                    Button("Rename…") { store.renameCustomInstrument(c.id) }
                    Button("Duplicate") { store.duplicateCustomInstrument(c.id) }
                    Divider()
                    Button("Delete") { store.deleteCustomInstrument(c.id) }
                }
            }
        }
    }

    private func subtitle(_ item: InstrumentChoice) -> String {
        switch item {
        case .kit(let k): return DrumKits.kits.first { $0.id == k }?.summary ?? "Drum kit"
        case .synth(let p):
            if item.category == "My Instruments" {
                let base = UserInstruments.named(p)?.basedOn
                return base.map { "Your instrument · from \($0)" } ?? "Your instrument · built from scratch"
            }
            return "Shaw Synth · \(item.category)"
        }
    }

    // MARK: Samples

    @ViewBuilder private var samples: some View {
        if store.sampleFolders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Use your own sounds").font(Theme.header).foregroundStyle(Theme.text)
                Text("Add a folder of samples, like drum hits, vocal chops, or loops. Click one to hear it. Double-click to add it as a new layer, or drag it onto the timeline or the piano roll.")
                    .font(Theme.tiny).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add Folder…") { store.addSampleFolderDialog() }
                    .controlSize(.small).padding(.top, 2)
            }
            .padding(10)
        } else {
            ForEach(store.sampleFolders, id: \.self) { folder in sampleFolder(folder) }
            Button { store.addSampleFolderDialog() } label: {
                Label("Add Folder…", systemImage: "plus").font(Theme.tiny)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
    }

    @ViewBuilder private func sampleFolder(_ folder: String) -> some View {
        let files = (store.sampleIndex[folder] ?? []).filter { matches($0.name) || matches($0.folder) }
        let open = !collapsedFolders.contains(folder) || !search.isEmpty
        HStack(spacing: 4) {
            Image(systemName: open ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.textFaint).frame(width: 10)
            Text(URL(fileURLWithPath: folder).lastPathComponent.uppercased())
                .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint).lineLimit(1)
            Spacer()
            if store.scanningFolders.contains(folder) {
                ProgressView().controlSize(.mini)
            } else if !FileManager.default.fileExists(atPath: folder) {
                Text("Missing").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsedFolders.contains(folder) { collapsedFolders.remove(folder) } else { collapsedFolders.insert(folder) }
        }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
            Button("Look for New Files") { store.rescanSamples(folder) }
            Divider()
            Button("Remove from Browser") { store.removeSampleFolder(folder) }
        }
        .help(folder)
        if open {
            if files.isEmpty, store.sampleIndex[folder] != nil {
                Text(search.isEmpty ? "No audio files in this folder." : "No matches.")
                    .font(Theme.tiny).foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 20).padding(.vertical, 2)
            }
            ForEach(Array(files.enumerated()), id: \.element.id) { i, file in
                if !file.folder.isEmpty, i == 0 || files[i - 1].folder != file.folder {
                    Text(file.folder).font(Theme.tiny).foregroundStyle(Theme.textFaint).lineLimit(1)
                        .padding(.leading, 22).padding(.trailing, 8).padding(.top, 5).padding(.bottom, 1)
                }
                SampleRow(file: file, selected: selected == file.id,
                          onSelect: {
                              selected = file.id
                              store.previewSampleFile(file.path)
                          },
                          onActivate: {
                              store.stopSamplePreview()
                              store.addSampler(file.path)
                          })
            }
        }
    }

    // MARK: Effects

    @ViewBuilder private var effects: some View {
        let fx = EffectRegistry.search(search)
        let host = store.currentEffectHost
        Text(hostDescription(host))
            .font(Theme.tiny).foregroundStyle(Theme.textDim)
            .padding(10)
        ForEach(["Space", "Modulation", "Dynamics", "EQ & Filter", "Distortion", "Utility"], id: \.self) { cat in
            let items = fx.filter { $0.category == cat }
            if !items.isEmpty {
                SectionHeader(title: cat)
                ForEach(items) { d in
                    BrowserRow(icon: icon(for: d.category), title: d.name, subtitle: d.summary, payload: .effect(d.id),
                               selected: selected == d.id, actionLabel: "Add",
                               onSelect: { selected = d.id },
                               onActivate: { if let host { store.addEffect(d.id, to: host) } })
                }
            }
        }
    }

    private func hostDescription(_ host: EffectHost?) -> String {
        switch host {
        case .clip?: return "Double-click adds to the selected clip. Or drag onto any clip, track, or composition tab."
        case .track(let c, let t)?:
            let name = store.project.composition(c)?.tracks.first { $0.id == t }?.name ?? "track"
            return "Double-click adds to \(name). Or drag onto any clip, track, or composition tab."
        case .composition(let id)?:
            return "Double-click adds to the whole \(store.project.asset(id)?.name ?? "composition"). Or drag it onto something."
        case nil: return "Drag onto a clip, track, or composition tab."
        }
    }

    private func matches(_ s: String) -> Bool {
        search.isEmpty || s.localizedCaseInsensitiveContains(search)
            || search.lowercased().split(separator: " ").allSatisfy { s.lowercased().contains($0) }
            || (search.lowercased().contains("drum") && s == "Drums")
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
}

/// One file in the Samples tab. It drags like a file from Finder: onto the timeline for an
/// audio clip, onto the piano roll for a sampler, or onto a drum sound to replace it.
struct SampleRow: View {
    let file: SampleFile
    var selected = false
    let onSelect: () -> Void
    let onActivate: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(Theme.accent).frame(width: 14)
            Text(file.name).font(Theme.small).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if hover || selected {
                Button("Add", action: onActivate)
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .help("Add a new layer that plays this sample")
            }
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(height: 21)
        .background(selected ? Theme.accent.opacity(0.22) : (hover ? Color.white.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onActivate)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .fileDraggable(file.path, preview: file.name)
    }
}

struct BrowserRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let payload: DragPayload
    var selected = false
    var actionLabel = "Add"
    let onSelect: () -> Void
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
            if hover || selected {
                Button(actionLabel, action: onActivate)
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(selected ? Theme.accent.opacity(0.22) : (hover ? Color.white.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onActivate)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .shawDraggable(payload, preview: title)
    }
}
