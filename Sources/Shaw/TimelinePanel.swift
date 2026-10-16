import ShawCore
import SwiftUI

struct TimelinePanel: View {
    @Environment(Store.self) private var store
    @State private var scrollX: CGFloat = 0
    @State private var scrollY: CGFloat = 0
    @State private var monitor = ScrollZoomMonitor()
    @State private var lanesSize: CGSize = .zero

    static let headerWidth: CGFloat = 200
    static let rulerHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            CompTabs()
            if let comp = store.activeComp {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        CornerView(comp: comp).frame(height: Self.rulerHeight)
                        TrackHeaderColumn(comp: comp, scrollY: scrollY)
                    }
                    .frame(width: Self.headerWidth)
                    .background(Theme.panel)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    VStack(spacing: 0) {
                        RulerView(comp: comp, scrollX: scrollX)
                            .frame(height: Self.rulerHeight)
                        GeometryReader { geo in
                            LanesView(comp: comp, scrollX: scrollX, scrollY: scrollY, size: geo.size)
                                .onAppear { lanesSize = geo.size; fit() }
                                .onChange(of: geo.size) { _, s in lanesSize = s }
                        }
                    }
                    .overlay {
                        PlayheadLine(scrollX: $scrollX, width: lanesSize.width)
                            .allowsHitTesting(false)
                    }
                    .clipped()
                }
                .background(FrameReporter { monitor.frame = $0 })
            }
        }
        .onAppear(perform: installScroll)
        .onDisappear { monitor.remove() }
        .onChange(of: store.activeCompID) { _, _ in scrollX = 0; scrollY = 0 }
        .onChange(of: store.fitRequest) { _, _ in fit() }
    }

    /// Zoom so the whole composition is visible.
    private func fit() {
        guard let comp = store.activeComp, lanesSize.width > 50 else { return }
        store.zoom = min(60, max(2, Double(lanesSize.width - 20) / max(comp.length, 4)))
        scrollX = 0
    }

    private func contentWidth(_ comp: Composition) -> CGFloat {
        CGFloat(max(comp.length, comp.contentEnd) + 32) * CGFloat(store.zoom)
    }

    private func installScroll() {
        monitor.onScroll = { dx, dy, p, mods in
            guard let comp = store.activeComp else { return }
            if mods.contains(.command) || mods.contains(.option) {
                zoom(by: exp(dy * 0.01), at: p.x - Self.headerWidth - 1)
                return
            }
            let maxX = max(0, contentWidth(comp) - lanesSize.width)
            let maxY = max(0, store.trackLayout(for: comp).total + 160 - lanesSize.height)
            if p.x > Self.headerWidth { scrollX = min(maxX, max(0, scrollX - dx)) }
            scrollY = min(maxY, max(0, scrollY - dy))
        }
        monitor.onMagnify = { m, p in zoom(by: 1 + m, at: p.x - Self.headerWidth - 1) }
        monitor.onRightClick = { p in
            // Right-click selects what's under the mouse first (like Finder / After Effects), then the menu opens.
            guard let comp = store.activeComp else { return false }
            let y = p.y - Self.rulerHeight
            guard y >= 0 else { return false }
            guard let ti = store.trackLayout(for: comp).index(atY: y + scrollY) else { return false }
            store.focus = .timeline
            if p.x < Self.headerWidth {
                store.selectedClips = []
                store.inspector = .track(store.activeCompID, comp.tracks[ti].id)
                return false
            }
            let beat = Double((p.x - Self.headerWidth - 1 + scrollX) / CGFloat(store.zoom))
            if let c = comp.tracks[ti].clips.last(where: { beat >= $0.start && beat < $0.end }) {
                if !store.selectedClips.contains(c.id) { store.selectedClips = [c.id] }
                store.inspector = .clip(store.activeCompID, c.id)
            }
            return false
        }
        monitor.install()
    }

    private func zoom(by factor: CGFloat, at x: CGFloat) {
        let old = CGFloat(store.zoom)
        let new = min(400, max(2, old * factor))
        let anchor = max(0, x)
        store.zoom = Double(new)
        scrollX = max(0, (scrollX + anchor) * new / old - anchor)
    }
}

// MARK: - Composition tabs

struct CompTabs: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 1) {
            ForEach(store.openComps, id: \.self) { id in
                CompTab(id: id)
            }
            Spacer()
        }
        .frame(height: 24)
        .background(Theme.panelHeader.opacity(0.7))
    }
}

struct CompTab: View {
    @Environment(Store.self) private var store
    let id: AssetID
    @State private var target = false

    var body: some View {
        let active = store.activeCompID == id
        let a = store.project.asset(id)
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(Theme.label(a?.colorIndex ?? 0)).frame(width: 7, height: 9)
            Text(a?.name ?? "?").font(.system(size: 11, weight: active ? .semibold : .regular))
            if store.openComps.count > 1 {
                Button { store.closeComposition(id) } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .foregroundStyle(active ? Theme.text : Theme.textDim)
        .background(target ? Theme.accent.opacity(0.3) : (active ? Theme.panel : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { store.openComposition(id) }
        .help("Composition. Drop an effect here to apply it to the whole composition.")
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { payload, _ in
                if case .effect(let k) = payload { store.addEffect(k, to: .composition(id)); return true }
                if case .effectInstance(let fx) = payload { store.dropEffect(fx, onto: .composition(id), before: nil); return true }
                return false
            },
            onHover: { target = $0 != nil }))
    }
}

// MARK: - Corner

struct CornerView: View {
    @Environment(Store.self) private var store
    let comp: Composition

    var body: some View {
        HStack(spacing: 6) {
            if comp.tracks.isEmpty {
                // Nothing to arrange yet; the empty timeline card is the one thing to do.
                Text(store.activeAsset?.name ?? "").font(Theme.small).foregroundStyle(Theme.textFaint)
                Spacer()
            } else {
            Button { store.addTrack() } label: {
                Label("Track", systemImage: "plus").font(Theme.tiny)
            }
            .buttonStyle(.borderless)
            .help("New empty track (⌘T)")
            Spacer()
            Text("Length").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            DragNumber(value: comp.length / Double(store.project.beatsPerBar), range: 1...999, step: 1, sensitivity: 0.1,
                       format: { "\(Int($0)) bars" },
                       onChange: { v in
                           let id = store.activeCompID
                           store.live { $0.updateComposition(id) { $0.length = v * Double(store.project.beatsPerBar) } }
                       },
                       onEnd: { store.endGesture() })
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(Theme.panelHeader)
        .onTapGesture { store.inspector = .composition(store.activeCompID) }
    }
}

// MARK: - Track headers

struct TrackHeaderColumn: View {
    @Environment(Store.self) private var store
    let comp: Composition
    let scrollY: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            let layout = store.trackLayout(for: comp)
            VStack(spacing: 0) {
                ForEach(Array(comp.tracks.enumerated()), id: \.element.id) { i, t in
                    TrackHeader(track: t, index: i)
                        .frame(height: store.trackHeight)
                    ForEach(layout.props[safe: i] ?? []) { prop in
                        KeyframeRowHeader(prop: prop)
                            .frame(height: TrackLayout.propRowHeight)
                    }
                }
            }
            .offset(y: -scrollY)
        }
        .clipped()
    }
}

struct TrackHeader: View {
    @Environment(Store.self) private var store
    let track: Track
    let index: Int
    @State private var renaming = false
    @State private var text = ""
    @State private var target = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let selected = store.inspector == .track(store.activeCompID, track.id)
        HStack(spacing: 0) {
            Rectangle().fill(Theme.label(track.colorIndex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if store.hasAnimation(track) {
                        let open = store.expandedTracks.contains(track.id)
                        Button {
                            if open { store.expandedTracks.remove(track.id) } else { store.expandedTracks.insert(track.id) }
                        } label: {
                            Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                                .frame(width: 12, height: 14).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        .help(open ? "Hide keyframes" : "Show keyframes")
                    }
                    if renaming {
                        TextField("", text: $text).textFieldStyle(.plain).font(Theme.small)
                            .focused($nameFocused)
                            .onAppear { nameFocused = true }
                            .onSubmit { commitRename() }
                            .onExitCommand { renaming = false }
                            .onChange(of: nameFocused) { _, f in if !f && renaming { commitRename() } }
                    } else {
                        Text(track.name).font(Theme.small).foregroundStyle(Theme.text).lineLimit(1)
                            .onTapGesture(count: 2) { text = track.name; renaming = true }
                    }
                    Spacer(minLength: 2)
                    if !track.effects.isEmpty {
                        Image(systemName: "fx").font(.system(size: 9)).foregroundStyle(Theme.accent)
                            .help("\(track.effects.count) effect\(track.effects.count == 1 ? "" : "s")")
                    }
                    ToggleChip(label: "M", on: track.mute, color: Theme.mute) {
                        store.updateTrack(track.id) { $0.mute.toggle() }
                    }
                    .help("Mute")
                    ToggleChip(label: "S", on: track.solo, color: Theme.solo) {
                        store.updateTrack(track.id) { $0.solo.toggle() }
                    }
                    .help("Solo")
                }
                HStack(spacing: 6) {
                    MiniFader(value: track.volume, width: 70,
                              onChange: { v in store.updateTrack(track.id, live: true) { $0.volume = v } },
                              onEnd: { store.endGesture() })
                    Knob(value: track.pan, size: 14,
                         onChange: { v in store.updateTrack(track.id, live: true) { $0.pan = v } },
                         onEnd: { store.endGesture() })
                        .help("Pan — double-click to center")
                    TrackMeter(trackID: track.id).frame(width: 40, height: 4)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(target ? Theme.accent.opacity(0.25) : (selected ? Theme.accent.opacity(0.14) : (index % 2 == 0 ? Theme.lane : Theme.laneAlt)))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            // Selecting a layer deselects clips, so Delete removes the layer itself.
            store.selectedClips = []
            store.inspector = .track(store.activeCompID, track.id)
            store.focus = .timeline
        }
        .contextMenu {
            Button("Rename") { text = track.name; renaming = true }
            Menu("Color") {
                ForEach(Theme.labels.indices, id: \.self) { i in
                    Button(Theme.labelNames[i]) { store.updateTrack(track.id) { $0.colorIndex = i } }
                }
            }
            Button("Add Track Below") { store.addTrack(at: index + 1) }
            Button("Move Up") { store.moveTrack(track.id, by: -1) }.disabled(index == 0)
            Button("Move Down") { store.moveTrack(track.id, by: 1) }
            Divider()
            Button("Delete Track", role: .destructive) { store.deleteTrack(track.id) }
        }
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { payload, _ in
                switch payload {
                case .effect(let k): store.addEffect(k, to: .track(store.activeCompID, track.id))
                case .effectInstance(let fx): store.dropEffect(fx, onto: .track(store.activeCompID, track.id), before: nil)
                case .asset(let id): store.addClip(asset: id, at: store.snapBeat(store.transport.position), track: track.id)
                case .preset, .kit: return false
                }
                return true
            },
            onHover: { target = $0 != nil }))
    }

    private func commitRename() {
        renaming = false
        let n = text.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { store.updateTrack(track.id) { $0.name = n } }
    }
}

struct TrackMeter: View {
    @Environment(Store.self) private var store
    let trackID: UUID

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
            let m = store.engine.meter(for: trackID)
            LevelMeterView(level: max(m?.peakL ?? 0, m?.peakR ?? 0))
                .clipShape(RoundedRectangle(cornerRadius: 1))
        }
    }
}

// MARK: - Ruler

struct RulerView: View {
    @Environment(Store.self) private var store
    let comp: Composition
    let scrollX: CGFloat
    @State private var loopDrag: (mode: Int, start: Double, end: Double, anchor: Double)?
    @State private var lengthDrag: Double?

    var body: some View {
        let zoom = CGFloat(store.zoom)
        let bpb = Double(store.project.beatsPerBar)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.panelHeader))
                    // Beyond the composition end.
                    let endX = CGFloat(comp.length) * zoom - scrollX
                    if endX < size.width {
                        ctx.fill(Path(CGRect(x: max(0, endX), y: 0, width: size.width - max(0, endX), height: size.height)),
                                 with: .color(Color.black.opacity(0.35)))
                    }
                    // Loop brace.
                    let hasClips = comp.tracks.contains { !$0.clips.isEmpty }
                    let lx0 = CGFloat(store.loopStart) * zoom - scrollX, lx1 = CGFloat(store.loopEnd) * zoom - scrollX
                    if hasClips {
                        // The loop bar: orange when looping, gray outline when off. Handles at both ends resize it.
                        let r = CGRect(x: lx0, y: 1, width: max(6, lx1 - lx0), height: Self.loopStrip - 2)
                        let on = store.loopEnabled
                        ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(on ? Theme.loopRegion.opacity(0.8) : Color.white.opacity(0.1)))
                        ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(on ? Theme.loopRegion : Theme.textFaint), lineWidth: 1)
                        for hx in [r.minX + 3, r.maxX - 5] {
                            ctx.fill(Path(roundedRect: CGRect(x: hx, y: r.minY + 2, width: 2, height: r.height - 4), cornerRadius: 1),
                                     with: .color(on ? Color.black.opacity(0.45) : Theme.textDim))
                        }
                    }
                    // Bar numbers and ticks.
                    var barStep = 1.0
                    while barStep * bpb * Double(zoom) < 46 { barStep *= 2 }
                    let firstBar = max(0, floor(Double(scrollX) / Double(zoom) / bpb / barStep) * barStep)
                    var bar = firstBar
                    while true {
                        let x = CGFloat(bar * bpb) * zoom - scrollX
                        if x > size.width { break }
                        ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 13)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                                   with: .color(Theme.textFaint), lineWidth: 1)
                        ctx.draw(Text("\(Int(bar) + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textDim),
                                 at: CGPoint(x: x + 3, y: 20), anchor: .leading)
                        if barStep == 1 && Double(zoom) * 1 >= 10 {
                            for b in 1..<Int(bpb) {
                                let bx = x + CGFloat(b) * zoom
                                ctx.stroke(Path { p in p.move(to: CGPoint(x: bx, y: size.height - 5)); p.addLine(to: CGPoint(x: bx, y: size.height)) },
                                           with: .color(Theme.textFaint.opacity(0.6)), lineWidth: 1)
                            }
                        }
                        bar += barStep
                    }
                    // Composition end marker.
                    ctx.fill(Path { p in
                        p.move(to: CGPoint(x: endX, y: size.height))
                        p.addLine(to: CGPoint(x: endX - 6, y: size.height - 9))
                        p.addLine(to: CGPoint(x: endX, y: size.height - 9))
                        p.closeSubpath()
                    }, with: .color(Theme.accent))
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: endX, y: 12)); p.addLine(to: CGPoint(x: endX, y: size.height)) },
                               with: .color(Theme.accent), lineWidth: 1.5)
                }
                // Comp-end handle (drag to change duration).
                Rectangle().fill(Color.clear).frame(width: 12, height: Self.handleHeight)
                    .contentShape(Rectangle())
                    .offset(x: CGFloat(comp.length) * zoom - scrollX - 9, y: TimelinePanel.rulerHeight - Self.handleHeight)
                    .onHover { NSCursor.set(.resizeLeftRight, when: $0) }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                        if lengthDrag == nil { lengthDrag = comp.length }
                        let beats = lengthDrag! + Double(g.translation.width / zoom)
                        let snapped = max(bpb, (beats / bpb).rounded() * bpb)
                        let id = store.activeCompID
                        store.live { $0.updateComposition(id) { $0.length = snapped } }
                    }.onEnded { _ in lengthDrag = nil; store.endGesture() })
                    .help("Composition end — drag to change duration")
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard case .active(let p) = phase, p.y < Self.loopStrip else { NSCursor.arrow.set(); return }
                let lx0 = CGFloat(store.loopStart) * zoom - scrollX, lx1 = CGFloat(store.loopEnd) * zoom - scrollX
                if abs(p.x - lx0) < 8 || abs(p.x - lx1) < 8 { NSCursor.resizeLeftRight.set() }
                else if p.x > lx0 && p.x < lx1 { NSCursor.openHand.set() }
                else { NSCursor.pointingHand.set() }
            }
            .gesture(rulerGesture(zoom: zoom, height: geo.size.height))
            .help("Top strip: click the loop bar to turn looping on/off, drag its ends to resize, drag the middle to move, click an empty bar to loop it. Below: click to move the playhead.")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    static let handleHeight: CGFloat = 14
    static let loopStrip: CGFloat = 14

    /// Top strip edits the loop brace; the rest scrubs the playhead.
    private func rulerGesture(zoom: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let beat = Double((g.location.x + scrollX) / zoom)
                let startBeat = Double((g.startLocation.x + scrollX) / zoom)
                if g.startLocation.y < Self.loopStrip {
                    let snap = { (b: Double) in store.snapBeat(b, disable: NSEvent.modifierFlags.contains(.command)) }
                    if loopDrag == nil {
                        let edge = 8 / Double(zoom)
                        if abs(startBeat - store.loopStart) < edge { loopDrag = (1, store.loopStart, store.loopEnd, startBeat) }
                        else if abs(startBeat - store.loopEnd) < edge { loopDrag = (2, store.loopStart, store.loopEnd, startBeat) }
                        else if startBeat > store.loopStart && startBeat < store.loopEnd { loopDrag = (3, store.loopStart, store.loopEnd, startBeat) }
                        else { loopDrag = (0, snap(startBeat), snap(startBeat), startBeat) }
                    }
                    guard let d = loopDrag else { return }
                    let delta = beat - d.anchor
                    let minLen = max(store.gridBeats(), 0.25)
                    switch d.mode {
                    case 1: store.loopStart = min(snap(d.start + delta), store.loopEnd - minLen)
                    case 2: store.loopEnd = max(snap(d.end + delta), store.loopStart + minLen)
                    case 3:
                        let s = max(0, snap(d.start + delta))
                        store.loopStart = s
                        store.loopEnd = s + (d.end - d.start)
                    default:
                        let a = snap(d.anchor), b = snap(beat)
                        if abs(b - a) >= minLen {
                            store.loopStart = min(a, b)
                            store.loopEnd = max(a, b)
                            store.loopEnabled = true
                        }
                    }
                } else {
                    store.scrubbing = true
                    store.seek(store.snapBeat(beat, disable: NSEvent.modifierFlags.contains(.command)))
                }
            }
            .onEnded { g in
                store.scrubbing = false
                if g.startLocation.y < Self.loopStrip, let d = loopDrag, abs(g.translation.width) < 2 {
                    if d.mode == 0 {
                        // Click an empty spot in the strip: loop that bar.
                        let bar = Double(store.project.beatsPerBar)
                        let b = (Double((g.startLocation.x + scrollX) / zoom) / bar).rounded(.down) * bar
                        store.loopStart = max(0, b)
                        store.loopEnd = max(0, b) + bar
                        store.loopEnabled = true
                    } else {
                        store.loopEnabled.toggle() // click the loop bar to turn looping on/off
                    }
                }
                loopDrag = nil
            }
    }
}

// MARK: - Playhead

struct PlayheadLine: View {
    @Environment(Store.self) private var store
    @Binding var scrollX: CGFloat
    let width: CGFloat

    var body: some View {
        let x = CGFloat(store.transport.position * store.zoom) - scrollX
        ZStack(alignment: .topLeading) {
            Color.clear
            if x >= 0 && x <= width {
                Rectangle().fill(Theme.playhead).frame(width: 1.5)
                    .offset(x: x)
                Path { p in
                    p.move(to: CGPoint(x: x - 5, y: TimelinePanel.rulerHeight - 9))
                    p.addLine(to: CGPoint(x: x + 5, y: TimelinePanel.rulerHeight - 9))
                    p.addLine(to: CGPoint(x: x, y: TimelinePanel.rulerHeight - 2))
                    p.closeSubpath()
                }
                .fill(Theme.playhead)
            }
        }
        .onChange(of: store.transport.position) { _, pos in
            // Follow the playhead while playing.
            guard store.transport.playing, !store.scrubbing, width > 50 else { return }
            let px = CGFloat(pos * store.zoom) - scrollX
            if px > width * 0.92 || px < 0 { scrollX = max(0, CGFloat(pos * store.zoom) - width * 0.08) }
        }
    }
}
