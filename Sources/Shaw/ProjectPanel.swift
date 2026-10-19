import ShawCore
import SwiftUI

struct ProjectPanel: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var dropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            summary
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.textDim)
                TextField("Search project", text: $search).textFieldStyle(.plain).font(Theme.small)
                Menu {
                    Button { store.openComposition(store.newComposition()) } label: { Label("New Composition", systemImage: assetIcon(.composition)) }
                    Button { store.open(asset: store.newPattern()) } label: { Label("New Pattern", systemImage: assetIcon(.notes)) }
                    Button { store.open(asset: store.newBeat()) } label: { Label("New Drum Pattern", systemImage: assetIcon(.drums)) }
                    Divider()
                    Button { store.importAudioDialog() } label: { Label("Import Audio…", systemImage: "square.and.arrow.down") }
                    Button { store.newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("New composition, pattern, beat, folder, or import")
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(Color.black.opacity(0.15))
            columnHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.project.folders) { folder in
                        FolderRow(folder: folder)
                        if folder.expanded {
                            ForEach(filtered(in: folder.id)) { a in AssetRow(asset: a, indent: 14) }
                        }
                    }
                    ForEach(filtered(in: nil)) { a in AssetRow(asset: a, indent: 0) }
                }
            }
            .background(dropTarget ? Theme.accent.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { store.selectedAssets = []; store.focus = .project }
            .onDrop(of: [.fileURL, .utf8PlainText], delegate: ShawDropDelegate(
                onPayload: { payload, _ in
                    if case .asset(let id) = payload { store.moveAssets([id], toFolder: nil); return true }
                    return false
                },
                onFiles: { urls, _ in store.importAudio(urls) },
                onHover: { dropTarget = $0 != nil }))
        }
    }

    private func filtered(in folder: UUID?) -> [Asset] {
        let folderIDs = Set(store.project.folders.map(\.id))
        return store.project.assets.filter { a in
            let inFolder = a.folderID.flatMap { folderIDs.contains($0) ? $0 : nil }
            guard inFolder == folder else { return false }
            return search.isEmpty || a.name.localizedCaseInsensitiveContains(search) || a.kind.label.localizedCaseInsensitiveContains(search)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 28)
            Text("Type").frame(width: 62, alignment: .leading)
            Text("Length").frame(width: 44, alignment: .trailing).padding(.trailing, 8)
        }
        .font(Theme.tiny).foregroundStyle(Theme.textFaint)
        .frame(height: 18)
        .background(Theme.panelHeader.opacity(0.6))
    }

    @ViewBuilder private var summary: some View {
        if let id = store.selectedAssets.first, let a = store.project.asset(id) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.label(a.colorIndex).opacity(0.85))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: assetIcon(a.kind)).foregroundStyle(.black.opacity(0.7)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(Theme.header).foregroundStyle(Theme.text).lineLimit(1)
                    Text(detail(a)).font(Theme.tiny).foregroundStyle(Theme.textDim).lineLimit(2)
                    let n = store.project.usageCount(of: id)
                    Text(n == 0 ? "Not used yet" : "Used \(n)×. Edits change every copy.")
                        .font(Theme.tiny).foregroundStyle(n > 1 ? Theme.accent : Theme.textFaint)
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private func detail(_ a: Asset) -> String {
        let len = formatLength(store.project.sourceLength(of: a.id), beatsPerBar: store.project.beatsPerBar)
        switch a.content {
        case .composition(let c): return "Composition · \(len) · \(c.tracks.count) tracks"
        case .notes(let p): return "Pattern · \(len) · \(p.instrument.isSampler ? "Sampler · " : "")\(p.instrument.displayName) · \(p.notes.count) notes"
        case .drums(let d): return "Beat · \(DrumKits.kitName(d.kit)) · \(d.steps) steps"
        case .audio(let f): return String(format: "Audio · %.2f s · %.0f Hz · %d ch", f.duration, f.sampleRate, f.channels)
        }
    }
}

struct FolderRow: View {
    @Environment(Store.self) private var store
    let folder: Folder
    @State private var target = false
    @State private var renaming = false
    @State private var text = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: folder.expanded ? "chevron.down" : "chevron.right").font(.system(size: 8)).frame(width: 10)
            Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            if renaming {
                TextField("", text: $text).textFieldStyle(.plain).font(Theme.small)
                    .focused($nameFocused)
                    .onAppear { nameFocused = true }
                    .onSubmit { commit() }
                    .onExitCommand { renaming = false }
                    .onChange(of: nameFocused) { _, f in if !f && renaming { commit() } }
            } else {
                Text(folder.name).font(Theme.small).foregroundStyle(Theme.text)
            }
            Spacer()
        }
        .padding(.leading, 8)
        .frame(height: 22)
        .background(target ? Theme.accent.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.edit { p in
                if let i = p.folders.firstIndex(where: { $0.id == folder.id }) { p.folders[i].expanded.toggle() }
            }
        }
        .contextMenu {
            Button("Rename") { text = folder.name; renaming = true }
            Button("Delete Folder") {
                store.edit { p in
                    p.folders.removeAll { $0.id == folder.id }
                    for i in p.assets.indices where p.assets[i].folderID == folder.id { p.assets[i].folderID = nil }
                }
            }
        }
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { payload, _ in
                guard case .asset(let id) = payload else { return false }
                let ids = store.selectedAssets.contains(id) ? store.selectedAssets : [id]
                store.moveAssets(ids, toFolder: folder.id)
                return true
            },
            onHover: { target = $0 != nil }))
    }

    private func commit() {
        renaming = false
        let n = text.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        store.edit { p in if let i = p.folders.firstIndex(where: { $0.id == folder.id }) { p.folders[i].name = n } }
    }
}

struct AssetRow: View {
    @Environment(Store.self) private var store
    let asset: Asset
    let indent: CGFloat
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let selected = store.selectedAssets.contains(asset.id)
        let isMain = asset.id == store.project.mainCompositionID
        HStack(spacing: 0) {
            Menu {
                ForEach(Theme.labels.indices, id: \.self) { i in
                    Button(Theme.labelNames[i]) { store.setAssetColor(asset.id, i) }
                }
            } label: {
                RoundedRectangle(cornerRadius: 2).fill(Theme.label(asset.colorIndex)).frame(width: 9, height: 11)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.leading, 6 + indent).padding(.trailing, 4)
            Image(systemName: assetIcon(asset.kind)).font(.system(size: 10)).foregroundStyle(Theme.textDim).frame(width: 16)
            if store.renamingAsset == asset.id {
                TextField("", text: $text)
                    .textFieldStyle(.plain).font(Theme.small).focused($focused)
                    .onSubmit { store.renameAsset(asset.id, to: text); store.renamingAsset = nil }
                    .onExitCommand { store.renamingAsset = nil }
                    .onAppear { text = asset.name; focused = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 4) {
                    Text(asset.name).font(Theme.small).foregroundStyle(Theme.text).lineLimit(1)
                    // Tag the song's main composition, unless its name already says so.
                    if isMain && asset.name.lowercased() != "main" {
                        Text("MAIN").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(asset.kind.label).font(Theme.tiny).foregroundStyle(Theme.textDim).frame(width: 62, alignment: .leading)
            Text(formatLength(store.project.sourceLength(of: asset.id), beatsPerBar: store.project.beatsPerBar)
                .replacingOccurrences(of: " bars", with: " bar").replacingOccurrences(of: " beats", with: " bt"))
                .font(Theme.tiny).foregroundStyle(Theme.textDim)
                .frame(width: 44, alignment: .trailing).padding(.trailing, 8)
        }
        .frame(height: 22)
        .background(selected ? Theme.accent.opacity(0.35) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(asset: asset.id) }
        .simultaneousGesture(TapGesture().onEnded {
            store.focus = .project
            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                if selected { store.selectedAssets.remove(asset.id) } else { store.selectedAssets.insert(asset.id) }
            } else {
                store.selectedAssets = [asset.id]
            }
            store.inspector = asset.kind == .composition ? .composition(asset.id) : .asset(asset.id)
        })
        .shawDraggable(.asset(asset.id), preview: asset.name)
        .contextMenu {
            Button("Open") { store.open(asset: asset.id) }
            Button("Rename") { store.renamingAsset = asset.id }
            Button("Duplicate") { store.duplicateAsset(asset.id) }
            if asset.kind == .composition && !isMain {
                Button("Set as Main Composition") { store.setMainComposition(asset.id) }
            }
            if !store.project.folders.isEmpty {
                Menu("Move to Folder") {
                    Button("None") { store.moveAssets([asset.id], toFolder: nil) }
                    ForEach(store.project.folders) { f in Button(f.name) { store.moveAssets([asset.id], toFolder: f.id) } }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.deleteAssets(store.selectedAssets.contains(asset.id) ? store.selectedAssets : [asset.id])
            }
            .disabled(isMain)
        }
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(onPayload: { payload, _ in
            // Dropping an effect on a composition in the project panel applies it to the composition.
            if case .effect(let k) = payload, asset.kind == .composition {
                store.addEffect(k, to: .composition(asset.id))
                return true
            }
            if case .effectInstance(let fx) = payload, asset.kind == .composition {
                store.dropEffect(fx, onto: .composition(asset.id), before: nil)
                return true
            }
            if case .preset(let name) = payload, asset.kind == .notes {
                store.edit { $0.updateNotes(asset.id) { $0.instrument = .preset(name) } }
                return true
            }
            if case .kit(let k) = payload, asset.kind == .drums {
                store.edit { $0.updateDrums(asset.id) { $0.kit = k } }
                return true
            }
            return false
        }))
    }
}
