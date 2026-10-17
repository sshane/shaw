import ShawCore
import SwiftUI

enum BrowserTab: String, CaseIterable { case instruments = "Instruments", effects = "Effects", samples = "Samples" }

struct BrowserPanel: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var selected: String?
    /// Set by the arrow keys so the list scrolls to keep the selection in view.
    @State private var reveal: String?
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
                BrowserSearchField(text: $search, placeholder: placeholder, focusRequest: store.focusBrowserSearch,
                                   onFocus: { store.focus = .browser },
                                   onMove: move, onSubmit: { _ = activateSelection() })
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(Color.black.opacity(0.15))
            ScrollViewReader { proxy in
                Group {
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
                .onChange(of: reveal) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }
        .onAppear { KeyRouter.shared.browserHandler = { e in handleKey(e) } }
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
        .onChange(of: store.browserTab) { old, _ in
            search = ""
            selected = nil
            reveal = nil
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
                    store.focus = .browser
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
        // Re-read when the library changes (InstrumentChoice.all reads the engine's copy).
        let _ = store.customInstruments
        ForEach(InstrumentChoice.categoryOrder, id: \.self) { cat in
            let items = instrumentItems(cat)
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
                       store.focus = .browser
                       store.previewInstrument(item)
                   },
                   onActivate: { store.addInstrument(item) })
        .id(item.id)
    }

    private func instrumentItems(_ category: String) -> [InstrumentChoice] {
        InstrumentChoice.all.filter { $0.category == category && (matches($0.name) || matches($0.category)) }
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
        let open = isOpen(folder)
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
                              store.focus = .browser
                              store.previewSampleFile(file.path)
                          },
                          onActivate: {
                              store.stopSamplePreview()
                              store.addSampler(file.path)
                          })
                .id(file.id)
            }
        }
    }

    private func isOpen(_ folder: String) -> Bool { !collapsedFolders.contains(folder) || !search.isEmpty }

    /// The files a folder shows right now (none while it's collapsed).
    private func visibleFiles(_ folder: String) -> [SampleFile] {
        guard isOpen(folder) else { return [] }
        return (store.sampleIndex[folder] ?? []).filter { matches($0.name) || matches($0.folder) }
    }

    // MARK: Effects

    @ViewBuilder private var effects: some View {
        let fx = EffectRegistry.search(search)
        let host = store.currentEffectHost
        Text(hostDescription(host))
            .font(Theme.tiny).foregroundStyle(Theme.textDim)
            .padding(10)
        ForEach(Self.effectCategories, id: \.self) { cat in
            let items = fx.filter { $0.category == cat }
            if !items.isEmpty {
                SectionHeader(title: cat)
                ForEach(items) { d in
                    BrowserRow(icon: icon(for: d.category), title: d.name, subtitle: d.summary, payload: .effect(d.id),
                               selected: selected == d.id, actionLabel: "Add",
                               onSelect: { selected = d.id; store.focus = .browser },
                               onActivate: { if let host { store.addEffect(d.id, to: host) } })
                    .id(d.id)
                }
            }
        }
    }

    private static let effectCategories = ["Space", "Modulation", "Dynamics", "EQ & Filter", "Distortion", "Utility"]

    // MARK: Keyboard

    /// One row of the current tab, in the order shown, so the arrow keys can walk the list.
    private struct Entry { let id: String; let select: () -> Void; let activate: () -> Void }

    private var entries: [Entry] {
        switch store.browserTab {
        case .instruments:
            return InstrumentChoice.categoryOrder.flatMap(instrumentItems).map { item in
                Entry(id: item.id, select: { store.previewInstrument(item) }, activate: { store.addInstrument(item) })
            }
        case .effects:
            let fx = EffectRegistry.search(search), host = store.currentEffectHost
            return Self.effectCategories.flatMap { cat in fx.filter { $0.category == cat } }.map { d in
                Entry(id: d.id, select: {}, activate: { if let host { store.addEffect(d.id, to: host) } })
            }
        case .samples:
            return store.sampleFolders.flatMap(visibleFiles).map { file in
                Entry(id: file.id, select: { store.previewSampleFile(file.path) },
                      activate: { store.stopSamplePreview(); store.addSampler(file.path) })
            }
        }
    }

    /// Up and down select the next or previous row and play it, just like clicking it.
    private func move(_ delta: Int) {
        let list = entries
        guard !list.isEmpty else { return }
        let i = selected.flatMap { s in list.firstIndex { $0.id == s } }
        let next = i.map { min(max($0 + delta, 0), list.count - 1) } ?? (delta > 0 ? 0 : list.count - 1)
        store.focus = .browser
        guard list[next].id != selected else { return }
        selected = list[next].id
        reveal = list[next].id
        list[next].select()
    }

    /// Return adds the selected row, like double-clicking it.
    private func activateSelection() -> Bool {
        guard let s = selected, let entry = entries.first(where: { $0.id == s }) else { return false }
        entry.activate()
        return true
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        switch e.keyCode {
        case 125: move(1); return true // down
        case 126: move(-1); return true // up
        case 36, 76: return activateSelection() // return, enter
        default: return false
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

/// The Browser's search box. Up and down move through the results and Return adds the selected
/// one, so you can type a few letters and pick a sound without reaching for the mouse.
struct BrowserSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequest: Int
    let onFocus: () -> Void
    let onMove: (Int) -> Void
    let onSubmit: () -> Void

    final class Field: NSTextField {
        var onFocus: (() -> Void)?
        override func becomeFirstResponder() -> Bool {
            let ok = super.becomeFirstResponder()
            if ok { onFocus?() }
            return ok
        }
    }

    func makeNSView(context: Context) -> Field {
        let f = Field(string: text)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 11)
        f.textColor = NSColor(Theme.text)
        f.delegate = context.coordinator
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.lastFocusRequest = focusRequest
        return f
    }

    func updateNSView(_ f: Field, context: Context) {
        context.coordinator.parent = self
        f.onFocus = onFocus
        if f.stringValue != text { f.stringValue = text }
        if context.coordinator.placeholder != placeholder {
            context.coordinator.placeholder = placeholder
            f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: NSColor(Theme.textFaint), .font: NSFont.systemFont(ofSize: 11),
            ])
        }
        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserSearchField
        var lastFocusRequest = 0
        var placeholder = ""
        init(_ parent: BrowserSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSTextField { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1); return true
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            default: return false
            }
        }
    }
}
