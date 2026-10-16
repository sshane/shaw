import ShawCore
import SwiftUI

/// Toolbar controls shared by the Piano Roll and Beat Maker.
struct EditorControls: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 6) {
            IconButton(systemName: "pencil", active: store.drawMode,
                       help: store.drawMode ? "Draw mode: click to add (B to switch off)" : "Draw mode off: double-click to add or delete (B to switch)") {
                store.drawMode.toggle()
            }
            IconButton(systemName: store.auditionNotes ? "headphones" : "headphones.slash", active: store.auditionNotes,
                       help: "Hear notes as you click them (only while stopped)") {
                store.auditionNotes.toggle()
            }
            Divider().frame(height: 16)
            Button {
                if let id = store.editingClip { store.loop(aroundClip: id) }
            } label: {
                Label("Loop This", systemImage: "repeat").font(Theme.tiny)
            }
            .buttonStyle(.borderless)
            .disabled(store.editingClip == nil)
            .help("Loop just this clip while you edit it")
            Button { store.loopVariationRun() } label: {
                Label("Loop All", systemImage: "repeat.circle").font(Theme.tiny)
            }
            .buttonStyle(.borderless)
            .disabled(store.editingClip == nil)
            .help("Loop this clip together with the variations next to it")
            Button { store.saveVariation() } label: {
                Label("Save Variation", systemImage: "plus.square.on.square").font(Theme.tiny.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Keep this version and keep working on a copy right after it (⇧⌘D)")
        }
    }
}
