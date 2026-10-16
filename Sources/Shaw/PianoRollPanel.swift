import ShawCore
import SwiftUI

/// Which pitches the piano roll shows, top to bottom. Synths get all 128 keys;
/// drum kits get one row per sound (C1 = kick, upward), like a folded Drum Rack.
struct RowLayout: Equatable {
    let top: Int
    let count: Int
    var bottom: Int { top - count + 1 }

    static let piano = RowLayout(top: 127, count: 128)
    static let drums = RowLayout(top: DrumKits.basePitch + DrumKits.voices.count - 1, count: DrumKits.voices.count)
    static func of(_ i: Instrument) -> RowLayout { i.isDrumKit ? .drums : .piano }

    func row(of pitch: Int) -> Int { top - pitch }
    func pitch(atRow r: Int) -> Int { top - min(count - 1, max(0, r)) }
    func clamp(_ pitch: Int) -> Int { min(top, max(bottom, pitch)) }
    func contains(_ pitch: Int) -> Bool { pitch >= bottom && pitch <= top }
}

enum RollGrid {
    static let options: [(String, Double)] = [("1/4", 1), ("1/8", 0.5), ("1/16", 0.25), ("1/32", 0.125), ("1/8T", 1.0 / 3), ("1/16T", 1.0 / 6), ("Off", 0)]
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static func name(_ pitch: Int) -> String { "\(noteNames[pitch % 12])\(pitch / 12 - 1)" }
    static func isBlack(_ pitch: Int) -> Bool { [1, 3, 6, 8, 10].contains(pitch % 12) }
}

struct PianoRollPanel: View {
    @Environment(Store.self) private var store
    @State private var scrollX: CGFloat = 0
    @State private var scrollY: CGFloat = -1
    @State private var monitor = ScrollZoomMonitor()
    @State private var gridSize: CGSize = .zero
    @State private var keyHeight: CGFloat = 13

    static let keyboardWidth: CGFloat = 76
    static let rulerHeight: CGFloat = 18
    static let velocityHeight: CGFloat = 56

    var body: some View {
        if let id = store.pianoRollAsset, let a = store.project.asset(id), case .notes(let p) = a.content {
            let layout = RowLayout.of(p.instrument)
            let rowH = p.instrument.isDrumKit ? max(keyHeight, 22) : keyHeight
            VStack(spacing: 0) {
                toolbar(a, p)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Theme.panelHeader.frame(height: Self.rulerHeight)
                        Keyboard(assetID: id, instrument: p.instrument, scrollY: scrollY, keyHeight: rowH, layout: layout)
                        Text("Velocity").font(.system(size: 9)).foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity).frame(height: Self.velocityHeight).background(Theme.panelHeader)
                    }
                    .frame(width: Self.keyboardWidth)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    VStack(spacing: 0) {
                        RollRuler(pattern: p, assetID: id, scrollX: scrollX)
                            .frame(height: Self.rulerHeight)
                        GeometryReader { geo in
                            if p.instrument.isDrumKit && store.drumStepView {
                                DrumStepView(assetID: id, pattern: p, scrollX: scrollX, rowHeight: rowH, size: geo.size)
                            } else {
                            NoteGrid(assetID: id, pattern: p, scrollX: scrollX, scrollY: scrollY, keyHeight: rowH, layout: layout, size: geo.size)
                                .onAppear { gridSize = geo.size; centerIfNeeded(p, geo.size) }
                                .onChange(of: geo.size) { _, s in gridSize = s }
                            }
                        }
                        VelocityLane(assetID: id, pattern: p, scrollX: scrollX)
                            .frame(height: Self.velocityHeight)
                    }
                    .overlay {
                        RollPlayhead(assetID: id, scrollX: scrollX).allowsHitTesting(false)
                    }
                    .clipped()
                }
                .background(FrameReporter { monitor.frame = $0 })
            }
            .onAppear { install(id) }
            .onDisappear { monitor.remove() }
            .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(onPayload: { payload, _ in
                // Drag an instrument onto the piano roll to swap the sound and keep the notes.
                guard case .preset(let name) = payload else { NSSound.beep(); return false }
                return store.replaceInstrument(ofAsset: id, with: .synth(name))
            }))
            .onChange(of: store.playingPitches) { _, pitches in reveal(pitches, layout: layout, rowH: rowH) }
            .onChange(of: store.keyboardOctave) { _, _ in
                if layout == .piano { reveal([store.keyboardBasePitch, store.keyboardBasePitch + 17], layout: layout, rowH: rowH) }
            }
            .onChange(of: store.pianoRollAsset) { _, new in
                scrollY = -1
                scrollX = 0
                store.selectedNotes = []
                if let new, case .notes(let p)? = store.project.asset(new)?.content { centerIfNeeded(p, gridSize) }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "pianokeys").font(.system(size: 28)).foregroundStyle(Theme.textFaint)
                Text("Nothing to edit yet").font(Theme.header).foregroundStyle(Theme.textFaint)
                Text("Add an instrument from the Browser, or double-click a clip.")
                    .font(Theme.small).foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Scroll so the given pitches are on screen (used while playing the computer keyboard).
    private func reveal(_ pitches: Set<Int>, layout: RowLayout, rowH: CGFloat) {
        guard let lo = pitches.min(), let hi = pitches.max(), gridSize.height > 20 else { return }
        let top = CGFloat(layout.row(of: hi)) * rowH, bottom = CGFloat(layout.row(of: lo) + 1) * rowH
        if top < scrollY || bottom > scrollY + gridSize.height {
            let mid = (top + bottom) / 2
            withAnimation(.easeOut(duration: 0.15)) {
                scrollY = max(0, min(CGFloat(layout.count) * rowH - gridSize.height, mid - gridSize.height / 2))
            }
        }
    }

    private func centerIfNeeded(_ p: NotePattern, _ size: CGSize) {
        guard scrollY < 0 else { return }
        let layout = RowLayout.of(p.instrument)
        if layout != .piano { scrollY = 0; return }
        let center = p.notes.isEmpty ? 60.0 : Double(p.notes.map(\.pitch).reduce(0, +)) / Double(p.notes.count)
        scrollY = max(0, (127 - CGFloat(center)) * keyHeight - size.height / 2)
    }

    @ViewBuilder private func toolbar(_ a: Asset, _ p: NotePattern) -> some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            Menu {
                ForEach(store.project.assets.filter { $0.kind == .notes }) { pa in
                    Button(pa.name) { store.open(asset: pa.id) }
                }
                Divider()
                Button("New Pattern") { store.open(asset: store.newPattern()) }
            } label: {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.label(a.colorIndex)).frame(width: 8, height: 10)
                    Text(a.name).font(Theme.header)
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Menu(p.instrument.preset) {
                Section("Synths") {
                    ForEach(SynthPresets.names, id: \.self) { n in
                        Button(n) { store.replaceInstrument(ofAsset: a.id, with: .synth(n)) }
                    }
                }
                Section("Drum Kits") {
                    ForEach(DrumKits.kits) { k in
                        Button(k.name) { store.replaceInstrument(ofAsset: a.id, with: .kit(k.id)) }
                    }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Change the sound and keep the notes. You can also drag an instrument from the Browser onto the piano roll.")
            if p.instrument.isDrumKit {
                @Bindable var store = store
                Picker("", selection: $store.drumStepView) {
                    Text("Piano Roll").tag(false)
                    Text("Steps").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140).controlSize(.small)
                .help("Two views of the same drum pattern: piano roll, or an FL Studio-style step grid")
            }
            Button { store.inspector = .asset(a.id); store.workspace.reveal(.inspector) } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless).help("Edit synth")
            Divider().frame(height: 16)
            Text("Length").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            DragNumber(value: p.length / Double(store.project.beatsPerBar), range: 0.25...64, step: 0.25, sensitivity: 0.03,
                       format: { String(format: $0 == $0.rounded() ? "%.0f bars" : "%.2f bars", $0) },
                       onChange: { v in store.live { $0.updateNotes(a.id) { $0.length = v * Double(store.project.beatsPerBar) } } },
                       onEnd: { store.endGesture() })
            Text("Grid").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            Picker("", selection: $store.rollSnap) {
                ForEach(RollGrid.options, id: \.1) { o in Text(o.0).tag(o.1) }
            }
            .labelsHidden().frame(width: 70).controlSize(.small)
            Spacer()
            EditorControls()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.panelHeader.opacity(0.6))
    }

    private func install(_ id: AssetID) {
        monitor.onScroll = { dx, dy, pt, mods in
            if mods.contains(.command) {
                let old = store.rollZoom
                let new = min(600, max(8, old * exp(Double(dy) * 0.01)))
                let anchor = Double(max(0, pt.x - Self.keyboardWidth))
                store.rollZoom = new
                scrollX = CGFloat(max(0, (Double(scrollX) + anchor) * new / old - anchor))
                return
            }
            if mods.contains(.option) {
                keyHeight = min(30, max(6, keyHeight * exp(dy * 0.01)))
                return
            }
            let drums = (store.pianoRollAsset.flatMap { store.project.asset($0) }).map { a -> Bool in
                if case .notes(let p) = a.content { return p.instrument.isDrumKit }
                return false
            } ?? false
            let rows: CGFloat = drums ? CGFloat(RowLayout.drums.count) : 128
            let maxY = max(0, rows * (drums ? max(keyHeight, 22) : keyHeight) - gridSize.height)
            scrollY = min(maxY, max(0, scrollY - dy))
            if pt.x > Self.keyboardWidth { scrollX = max(0, scrollX - dx) }
        }
        monitor.onMagnify = { m, _ in store.rollZoom = min(600, max(8, store.rollZoom * (1 + Double(m)))) }
        monitor.onRightClick = { pt in
            // Right-click deletes the note under the cursor (FL Studio style).
            guard let pid = store.pianoRollAsset, case .notes(let p)? = store.project.asset(pid)?.content else { return false }
            let x = pt.x - Self.keyboardWidth - 1, y = pt.y - Self.rulerHeight
            guard x >= 0, y >= 0, y < gridSize.height else { return false }
            let beat = Double((x + scrollX) / CGFloat(store.rollZoom))
            let layout = RowLayout.of(p.instrument)
            let rowH = p.instrument.isDrumKit ? max(keyHeight, 22) : keyHeight
            let pitch = layout.pitch(atRow: Int((y + scrollY) / rowH))
            if let n = p.notes.last(where: { $0.pitch == pitch && beat >= $0.start && beat < $0.end }) {
                store.edit { $0.updateNotes(pid) { $0.notes.removeAll { $0.id == n.id } } }
                store.selectedNotes.remove(n.id)
                return true
            }
            return false
        }
        monitor.install()
        KeyRouter.shared.pianoRollHandler = { e in handleKey(e) }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard let id = store.pianoRollAsset, case .notes(let p)? = store.project.asset(id)?.content else { return false }
        let sel = store.selectedNotes
        let cmd = e.modifierFlags.contains(.command), shift = e.modifierFlags.contains(.shift)
        let grid = store.rollSnap > 0 ? store.rollSnap : 0.25
        func transform(_ f: @escaping (inout Note) -> Void) {
            store.edit { $0.updateNotes(id) { pat in for i in pat.notes.indices where sel.contains(pat.notes[i].id) { f(&pat.notes[i]) } } }
        }
        switch e.keyCode {
        case 51, 117:
            guard !sel.isEmpty else { return false }
            store.edit { $0.updateNotes(id) { $0.notes.removeAll { sel.contains($0.id) } } }
            store.selectedNotes = []
            return true
        case 126, 125: // up / down
            guard !sel.isEmpty else { return false }
            let d = (e.keyCode == 126 ? 1 : -1) * (shift ? 12 : 1)
            let layout = RowLayout.of(p.instrument)
            transform { $0.pitch = layout.clamp($0.pitch + (layout == .piano ? d : (d > 0 ? 1 : -1))) }
            if let n = p.notes.first(where: { sel.contains($0.id) }) { store.audition(n.pitch + d, instrument: p.instrument) }
            return true
        case 123 where e.modifierFlags.contains(.option), 124 where e.modifierFlags.contains(.option): // ⌥← / ⌥→ shorten / lengthen
            guard !sel.isEmpty else { return false }
            let d = (e.keyCode == 124 ? 1.0 : -1.0) * (shift ? 1 : grid)
            transform { $0.length = max(grid, $0.length + d) }
            if let n = p.notes.first(where: { sel.contains($0.id) }) { store.lastNoteLength = max(grid, n.length + d) }
            return true
        case 123, 124: // left / right
            guard !sel.isEmpty else { return false }
            let d = (e.keyCode == 124 ? grid : -grid) * (shift ? 4 : 1)
            transform { $0.start = max(0, $0.start + d) }
            return true
        case 8 where cmd, 7 where cmd: // ⌘C / ⌘X
            let chosen = p.notes.filter { sel.contains($0.id) }
            guard !chosen.isEmpty else { return true }
            store.noteClipboard = chosen
            if e.keyCode == 7 {
                store.edit { $0.updateNotes(id) { $0.notes.removeAll { sel.contains($0.id) } } }
                store.selectedNotes = []
            }
            return true
        case 9 where cmd: // ⌘V
            let clip = store.noteClipboard
            guard !clip.isEmpty else { return true }
            let first = clip.map(\.start).min() ?? 0
            let span = (clip.map(\.end).max() ?? 0) - first
            // Paste where you last clicked, or right after the copied notes.
            let at = store.rollInsertBeat ?? (first + (span / grid).rounded(.up) * grid)
            let pasted = clip.map { n -> Note in var c = n; c.id = UUID(); c.start = at + (n.start - first); return c }
            store.edit { $0.updateNotes(id) { $0.notes += pasted } }
            store.selectedNotes = Set(pasted.map(\.id))
            store.rollInsertBeat = at + (span / grid).rounded(.up) * grid
            return true
        case 0 where cmd: // ⌘A
            store.selectedNotes = Set(p.notes.map(\.id))
            return true
        case 2 where cmd && !shift: // ⌘D (⇧⌘D is Save Variation)
            let chosen = p.notes.filter { sel.contains($0.id) }
            guard !chosen.isEmpty else { return true }
            let span = (chosen.map(\.end).max() ?? 0) - (chosen.map(\.start).min() ?? 0)
            let shiftBy = (span / grid).rounded(.up) * grid
            let copies = chosen.map { n -> Note in var c = n; c.id = UUID(); c.start += shiftBy; return c }
            store.edit { $0.updateNotes(id) { $0.notes += copies } }
            store.selectedNotes = Set(copies.map(\.id))
            return true
        case 53: // escape
            store.selectedNotes = []
            return true
        default:
            return false
        }
    }

}

// MARK: - Keyboard

struct Keyboard: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let instrument: Instrument
    let scrollY: CGFloat
    let keyHeight: CGFloat
    var layout: RowLayout = .piano
    @State private var held: Int?
    @State private var hoverPitch: Int?

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.85)))
            let first = max(0, Int(scrollY / keyHeight) - 1)
            let last = min(layout.count - 1, Int((scrollY + size.height) / keyHeight) + 1)
            guard first <= last else { return }
            if instrument.isDrumKit {
                // Drum kits: one labelled pad per sound.
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.16)))
                for row in first...last {
                    let pitch = layout.pitch(atRow: row)
                    let y = CGFloat(row) * keyHeight - scrollY
                    let r = CGRect(x: 2, y: y + 1, width: size.width - 4, height: keyHeight - 2)
                    let lit = pitch == held || store.playingPitches.contains(pitch)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(lit ? Theme.accent : Color(white: 0.26)))
                    let name = DrumKits.voice(atPitch: pitch)?.name ?? ""
                    ctx.draw(Text(name).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text),
                             at: CGPoint(x: 8, y: y + keyHeight / 2), anchor: .leading)
                }
                return
            }
            let base = store.keyboardBasePitch
            for row in first...last {
                let pitch = layout.pitch(atRow: row)
                let y = CGFloat(row) * keyHeight - scrollY
                let black = RollGrid.isBlack(pitch)
                let r = CGRect(x: 0, y: y, width: black ? size.width * 0.62 : size.width, height: keyHeight)
                let lit = pitch == held || store.playingPitches.contains(pitch)
                ctx.fill(Path(r), with: .color(lit ? Theme.accent : (black ? Color(white: 0.12) : Color(white: 0.88))))
                // Accent stripe on the keys your computer keyboard can reach (A … ').
                if store.keyboardEnabled && pitch >= base && pitch <= base + 17 {
                    ctx.fill(Path(CGRect(x: size.width - 4, y: y, width: 4, height: keyHeight)), with: .color(Theme.accent.opacity(0.75)))
                }
                ctx.fill(Path(CGRect(x: 0, y: y + keyHeight - 0.5, width: size.width, height: 0.5)), with: .color(.black.opacity(0.25)))
                // C is always labelled; any other key shows its name while hovered or played.
                let showName = pitch % 12 == 0 || lit || pitch == hoverPitch
                if showName && keyHeight >= 7 {
                    let ink: Color = lit ? .white : (black ? .white.opacity(0.85) : .black.opacity(0.6))
                    let x = black ? size.width * 0.62 - 3 : size.width - 6
                    ctx.draw(Text(RollGrid.name(pitch)).font(.system(size: 9, weight: .semibold)).foregroundStyle(ink),
                             at: CGPoint(x: x, y: y + keyHeight / 2), anchor: .trailing)
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let p) = phase { hoverPitch = layout.pitch(atRow: Int((p.y + scrollY) / keyHeight)) } else { hoverPitch = nil }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                store.focus = .pianoRoll
                let pitch = layout.pitch(atRow: Int((g.location.y + scrollY) / keyHeight))
                if pitch != held {
                    if let h = held { store.engine.previewNoteOff(h) }
                    held = pitch
                    store.engine.previewNoteOn(pitch, velocity: 0.8, instrument: instrument)
                }
            }
            .onEnded { _ in
                if let h = held { store.engine.previewNoteOff(h) }
                held = nil
            })
    }
}

// MARK: - Ruler

struct RollRuler: View {
    @Environment(Store.self) private var store
    let pattern: NotePattern
    let assetID: AssetID
    let scrollX: CGFloat
    @State private var startLen: Double?

    var body: some View {
        let zoom = CGFloat(store.rollZoom)
        let bpb = Double(store.project.beatsPerBar)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.panelHeader))
                var beat = floor(Double(scrollX / zoom))
                while CGFloat(beat) * zoom - scrollX < size.width {
                    let x = CGFloat(beat) * zoom - scrollX
                    let isBar = Int(beat) % Int(bpb) == 0
                    if isBar {
                        ctx.draw(Text("\(Int(beat / bpb) + 1)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.textDim),
                                 at: CGPoint(x: x + 3, y: size.height / 2), anchor: .leading)
                    }
                    if isBar || zoom > 20 {
                        ctx.fill(Path(CGRect(x: x, y: isBar ? 0 : size.height - 5, width: 1, height: isBar ? size.height : 5)), with: .color(Theme.textFaint))
                    }
                    beat += 1
                }
                let endX = CGFloat(pattern.length) * zoom - scrollX
                ctx.fill(Path(CGRect(x: endX - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.accent))
            }
            Rectangle().fill(Theme.accent.opacity(0.001)).frame(width: 12)
                .offset(x: CGFloat(pattern.length) * zoom - scrollX - 6)
                .onHover { NSCursor.set(.resizeLeftRight, when: $0) }
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    if startLen == nil { startLen = pattern.length }
                    let v = max(1, ((startLen! + Double(g.translation.width / zoom)) ).rounded())
                    store.live { $0.updateNotes(assetID) { $0.length = v } }
                }.onEnded { _ in startLen = nil; store.endGesture() })
                .help("Pattern end. Drag it to change the length.")
        }
    }
}

// MARK: - Note grid

struct NoteGrid: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let pattern: NotePattern
    let scrollX: CGFloat
    let scrollY: CGFloat
    let keyHeight: CGFloat
    var layout: RowLayout = .piano
    let size: CGSize

    private enum Mode { case move, resize, marquee, pendingEmpty, none }
    private struct DragInfo {
        var mode: Mode
        var origin: [Note]
        var ids: Set<UUID>
        var anchor: Note?
        var lastPitch: Int
        var duplicatePending = false
        var hitNote: UUID?
    }
    @State private var drag: DragInfo?
    @State private var marquee: CGRect?
    @State private var previewPitch: Int?
    @State private var lastClick: (time: Date, point: CGPoint) = (.distantPast, .zero)

    private var zoom: CGFloat { CGFloat(store.rollZoom) }

    var body: some View {
        let sel = store.selectedNotes
        let grid = store.rollSnap
        let bpb = Double(store.project.beatsPerBar)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let first = max(0, Int(scrollY / keyHeight) - 1)
                let last = min(layout.count - 1, Int((scrollY + size.height) / keyHeight) + 1)
                if first <= last {
                    for row in first...last {
                        let pitch = layout.pitch(atRow: row)
                        let y = CGFloat(row) * keyHeight - scrollY
                        let c: Color = layout == .piano ? (RollGrid.isBlack(pitch) ? Color(white: 0.13) : Color(white: 0.17))
                            : (row % 2 == 0 ? Color(white: 0.17) : Color(white: 0.145))
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: keyHeight)), with: .color(c))
                        if pitch % 12 == 0 {
                            ctx.fill(Path(CGRect(x: 0, y: y + keyHeight - 1, width: size.width, height: 1)), with: .color(Color.white.opacity(0.1)))
                        }
                    }
                }
                let step = grid > 0 ? grid : 0.25
                var b = floor(Double(scrollX / zoom) / step) * step
                while CGFloat(b) * zoom - scrollX <= size.width {
                    let x = CGFloat(b) * zoom - scrollX
                    let isBar = abs(b / bpb - (b / bpb).rounded()) < 1e-6
                    let isBeat = abs(b - b.rounded()) < 1e-6
                    if isBar || isBeat || CGFloat(step) * zoom > 5 {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                                 with: .color(isBar ? Theme.gridBar : (isBeat ? Theme.gridBeat : Theme.gridSub)))
                    }
                    b += step
                }
                let endX = CGFloat(pattern.length) * zoom - scrollX
                if endX < size.width {
                    ctx.fill(Path(CGRect(x: max(0, endX), y: 0, width: size.width, height: size.height)), with: .color(Color.black.opacity(0.4)))
                }
                let color = store.color(of: assetID)
                for n in pattern.notes where layout.contains(n.pitch) {
                    let r = rect(of: n)
                    guard r.maxX >= 0, r.minX <= size.width, r.maxY >= 0, r.minY <= size.height else { continue }
                    let path = Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2)
                    ctx.fill(path, with: .color(color.opacity(0.45 + 0.55 * n.velocity)))
                    ctx.stroke(path, with: .color(sel.contains(n.id) ? .white : .black.opacity(0.5)), lineWidth: sel.contains(n.id) ? 1.5 : 1)
                    // Grip on the right edge shows where to grab for resizing.
                    if r.width > 14 {
                        ctx.fill(Path(CGRect(x: r.maxX - 4, y: r.minY + 3, width: 1.5, height: max(1, r.height - 6))), with: .color(.black.opacity(0.35)))
                    }
                    if r.width > 26 && keyHeight >= 10 {
                        ctx.draw(Text(layout == .piano ? RollGrid.name(n.pitch) : "").font(.system(size: 8, weight: .semibold)).foregroundStyle(.black.opacity(0.7)),
                                 at: CGPoint(x: r.minX + 3, y: r.midY), anchor: .leading)
                    }
                }
            }
            if let m = marquee {
                Rectangle().fill(Color.white.opacity(0.06))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    .frame(width: m.width, height: m.height).offset(x: m.minX, y: m.minY)
            }
            if pattern.notes.isEmpty {
                Text(store.drawMode ? "Click to draw notes" : "Double-click to add a note · or play the A–L keys to try ideas")
                    .font(Theme.small).foregroundStyle(Theme.textFaint)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let p) = phase, resizeHit(p) != nil {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in changed(g) }
            .onEnded { g in ended(g) })
    }

    private func rect(of n: Note) -> CGRect {
        CGRect(x: CGFloat(n.start) * zoom - scrollX, y: CGFloat(layout.row(of: n.pitch)) * keyHeight - scrollY,
               width: max(3, CGFloat(n.length) * zoom), height: keyHeight)
    }

    /// Generous resize grab zone: the right part of the note plus a few pixels past its end.
    private func resizeHit(_ p: CGPoint) -> Note? {
        pattern.notes.last { n in
            let r = rect(of: n)
            let inside = min(14, max(6, r.width * 0.4))
            return p.y >= r.minY && p.y < r.maxY && p.x >= r.maxX - inside && p.x <= r.maxX + 7
        }
    }

    private func hit(_ p: CGPoint) -> Note? { pattern.notes.last { rect(of: $0).contains(p) } }

    private func beat(atX x: CGFloat) -> Double { Double((x + scrollX) / zoom) }
    private func pitch(atY y: CGFloat) -> Int { layout.pitch(atRow: Int(floor((y + scrollY) / keyHeight))) }

    private func snap(_ b: Double, floorMode: Bool = false) -> Double {
        let g = store.rollSnap
        if g <= 0 || NSEvent.modifierFlags.contains(.command) && !floorMode { return max(0, b) }
        return max(0, floorMode ? floor(b / g) * g : (b / g).rounded() * g)
    }

    /// Held preview while dragging a note, only if auditioning is on and the song is stopped.
    private func preview(_ pitch: Int) {
        guard store.auditionNotes, !store.transport.playing, pitch != previewPitch else { return }
        if let p = previewPitch { store.engine.previewNoteOff(p) }
        previewPitch = pitch
        store.engine.previewNoteOn(pitch, velocity: 0.75, instrument: pattern.instrument)
    }

    private func changed(_ g: DragGesture.Value) {
        store.focus = .pianoRoll
        let mods = NSEvent.modifierFlags
        if drag == nil { begin(g.startLocation, mods) }
        guard var d = drag else { return }
        let moved = hypot(g.translation.width, g.translation.height)
        let dx = Double(g.translation.width / zoom)
        let minLen = store.rollSnap > 0 ? store.rollSnap : 1.0 / 32
        switch d.mode {
        case .pendingEmpty:
            // Dragging on empty space selects; it never creates a note.
            guard moved > 3 else { return }
            d.mode = .marquee
            drag = d
            fallthrough
        case .marquee:
            let r = CGRect(x: min(g.startLocation.x, g.location.x), y: min(g.startLocation.y, g.location.y),
                           width: abs(g.translation.width), height: abs(g.translation.height))
            marquee = r
            let picked = Set(pattern.notes.filter { rect(of: $0).intersects(r) }.map(\.id))
            store.selectedNotes = mods.contains(.shift) ? d.ids.union(picked) : picked
        case .move:
            guard let a = d.anchor, moved > 2 else { return }
            if d.duplicatePending {
                // Option-drag: leave copies behind, move the originals.
                let copies = d.origin.filter { d.ids.contains($0.id) }.map { n -> Note in var c = n; c.id = UUID(); return c }
                d.origin += copies
                d.duplicatePending = false
                drag = d
            }
            let dBeat = snap(a.start + dx) - a.start
            let dPitch = -Int((g.translation.height / keyHeight).rounded())
            let ids = d.ids
            let movedNotes = d.origin.map { n -> Note in
                guard ids.contains(n.id) else { return n }
                var m = n
                m.start = max(0, n.start + dBeat)
                m.pitch = layout.clamp(n.pitch + dPitch)
                return m
            }
            store.live { $0.updateNotes(assetID) { $0.notes = movedNotes } }
            if a.pitch + dPitch != d.lastPitch {
                d.lastPitch = a.pitch + dPitch
                preview(d.lastPitch)
                drag = d
            }
        case .resize:
            guard let a = d.anchor else { return }
            let newLen = max(minLen, snap(a.end + dx) - a.start)
            let delta = newLen - a.length
            let ids = d.ids
            let resized = d.origin.map { n -> Note in
                guard ids.contains(n.id) else { return n }
                var m = n
                m.length = max(minLen, n.length + delta)
                return m
            }
            store.live { $0.updateNotes(assetID) { $0.notes = resized } }
            store.lastNoteLength = newLen
        case .none:
            break
        }
    }

    private func begin(_ p: CGPoint, _ mods: NSEvent.ModifierFlags) {
        if let n = resizeHit(p) ?? hit(p) {
            let resize = resizeHit(p)?.id == n.id
            if mods.contains(.shift) {
                if store.selectedNotes.contains(n.id) { store.selectedNotes.remove(n.id) } else { store.selectedNotes.insert(n.id) }
                drag = DragInfo(mode: .none, origin: [], ids: [], anchor: nil, lastPitch: -1, hitNote: n.id)
                return
            }
            if !store.selectedNotes.contains(n.id) { store.selectedNotes = [n.id] }
            store.lastNoteLength = n.length
            drag = DragInfo(mode: resize ? .resize : .move, origin: pattern.notes, ids: store.selectedNotes, anchor: n,
                            lastPitch: n.pitch, duplicatePending: mods.contains(.option) && !resize, hitNote: n.id)
            preview(n.pitch)
            return
        }
        if store.drawMode {
            // Draw mode: a click on empty space draws a note; dragging sets its length.
            let note = makeNote(at: p)
            var origin = pattern.notes
            origin.append(note)
            let o = origin
            store.live { $0.updateNotes(assetID) { $0.notes = o } }
            store.selectedNotes = [note.id]
            drag = DragInfo(mode: .resize, origin: origin, ids: [note.id], anchor: note, lastPitch: note.pitch)
            preview(note.pitch)
            return
        }
        drag = DragInfo(mode: .pendingEmpty, origin: pattern.notes, ids: mods.contains(.shift) ? store.selectedNotes : [],
                        anchor: nil, lastPitch: -1)
    }

    private func makeNote(at p: CGPoint) -> Note {
        let start = snap(beat(atX: p.x), floorMode: true)
        // Drum hits are one grid step long; melodic notes reuse the last length you set.
        let length = pattern.instrument.isDrumKit ? (store.rollSnap > 0 ? store.rollSnap : 0.25) : store.lastNoteLength
        return Note(pitch: pitch(atY: p.y), start: start, length: length, velocity: 0.8)
    }

    private func ended(_ g: DragGesture.Value) {
        let wasClick = hypot(g.translation.width, g.translation.height) <= 3
        let d = drag
        drag = nil
        marquee = nil
        if let p = previewPitch { store.engine.previewNoteOff(p) }
        previewPitch = nil
        store.endGesture()
        guard wasClick else { return }
        let p = g.location
        let now = Date()
        let isDouble = now.timeIntervalSince(lastClick.time) < 0.35 && hypot(p.x - lastClick.point.x, p.y - lastClick.point.y) < 6
        lastClick = isDouble ? (.distantPast, .zero) : (now, p)
        if isDouble && !store.drawMode {
            if let id = d?.hitNote {
                // Double-click a note to delete it.
                store.edit { $0.updateNotes(assetID) { $0.notes.removeAll { $0.id == id } } }
                store.selectedNotes.remove(id)
            } else {
                // Double-click empty space to add a note.
                let note = makeNote(at: p)
                store.edit { $0.updateNotes(assetID) { $0.notes.append(note) } }
                store.selectedNotes = [note.id]
                store.audition(note.pitch, instrument: pattern.instrument)
            }
            return
        }
        if d?.mode == .pendingEmpty {
            // A plain click on empty space clears the selection and sets where ⌘V pastes.
            store.selectedNotes = []
            store.rollInsertBeat = snap(beat(atX: p.x), floorMode: true)
        }
    }
}

// MARK: - Velocity lane

struct VelocityLane: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let pattern: NotePattern
    let scrollX: CGFloat

    var body: some View {
        let zoom = CGFloat(store.rollZoom)
        let sel = store.selectedNotes
        let color = store.color(of: assetID)
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.panelHeader))
            for n in pattern.notes {
                let x = CGFloat(n.start) * zoom - scrollX
                guard x > -4 && x < size.width + 4 else { continue }
                let h = CGFloat(n.velocity) * (size.height - 6)
                let c: Color = sel.contains(n.id) ? .white : color
                ctx.fill(Path(CGRect(x: x, y: size.height - h, width: 2, height: h)), with: .color(c.opacity(0.9)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: size.height - h - 3, width: 7, height: 6)), with: .color(c))
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                store.focus = .pianoRoll
                let b = Double((g.location.x + scrollX) / zoom)
                let v = min(1, max(0.02, Double(1 - g.location.y / PianoRollPanel.velocityHeight)))
                let tol = Double(6 / zoom)
                let targets = pattern.notes.filter { abs($0.start - b) <= tol }
                guard !targets.isEmpty else { return }
                // If the touched note is selected, adjust the whole selection together.
                let ids = targets.contains { sel.contains($0.id) } ? sel : Set(targets.map(\.id))
                store.live { $0.updateNotes(assetID) { p in for i in p.notes.indices where ids.contains(p.notes[i].id) { p.notes[i].velocity = v } } }
            }
            .onEnded { _ in store.endGesture() })
        .help("Drag up and down to set note velocity")
    }
}

struct RollPlayhead: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let scrollX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let local = store.localPosition(of: assetID, at: store.transport.position), store.transport.playing {
                Rectangle().fill(Theme.playhead).frame(width: 1.5)
                    .offset(x: CGFloat(local * store.rollZoom) - scrollX)
            }
        }
    }
}

// MARK: - Drum step view

/// FL Studio-style step grid over a drum pattern's notes. Same data as the piano roll:
/// a lit step is a note on that row starting at that step.
struct DrumStepView: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    let pattern: NotePattern
    let scrollX: CGFloat
    let rowHeight: CGFloat
    let size: CGSize
    @State private var paintOn: Bool?
    @State private var painted: Set<Int> = []

    private var step: Double { store.rollSnap > 0 ? store.rollSnap : 0.25 }
    private var zoom: CGFloat { CGFloat(store.rollZoom) }
    private var steps: Int { max(1, Int((pattern.length / step).rounded())) }

    private func noteAt(_ pitch: Int, _ s: Int) -> Note? {
        let b = Double(s) * step
        return pattern.notes.first { $0.pitch == pitch && $0.start >= b - 1e-6 && $0.start < b + step - 1e-6 }
    }

    var body: some View {
        let layout = RowLayout.drums
        let color = store.color(of: assetID)
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg))
            let w = CGFloat(step) * zoom
            for row in 0..<layout.count {
                let pitch = layout.pitch(atRow: row)
                let y = CGFloat(row) * rowHeight
                for s in 0..<steps {
                    let x = CGFloat(s) * w - scrollX
                    guard x + w >= 0, x <= size.width else { continue }
                    let r = CGRect(x: x + 1.5, y: y + 2, width: max(2, w - 3), height: rowHeight - 4)
                    let beatShade = Int(Double(s) * step) % 2 == 0 ? Color(white: 0.24) : Color(white: 0.2)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(beatShade))
                    if let n = noteAt(pitch, s) {
                        ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(color.opacity(0.35 + 0.65 * n.velocity)))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in paint(g.location) }
            .onEnded { _ in paintOn = nil; painted = []; store.endGesture() })
        .help("Click or drag to paint steps. Same notes as the piano roll view.")
    }

    private func paint(_ p: CGPoint) {
        store.focus = .pianoRoll
        let row = Int(p.y / rowHeight), s = Int((p.x + scrollX) / (CGFloat(step) * zoom))
        guard row >= 0, row < RowLayout.drums.count, s >= 0, s < steps else { return }
        let key = row * 10_000 + s
        guard !painted.contains(key) else { return }
        painted.insert(key)
        let pitch = RowLayout.drums.pitch(atRow: row)
        let existing = noteAt(pitch, s)
        if paintOn == nil { paintOn = existing == nil }
        let st = step
        if paintOn == true, existing == nil {
            let n = Note(pitch: pitch, start: Double(s) * st, length: st, velocity: 0.85)
            store.live { $0.updateNotes(assetID) { $0.notes.append(n) } }
        } else if paintOn == false, let e = existing {
            store.live { $0.updateNotes(assetID) { $0.notes.removeAll { $0.id == e.id } } }
        }
    }
}
