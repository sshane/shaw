import ShawCore
import SwiftUI

struct SessionPanel: View {
    @Environment(Store.self) private var store
    static let columnWidth: CGFloat = 132
    static let rowHeight: CGFloat = 30

    var body: some View {
        if let comp = store.activeComp {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Session · \(store.activeAsset?.name ?? "")").font(Theme.header).foregroundStyle(Theme.textDim)
                    Text("Clips launch on the next bar and loop. Drag anything from the Project panel into a slot.")
                        .font(Theme.tiny).foregroundStyle(Theme.textFaint)
                    Spacer()
                    Button("Stop All Clips") { store.engine.stopAllSession() }.controlSize(.small)
                    Button("Add Track") { store.addTrack() }.controlSize(.small)
                }
                .padding(.horizontal, 10).frame(height: 28)
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 1) {
                        ForEach(comp.tracks) { t in
                            SessionColumn(track: t, scenes: comp.sceneCount)
                                .frame(width: Self.columnWidth)
                        }
                        SceneColumn(scenes: comp.sceneCount)
                            .frame(width: 90)
                    }
                    .padding(6)
                }
            }
            .onTapGesture { store.focus = .session }
        }
    }
}

struct SessionColumn: View {
    @Environment(Store.self) private var store
    let track: Track
    let scenes: Int

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Rectangle().fill(Theme.label(track.colorIndex)).frame(width: 3)
                Text(track.name).font(Theme.small).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
            }
            .frame(height: 22)
            .background(Theme.panelHeader)
            .contentShape(Rectangle())
            .onTapGesture { store.inspector = .track(store.activeCompID, track.id) }
            .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(onPayload: { p, _ in
                if case .effect(let k) = p { store.addEffect(k, to: .track(store.activeCompID, track.id)); return true }
                return false
            }))
            ForEach(0..<scenes, id: \.self) { s in
                SlotCell(track: track, scene: s)
            }
            Button {
                store.engine.stopTrack(track.id)
            } label: {
                Image(systemName: "stop.fill").font(.system(size: 9))
                    .frame(maxWidth: .infinity).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Theme.control))
            }
            .buttonStyle(.plain)
            .help("Stop this track's clip at the next bar")
            HStack(spacing: 4) {
                ToggleChip(label: "M", on: track.mute, color: Theme.mute) { store.updateTrack(track.id) { $0.mute.toggle() } }
                ToggleChip(label: "S", on: track.solo, color: Theme.solo) { store.updateTrack(track.id) { $0.solo.toggle() } }
                MiniFader(value: track.volume, width: 70,
                          onChange: { v in store.updateTrack(track.id, live: true) { $0.volume = v } }, onEnd: { store.endGesture() })
            }
            .padding(.top, 2)
        }
    }
}

struct SlotCell: View {
    @Environment(Store.self) private var store
    let track: Track
    let scene: Int
    @State private var target = false
    @State private var lastClick = Date.distantPast

    var body: some View {
        let slot = track.slots[scene]
        let info = store.transport.sessions[track.id]
        let playing = info?.playing == scene
        let queued = info?.queued == scene
        Group {
            if let slot, let a = store.project.asset(slot.assetID) {
                HStack(spacing: 4) {
                    Button { store.launch(track: track.id, scene: scene) } label: {
                        Image(systemName: "play.fill").font(.system(size: 9))
                            .foregroundStyle(playing ? Color.green : (queued ? Color.yellow : Color.black.opacity(0.7)))
                            .frame(width: 20, height: SessionPanel.rowHeight)
                    }
                    .buttonStyle(.plain)
                    .help("Launch")
                    Text(a.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.black.opacity(0.8)).lineLimit(1)
                    Spacer(minLength: 0)
                    if store.project.usageCount(of: a.id) > 1 { Image(systemName: "link").font(.system(size: 8)).foregroundStyle(.black.opacity(0.6)) }
                }
                .frame(height: SessionPanel.rowHeight)
                .background(Theme.label(a.colorIndex).opacity(playing ? 1 : 0.75))
                .overlay(alignment: .bottom) {
                    if playing { SlotProgress(assetID: a.id, launchBeat: info?.launchBeat ?? 0) }
                }
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(queued ? Color.yellow : Color.clear, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .contentShape(Rectangle())
                .onTapGesture {
                    let now = Date()
                    if now.timeIntervalSince(lastClick) < 0.35 { store.open(asset: a.id) }
                    lastClick = now
                    store.inspector = .slot(store.activeCompID, track.id, scene)
                }
                .shawDraggable(.asset(a.id), preview: a.name)
                .contextMenu {
                    Button("Launch") { store.launch(track: track.id, scene: scene) }
                    Button("Open") { store.open(asset: a.id) }
                    Button("Place on Timeline at Playhead") {
                        store.addClip(asset: a.id, at: store.snapBeat(store.transport.position), track: track.id)
                    }
                    Divider()
                    Button("Remove from Slot", role: .destructive) { store.setSlot(track: track.id, scene: scene, asset: nil) }
                }
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.25))
                    .overlay(Image(systemName: "square.fill").font(.system(size: 5)).foregroundStyle(Theme.textFaint))
                    .frame(height: SessionPanel.rowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let now = Date()
                        if now.timeIntervalSince(lastClick) < 0.35 {
                            let id = store.newPattern(bars: 1)
                            store.setSlot(track: track.id, scene: scene, asset: id)
                            store.open(asset: id)
                        }
                        lastClick = now
                    }
                    .help("Drop a pattern, beat, composition or audio here. Double-click to draw a new pattern.")
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(target ? Theme.accent : Color.clear, lineWidth: 2))
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { payload, _ in
                switch payload {
                case .asset(let id): store.setSlot(track: track.id, scene: scene, asset: id)
                case .preset(let name): store.setSlot(track: track.id, scene: scene, asset: store.newPattern(preset: name, bars: 1))
                case .kit(let k): store.setSlot(track: track.id, scene: scene, asset: store.newBeat(kit: k))
                case .effect(let k): store.addEffect(k, to: .track(store.activeCompID, track.id))
                }
                return true
            },
            onHover: { target = $0 != nil }))
    }
}

struct SlotProgress: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let launchBeat: Double

    var body: some View {
        let len = max(store.project.sourceLength(of: assetID), 0.001)
        let pos = store.transport.sessionBeat - launchBeat
        let n = pos < 0 ? 0 : pos.truncatingRemainder(dividingBy: len) / len
        GeometryReader { g in
            Rectangle().fill(Color.black.opacity(0.45)).frame(width: g.size.width * n, height: 3)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct SceneColumn: View {
    @Environment(Store.self) private var store
    let scenes: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("Scenes").font(Theme.tiny).foregroundStyle(Theme.textDim).frame(height: 22)
            ForEach(0..<scenes, id: \.self) { s in
                Button { store.launchScene(s) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 8))
                        Text("Scene \(s + 1)").font(Theme.tiny)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: SessionPanel.rowHeight)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Theme.control))
                }
                .buttonStyle(.plain)
                .help("Launch every clip in this row")
            }
            Button {
                let id = store.activeCompID
                store.edit { $0.updateComposition(id) { $0.sceneCount += 1 } }
            } label: {
                Label("Scene", systemImage: "plus").font(Theme.tiny).frame(maxWidth: .infinity).frame(height: 20)
            }
            .buttonStyle(.borderless)
        }
    }
}
