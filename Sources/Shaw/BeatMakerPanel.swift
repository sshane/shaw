import ShawCore
import SwiftUI

struct BeatMakerPanel: View {
    @Environment(Store.self) private var store
    static let cellW: CGFloat = 24
    static let cellH: CGFloat = 26
    static let headerW: CGFloat = 200

    var body: some View {
        if let id = store.beatAsset, let a = store.project.asset(id), case .drums(let d) = a.content {
            VStack(spacing: 0) {
                toolbar(a, d)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(d.rows.enumerated()), id: \.element.id) { i, row in
                                DrumRowHeader(assetID: id, kit: d.kit, row: row, index: i)
                                    .frame(height: Self.cellH)
                            }
                            Menu {
                                ForEach(DrumKits.voices, id: \.id) { v in
                                    Button(v.name) { store.edit { $0.updateDrums(id) { $0.rows.append(DrumRow(sound: v.id, steps: $0.steps)) } } }
                                }
                            } label: {
                                Label("Add Row", systemImage: "plus").font(Theme.tiny)
                            }
                            .menuStyle(.borderlessButton).fixedSize().padding(6)
                        }
                        .frame(width: Self.headerW)
                        ScrollView(.horizontal) {
                            StepGrid(assetID: id, pattern: d)
                                .padding(.trailing, 20)
                        }
                    }
                }
            }
            .onAppear { installKeys() }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "circle.grid.3x3.fill").font(.system(size: 28)).foregroundStyle(Theme.textFaint)
                Text("No beat open").font(Theme.header).foregroundStyle(Theme.textDim)
                Text("Double-click a beat clip, or make a new one.").font(Theme.small).foregroundStyle(Theme.textFaint)
                Button("New Beat") { store.open(asset: store.newBeat()) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func installKeys() {
        KeyRouter.shared.beatMakerHandler = { _ in false }
    }

    @ViewBuilder private func toolbar(_ a: Asset, _ d: DrumPattern) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.project.assets.filter { $0.kind == .drums }) { b in Button(b.name) { store.open(asset: b.id) } }
                Divider()
                Button("New Beat") { store.open(asset: store.newBeat()) }
            } label: {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.label(a.colorIndex)).frame(width: 8, height: 10)
                    Text(a.name).font(Theme.header)
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Menu(DrumKits.kitName(d.kit)) {
                ForEach(DrumKits.kits) { k in
                    Button(k.name) {
                        store.edit { $0.updateDrums(a.id) { $0.kit = k.id } }
                        store.engine.previewDrum(kit: k.id, sound: "kick")
                    }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Drum kit")
            Divider().frame(height: 16)
            Text("Steps").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            Menu("\(d.steps)") {
                ForEach([8, 12, 16, 24, 32, 48, 64], id: \.self) { n in
                    Button("\(n)") { store.edit { $0.updateDrums(a.id) { $0.resize(steps: n) } } }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Text("Grid").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            Menu(resolutionName(d.stepsPerBeat)) {
                ForEach([(2, "1/8"), (3, "1/8T"), (4, "1/16"), (6, "1/16T"), (8, "1/32")], id: \.0) { r in
                    Button(r.1) { store.edit { $0.updateDrums(a.id) { $0.stepsPerBeat = r.0 } } }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Text("Swing").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            DragNumber(value: d.swing * 100, range: 0...100, step: 1, sensitivity: 0.5, format: { "\(Int($0))%" },
                       onChange: { v in store.live { $0.updateDrums(a.id) { $0.swing = v / 100 } } }, onEnd: { store.endGesture() })
            Spacer()
            Text("Click or drag to paint · Right-click a step for velocity · Click a name to hear it")
                .font(Theme.tiny).foregroundStyle(Theme.textFaint).lineLimit(1)
            Button("Clear") {
                store.edit { $0.updateDrums(a.id) { p in for i in p.rows.indices { p.rows[i].steps = Array(repeating: 0, count: p.steps) } } }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.panelHeader.opacity(0.6))
    }

    private func resolutionName(_ spb: Int) -> String {
        [2: "1/8", 3: "1/8T", 4: "1/16", 6: "1/16T", 8: "1/32"][spb] ?? "\(spb)/beat"
    }
}

struct DrumRowHeader: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let kit: String
    let row: DrumRow
    let index: Int

    var body: some View {
        HStack(spacing: 5) {
            Button {
                store.engine.previewDrum(kit: kit, sound: row.sound, pitch: row.pitch, volume: row.volume)
            } label: {
                Text(DrumKits.voiceName(row.sound))
                    .font(Theme.small).foregroundStyle(row.mute ? Theme.textFaint : Theme.text)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to preview")
            ToggleChip(label: "M", on: row.mute, color: Theme.mute) { update { $0.mute.toggle() } }
            MiniFader(value: row.volume, range: -36...6, width: 44,
                      onChange: { v in update(live: true) { $0.volume = v } }, onEnd: { store.endGesture() })
            DragNumber(value: row.pitch, range: -24...24, step: 1, sensitivity: 0.15,
                       format: { $0 == 0 ? "±0" : String(format: "%+.0f", $0) },
                       onChange: { v in update(live: true) { $0.pitch = v } }, onEnd: { store.endGesture() })
                .frame(width: 26)
                .help("Pitch in semitones")
            Menu {
                ForEach(DrumKits.voices, id: \.id) { v in Button(v.name) { update { $0.sound = v.id } } }
                Divider()
                Button("Remove Row", role: .destructive) {
                    store.edit { $0.updateDrums(assetID) { $0.rows.removeAll { $0.id == row.id } } }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(index % 2 == 0 ? Theme.lane : Theme.laneAlt)
    }

    private func update(live: Bool = false, _ f: @escaping (inout DrumRow) -> Void) {
        let rid = row.id
        let body: (inout Project) -> Void = { p in
            p.updateDrums(assetID) { d in if let i = d.rows.firstIndex(where: { $0.id == rid }) { f(&d.rows[i]) } }
        }
        if live { store.live(body) } else { store.edit(body) }
    }
}

struct StepGrid: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let pattern: DrumPattern
    @State private var paintValue: Double?
    @State private var painted: Set<Int> = []
    @State private var hover: (Int, Int)?

    private let cw = BeatMakerPanel.cellW, ch = BeatMakerPanel.cellH
    private func groupGap(_ step: Int) -> CGFloat { CGFloat(step / pattern.stepsPerBeat) * 4 }
    private func x(_ step: Int) -> CGFloat { CGFloat(step) * cw + groupGap(step) }

    var body: some View {
        let width = x(pattern.steps) + 4
        let height = CGFloat(pattern.rows.count) * ch
        let color = store.color(of: assetID)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for (ri, row) in pattern.rows.enumerated() {
                    let y = CGFloat(ri) * ch
                    for s in 0..<pattern.steps {
                        let v = s < row.steps.count ? row.steps[s] : 0
                        let r = CGRect(x: x(s) + 2, y: y + 3, width: cw - 4, height: ch - 6)
                        let beatShade = (s / pattern.stepsPerBeat) % 2 == 0 ? Color(white: 0.24) : Color(white: 0.2)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(beatShade))
                        if v > 0 {
                            let alpha = row.mute ? 0.3 : 0.35 + 0.65 * v
                            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(color.opacity(alpha)))
                            // Velocity bar
                            let vh = (r.height - 4) * CGFloat(v)
                            ctx.fill(Path(CGRect(x: r.maxX - 4, y: r.maxY - 2 - vh, width: 2, height: vh)), with: .color(.black.opacity(0.4)))
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            BeatPlayhead(assetID: assetID, pattern: pattern, xFor: x)
                .frame(width: width, height: height)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let p) = phase { hover = cell(at: p) } else { hover = nil }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in paint(at: g.location) }
            .onEnded { _ in
                paintValue = nil
                painted = []
                store.endGesture()
            })
        .contextMenu {
            if let (r, s) = hover {
                Button("Hard (100%)") { set(r, s, 1) }
                Button("Medium (70%)") { set(r, s, 0.7) }
                Button("Soft (40%)") { set(r, s, 0.4) }
                Button("Ghost (20%)") { set(r, s, 0.2) }
                Divider()
                Button("Off") { set(r, s, 0) }
                Divider()
                Button("Fill Every 2") { fill(r, every: 2) }
                Button("Fill Every 4") { fill(r, every: 4) }
                Button("Clear Row") { fill(r, every: 0) }
            }
        }
    }

    private func cell(at p: CGPoint) -> (Int, Int)? {
        let r = Int(p.y / ch)
        guard r >= 0, r < pattern.rows.count else { return nil }
        var s = Int(p.x / cw)
        while s > 0 && x(s) > p.x { s -= 1 }
        while s + 1 < pattern.steps && x(s + 1) <= p.x { s += 1 }
        guard s >= 0, s < pattern.steps else { return nil }
        return (r, s)
    }

    private func paint(at p: CGPoint) {
        store.focus = .beatMaker
        guard let (r, s) = cell(at: p) else { return }
        let key = r * 1000 + s
        guard !painted.contains(key) else { return }
        painted.insert(key)
        let current = pattern.rows[r].steps[safe: s] ?? 0
        if paintValue == nil { paintValue = current > 0 ? 0 : 0.85 }
        let v = paintValue!
        let rid = pattern.rows[r].id
        store.live { $0.updateDrums(assetID) { d in
            if let i = d.rows.firstIndex(where: { $0.id == rid }), s < d.rows[i].steps.count { d.rows[i].steps[s] = v }
        } }
        if v > 0 {
            let row = pattern.rows[r]
            store.engine.previewDrum(kit: pattern.kit, sound: row.sound, velocity: v, pitch: row.pitch, volume: row.volume)
        }
    }

    private func set(_ r: Int, _ s: Int, _ v: Double) {
        let rid = pattern.rows[r].id
        store.edit { $0.updateDrums(assetID) { d in
            if let i = d.rows.firstIndex(where: { $0.id == rid }), s < d.rows[i].steps.count { d.rows[i].steps[s] = v }
        } }
    }

    private func fill(_ r: Int, every n: Int) {
        let rid = pattern.rows[r].id
        store.edit { $0.updateDrums(assetID) { d in
            guard let i = d.rows.firstIndex(where: { $0.id == rid }) else { return }
            for s in d.rows[i].steps.indices { d.rows[i].steps[s] = n > 0 && s % n == 0 ? 0.85 : 0 }
        } }
    }
}

struct BeatPlayhead: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let pattern: DrumPattern
    let xFor: (Int) -> CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if store.transport.playing, let local = store.localPosition(of: assetID, at: store.transport.position) {
                let step = Int(local * Double(pattern.stepsPerBeat))
                if step >= 0 && step < pattern.steps {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.playhead, lineWidth: 1.5)
                        .frame(width: BeatMakerPanel.cellW - 2)
                        .offset(x: xFor(step) + 1)
                }
            }
        }
    }
}
