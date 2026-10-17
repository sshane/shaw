import ShawCore
import SwiftUI

struct PlacedClip: Identifiable {
    let clip: Clip
    let trackIndex: Int
    var id: UUID { clip.id }
}

struct LanesView: View {
    @Environment(Store.self) private var store
    let comp: Composition
    let scrollX: CGFloat
    let scrollY: CGFloat
    let size: CGSize

    @State private var dropPoint: CGPoint?
    @State private var marquee: CGRect?
    @State private var lastClick = Date.distantPast

    var body: some View {
        let zoom = CGFloat(store.zoom)
        let th = store.trackHeight
        let layout = store.trackLayout(for: comp)
        let visible0 = Double(scrollX / zoom), visible1 = Double((scrollX + size.width) / zoom)
        // Flattened so a clip keeps its identity (and drag state) while moving between tracks.
        let placed = comp.tracks.enumerated().flatMap { ti, t in t.clips.map { PlacedClip(clip: $0, trackIndex: ti) } }
            // Selected clips stay mounted even off-screen so an in-progress drag is never torn down.
            .filter { ($0.clip.end >= visible0 && $0.clip.start <= visible1) || store.selectedClips.contains($0.clip.id) }

        ZStack(alignment: .topLeading) {
            LaneBackground(comp: comp, layout: layout, scrollX: scrollX, scrollY: scrollY)
                .gesture(backgroundGesture(zoom: zoom, layout: layout))
            ForEach(placed) { pc in
                let x = CGFloat(pc.clip.start) * zoom - scrollX
                let y = layout.top(pc.trackIndex) - scrollY
                ClipView(clip: pc.clip, trackIndex: pc.trackIndex, layout: layout)
                    .frame(width: max(4, CGFloat(pc.clip.length) * zoom), height: th - 3)
                    .offset(x: x, y: y + 1)
            }
            // Keyframe rows (◆) under layers that are twirled open.
            ForEach(Array(layout.props.enumerated()), id: \.offset) { ti, props in
                ForEach(Array(props.enumerated()), id: \.element.id) { j, prop in
                    let y = layout.top(ti) + th + CGFloat(j) * TrackLayout.propRowHeight - scrollY
                    if y + TrackLayout.propRowHeight >= 0 && y <= size.height {
                        KeyframeLane(prop: prop, scrollX: scrollX, width: size.width)
                            .frame(width: size.width, height: TrackLayout.propRowHeight)
                            .offset(y: y)
                    }
                }
            }
            if let p = dropPoint {
                let beat = store.snapBeat(Double((p.x + scrollX) / zoom))
                let ti = layout.index(atY: p.y + scrollY) ?? comp.tracks.count
                Rectangle().fill(Theme.accent.opacity(0.3))
                    .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1))
                    .frame(width: max(8, CGFloat(store.project.beatsPerBar) * zoom), height: th - 3)
                    .offset(x: CGFloat(beat) * zoom - scrollX, y: layout.top(ti) - scrollY + 1)
                    .allowsHitTesting(false)
            }
            if let m = marquee {
                Rectangle().fill(Color.white.opacity(0.06))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    .frame(width: m.width, height: m.height)
                    .offset(x: m.minX, y: m.minY)
                    .allowsHitTesting(false)
            }
            if comp.tracks.allSatisfy({ $0.clips.isEmpty }) {
                EmptyTimelineCard(firstEver: !store.hasContent)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .onDrop(of: [.utf8PlainText, .fileURL], delegate: ShawDropDelegate(
            onPayload: { payload, loc in handleDrop(payload, at: loc) },
            onFiles: { urls, loc in
                let ids = store.importAudio(urls)
                var beat = store.snapBeat(Double((loc.x + scrollX) / zoom))
                let track = trackID(atY: loc.y)
                for id in ids {
                    store.addClip(asset: id, at: beat, track: track)
                    beat += store.project.sourceLength(of: id)
                }
            },
            onHover: { dropPoint = $0 }))
    }

    private func trackID(atY y: CGFloat) -> UUID? {
        guard let ti = store.trackLayout(for: comp).index(atY: y + scrollY) else { return nil }
        return comp.tracks[ti].id
    }

    private func handleDrop(_ payload: DragPayload, at loc: CGPoint) -> Bool {
        let zoom = CGFloat(store.zoom)
        let beat = store.snapBeat(Double((loc.x + scrollX) / zoom))
        let track = trackID(atY: loc.y)
        store.focus = .timeline
        switch payload {
        case .asset(let id):
            store.addClip(asset: id, at: beat, track: track)
        case .effect(let k):
            if let t = track { store.addEffect(k, to: .track(store.activeCompID, t)) } else { store.addEffect(k, to: .composition(store.activeCompID)) }
        case .effectInstance(let id):
            store.dropEffect(id, onto: track.map { .track(store.activeCompID, $0) } ?? .composition(store.activeCompID), before: nil)
        case .preset(let name):
            store.addInstrument(.synth(name), at: beat, track: track)
        case .kit(let kit):
            store.addInstrument(.kit(kit), at: beat, track: track)
        }
        return true
    }

    private func backgroundGesture(zoom: CGFloat, layout: TrackLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                store.focus = .timeline
                guard hypot(g.translation.width, g.translation.height) > 3 else { return }
                let r = CGRect(x: min(g.startLocation.x, g.location.x), y: min(g.startLocation.y, g.location.y),
                               width: abs(g.translation.width), height: abs(g.translation.height))
                marquee = r
                // Select clips intersecting the rubber band.
                let b0 = Double((r.minX + scrollX) / zoom), b1 = Double((r.maxX + scrollX) / zoom)
                let t0 = layout.index(atY: r.minY + scrollY) ?? 0, t1 = layout.index(atY: r.maxY + scrollY) ?? comp.tracks.count
                var sel: Set<UUID> = []
                for (ti, t) in comp.tracks.enumerated() where ti >= t0 && ti <= t1 {
                    for c in t.clips where c.end > b0 && c.start < b1 { sel.insert(c.id) }
                }
                store.selectedClips = sel
            }
            .onEnded { g in
                defer { marquee = nil }
                guard hypot(g.translation.width, g.translation.height) <= 3 else { return }
                let beat = Double((g.location.x + scrollX) / zoom)
                let now = Date()
                if now.timeIntervalSince(lastClick) < 0.35 {
                    // Double-click on an empty lane: draw a new pattern there (like FL Studio).
                    if let t = trackID(atY: g.location.y) {
                        store.createPatternClip(kind: .notes, at: store.snapBeat(beat, disable: false), track: t)
                    }
                    lastClick = .distantPast
                    return
                }
                lastClick = now
                store.selectedClips = []
                store.selectedKeyframes = []
                store.inspector = .composition(store.activeCompID)
                store.seek(store.snapBeat(beat, disable: NSEvent.modifierFlags.contains(.command)))
            }
    }
}

struct LaneBackground: View {
    @Environment(Store.self) private var store
    let comp: Composition
    let layout: TrackLayout
    let scrollX: CGFloat
    let scrollY: CGFloat

    var body: some View {
        let zoom = CGFloat(store.zoom)
        let th = store.trackHeight
        let bpb = Double(store.project.beatsPerBar)
        let grid = store.gridBeats()
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg))
            for i in comp.tracks.indices {
                let y = layout.top(i) - scrollY, h = layout.heights[i]
                guard y + h >= 0 && y <= size.height else { continue }
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: th)), with: .color(i % 2 == 0 ? Theme.lane : Theme.laneAlt))
                if h > th {
                    // Keyframe rows sit on a slightly darker strip under their layer.
                    ctx.fill(Path(CGRect(x: 0, y: y + th, width: size.width, height: h - th)), with: .color(Color.black.opacity(0.22)))
                }
                ctx.fill(Path(CGRect(x: 0, y: y + h - 1, width: size.width, height: 1)), with: .color(Theme.border))
            }
            // Loop region tint (hidden until there's something to loop).
            if store.loopEnabled && !comp.tracks.allSatisfy({ $0.clips.isEmpty }) {
                let x0 = CGFloat(store.loopStart) * zoom - scrollX, x1 = CGFloat(store.loopEnd) * zoom - scrollX
                ctx.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)), with: .color(Theme.loopRegion.opacity(0.05)))
            }
            // Grid.
            let b0 = Double(scrollX / zoom), b1 = Double((scrollX + size.width) / zoom)
            let minorStep = grid > 0 ? grid : (Double(zoom) >= 12 ? 1 : bpb)
            var b = floor(b0 / minorStep) * minorStep
            while b <= b1 {
                let x = CGFloat(b) * zoom - scrollX
                let isBar = abs(b / bpb - (b / bpb).rounded()) < 1e-6
                let isBeat = abs(b - b.rounded()) < 1e-6
                let color = isBar ? Theme.gridBar : (isBeat ? Theme.gridBeat : Theme.gridSub)
                if isBar || CGFloat(minorStep) * zoom >= 6 {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(color))
                }
                b += minorStep
            }
            // Beyond the composition end.
            let endX = CGFloat(comp.length) * zoom - scrollX
            if endX < size.width {
                ctx.fill(Path(CGRect(x: max(0, endX), y: 0, width: size.width - max(0, endX), height: size.height)),
                         with: .color(Color.black.opacity(0.4)))
                ctx.fill(Path(CGRect(x: endX, y: 0, width: 1.5, height: size.height)), with: .color(Theme.accent.opacity(0.6)))
            }
        }
    }
}

// MARK: - Clip

struct ClipView: View {
    @Environment(Store.self) private var store
    let clip: Clip
    let trackIndex: Int
    var layout: TrackLayout?

    private enum Mode { case move, trimLeft, trimRight }
    private struct DragInfo {
        var mode: Mode
        var origin: Project
        var clip: Clip
        var ids: Set<UUID>
    }

    @State private var drag: DragInfo?
    @State private var pressed = false
    @State private var lastClick = Date.distantPast
    @State private var dropTarget = false
    @State private var hoverZone: Mode?

    var body: some View {
        let asset = store.project.asset(clip.assetID)
        let color = Theme.label(asset?.colorIndex ?? 0)
        let selected = store.selectedClips.contains(clip.id)
        let L = store.project.sourceLength(of: clip.assetID)
        let segs = clipSegments(offset: clip.offset, length: clip.length, loops: clip.loops, sourceLength: L)
        let uses = store.project.usageCount(of: clip.assetID)
        // Linked copies light up when one of them is selected, or while you hover a clip's link icon.
        let showLink = uses > 1 && (LinkHover.shared.asset == clip.assetID || (!selected && isLinkedToSelection))
        let isComp = asset?.kind == .composition
        let drawer = SourceDrawer(project: store.project)

        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pxPerBeat = w / CGFloat(max(clip.length, 1e-6))
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let header: CGFloat = 15
                    for s in segs {
                        let x0 = CGFloat(s.t0) * pxPerBeat, x1 = CGFloat(s.t1) * pxPerBeat
                        let r = CGRect(x: x0, y: 0, width: max(0, x1 - x0), height: size.height)
                        if s.empty {
                            ctx.fill(Path(r), with: .color(color.opacity(0.08)))
                            var hctx = ctx
                            hctx.clip(to: Path(r))
                            hctx.stroke(Hatch(spacing: 7).path(in: r), with: .color(color.opacity(0.25)), lineWidth: 1)
                            continue
                        }
                        let loopTint = s.loopStart || (clip.loops && s.t0 > 0)
                        ctx.fill(Path(r), with: .color(color.opacity(loopTint ? 0.32 : 0.42)))
                        ctx.fill(Path(CGRect(x: x0, y: 0, width: r.width, height: header)), with: .color(color.opacity(loopTint ? 0.6 : 0.85)))
                        drawer.draw(ctx, assetID: clip.assetID,
                                    rect: CGRect(x: x0 + 1, y: header + 3, width: max(0, r.width - 2), height: size.height - header - 6),
                                    from: s.s0, to: s.s1, color: Color.white)
                        if s.loopStart {
                            // Notch marks each repeat of a looped clip.
                            ctx.fill(Path { p in
                                p.move(to: CGPoint(x: x0, y: 0)); p.addLine(to: CGPoint(x: x0 + 5, y: 0)); p.addLine(to: CGPoint(x: x0, y: 6)); p.closeSubpath()
                            }, with: .color(.black.opacity(0.6)))
                            ctx.fill(Path(CGRect(x: x0, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.45)))
                        }
                    }
                }
                HStack(spacing: 3) {
                    if isComp { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 8)) }
                    Text(asset?.name ?? "Missing").font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    if uses > 1 {
                        Image(systemName: "link").font(.system(size: 8))
                            .padding(2).contentShape(Rectangle())
                            .onHover { inside in
                                if inside { LinkHover.shared.asset = clip.assetID } else if LinkHover.shared.asset == clip.assetID { LinkHover.shared.asset = nil }
                            }
                            .help("Linked: used \(uses) times. Select it to see the other copies.")
                    }
                    if clip.loops { Image(systemName: "repeat").font(.system(size: 8)) }
                    if !clip.effects.isEmpty { Image(systemName: "fx").font(.system(size: 8)) }
                    if clip.mute { Image(systemName: "speaker.slash.fill").font(.system(size: 8)) }
                }
                .foregroundStyle(Color.black.opacity(0.8))
                .padding(.horizontal, 4)
                .frame(width: w, height: 15, alignment: .leading)
                .clipped()
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Theme.selection : (dropTarget ? Theme.accent : Color.black.opacity(0.5)),
                                                              lineWidth: selected || dropTarget ? 1.5 : 1))
            .opacity(clip.mute ? 0.45 : 1)
            .overlay {
                if showLink {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.selection.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                // Only at an edge: a small grip showing it can be dragged to resize.
                if let z = hoverZone, z != .move {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.85))
                        .frame(width: 3).padding(.vertical, 3).padding(.horizontal, 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: z == .trimLeft ? .leading : .trailing)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(bodyGesture())
            .overlay(alignment: .leading) { edgeHandle(.trimLeft, width: edgeWidth(w)) }
            .overlay(alignment: .trailing) { edgeHandle(.trimRight, width: edgeWidth(w)) }
            // One hover area over the whole clip, edges included, so crossing an edge isn't "leaving" the clip.
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let e = edgeWidth(w)
                    let zone: Mode = p.x <= e ? .trimLeft : (p.x >= w - e ? .trimRight : .move)
                    if zone != hoverZone { hoverZone = zone }
                    (zone == .move ? NSCursor.arrow : NSCursor.resizeLeftRight).set()
                case .ended:
                    hoverZone = nil
                    NSCursor.arrow.set()
                }
            }
        }
        .contextMenu { menu(asset: asset) }
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { payload, loc in
                switch payload {
                case .effect(let k): store.addEffect(k, to: .clip(store.activeCompID, clip.id))
                case .effectInstance(let id): store.dropEffect(id, onto: .clip(store.activeCompID, clip.id), before: nil)
                case .preset(let name): store.replaceInstrument(ofAsset: clip.assetID, with: .synth(name))
                case .kit(let k): store.replaceInstrument(ofAsset: clip.assetID, with: .kit(k))
                case .asset(let id):
                    let beat = store.snapBeat(clip.start + Double(loc.x) / store.zoom)
                    let track = store.activeComp?.tracks[safe: trackIndex]?.id
                    store.addClip(asset: id, at: beat, track: track)
                }
                return true
            },
            onHover: { dropTarget = $0 != nil }))
        .help(clip.loops ? "Looping clip. Option-drag the right edge to extend." : "Drag to move, drag edges to trim, Option-drag right edge to loop, double-click to open")
    }

    /// True when another clip of the same source is selected in this composition.
    private var isLinkedToSelection: Bool {
        guard !store.selectedClips.isEmpty, let comp = store.activeComp else { return false }
        return comp.tracks.contains { t in t.clips.contains { $0.id != clip.id && $0.assetID == clip.assetID && store.selectedClips.contains($0.id) } }
    }

    /// Edge grab zones shrink on narrow (zoomed-out) clips so the middle stays draggable.
    private func edgeWidth(_ w: CGFloat) -> CGFloat { max(3, min(8, w * 0.25)) }

    private func edgeHandle(_ mode: Mode, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: width)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in changed(g, mode: mode) }
                .onEnded { _ in ended() })
    }

    private func bodyGesture() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { g in changed(g, mode: .move) }
            .onEnded { g in
                let wasClick = hypot(g.translation.width, g.translation.height) < 3
                ended()
                if wasClick {
                    let now = Date()
                    if now.timeIntervalSince(lastClick) < 0.35 {
                        store.open(asset: clip.assetID, clip: clip.id)
                        lastClick = .distantPast
                    } else {
                        lastClick = now
                    }
                }
            }
    }

    private func select() {
        store.focus = .timeline
        let shift = NSEvent.modifierFlags.contains(.shift)
        if shift {
            if store.selectedClips.contains(clip.id) { store.selectedClips.remove(clip.id) } else { store.selectedClips.insert(clip.id) }
        } else if !store.selectedClips.contains(clip.id) {
            store.selectedClips = [clip.id]
        }
        store.inspector = .clip(store.activeCompID, clip.id)
    }

    private func changed(_ g: DragGesture.Value, mode: Mode) {
        let mods = NSEvent.modifierFlags
        if drag == nil {
            if !pressed {
                pressed = true
                select()
            }
            // Don't start moving (or Option-duplicating) until the mouse actually moves.
            if mode == .move && hypot(g.translation.width, g.translation.height) < 3 { return }
            var origin = store.project
            var ids = store.selectedClips.contains(clip.id) ? store.selectedClips : [clip.id]
            if mode != .move { ids = [clip.id] }
            if mode == .move && mods.contains(.option) && hypot(g.translation.width, g.translation.height) > 2 {
                // Option-drag duplicates: leave linked copies behind and drag the originals.
                let cid = store.activeCompID
                store.live { p in
                    p.updateComposition(cid) { c in
                        for ti in c.tracks.indices {
                            for k in c.tracks[ti].clips where ids.contains(k.id) {
                                var copy = k
                                copy.id = UUID()
                                c.tracks[ti].clips.append(copy)
                            }
                        }
                    }
                }
                origin = store.project
            }
            drag = DragInfo(mode: mode, origin: origin, clip: clip, ids: ids)
        }
        guard let d = drag, hypot(g.translation.width, g.translation.height) >= 2 || d.mode != .move else { return }
        let free = mods.contains(.command)
        let dx = Double(g.translation.width) / store.zoom
        // Never force a short clip to grow just because the grid is coarse.
        let minLen = free ? 1.0 / 64 : min(max(store.gridBeats(), 1.0 / 16), d.clip.length)
        let L = store.project.sourceLength(of: d.clip.assetID)
        switch d.mode {
        case .move:
            let newStart = store.snapBeat(d.clip.start + dx, disable: free)
            var dt = Int((g.translation.height / store.trackHeight).rounded())
            if let layout {
                // Layers can be taller when their keyframe rows are open: find the layer under the pointer.
                let y = layout.top(trackIndex) + store.trackHeight / 2 + g.translation.height
                dt = (layout.index(atY: y) ?? (y < 0 ? 0 : layout.tops.count - 1)) - trackIndex
            }
            store.moveClips(d.origin, ids: d.ids, deltaBeats: newStart - d.clip.start, deltaTracks: dt)
        case .trimRight:
            let loop = mods.contains(.option)
            let newEnd = store.snapBeat(d.clip.end + dx, disable: free)
            let length = max(minLen, newEnd - d.clip.start)
            store.updateClip(d.clip.id, live: true) { c in
                c.length = length
                if loop { c.loops = true }
            }
        case .trimLeft:
            var newStart = store.snapBeat(d.clip.start + dx, disable: free)
            newStart = min(newStart, d.clip.end - minLen)
            if !d.clip.loops { newStart = max(newStart, d.clip.start - d.clip.offset) }
            newStart = max(0, newStart)
            var off = d.clip.offset + (newStart - d.clip.start)
            if d.clip.loops { off = ((off.truncatingRemainder(dividingBy: L)) + L).truncatingRemainder(dividingBy: L) }
            let o = max(0, off)
            store.updateClip(d.clip.id, live: true) { c in
                c.start = newStart
                c.length = d.clip.end - newStart
                c.offset = o
            }
        }
    }

    private func ended() {
        drag = nil
        pressed = false
        store.endGesture()
    }

    @ViewBuilder private func menu(asset: Asset?) -> some View {
        Button("Open \(asset?.kind.label ?? "Source")") { store.open(asset: clip.assetID) }
        Button("Duplicate") { select(); store.duplicateSelectedClips() }
        Button("Make Unique") { store.makeUnique(clip.id) }
        Button("Split at Playhead") { select(); store.splitSelectedClips(at: store.transport.position) }
        Button("Pre-compose") { select(); store.precomposeSelection() }
        let problem = store.mergeProblem(store.selectedClips)
        Button("Merge into One Clip") { store.mergeSelectedClips() }
            .disabled(problem != nil)
        if let problem { Text(problem).foregroundStyle(.secondary) }
        Divider()
        Button("Fade In") { store.addFade(clip: clip.id, fadeIn: true) }
        Button("Fade Out") { store.addFade(clip: clip.id, fadeIn: false) }
        Divider()
        Toggle("Loop Past End", isOn: Binding(get: { clip.loops }, set: { v in store.updateClip(clip.id) { $0.loops = v } }))
        Toggle("Mute Clip", isOn: Binding(get: { clip.mute }, set: { v in store.updateClip(clip.id) { $0.mute = v } }))
        Button("Fit Length to Source") {
            let L = store.project.sourceLength(of: clip.assetID)
            store.updateClip(clip.id) { $0.length = max(0.25, L - $0.offset); $0.loops = false }
        }
        Divider()
        Button("Delete", role: .destructive) { select(); store.deleteSelectedClips() }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

/// The single obvious next step when a composition is empty.
struct EmptyTimelineCard: View {
    @Environment(Store.self) private var store
    let firstEver: Bool

    var body: some View {
        VStack(spacing: 12) {
            Button {
                store.workspace.reveal(.browser)
                store.browserTab = .instruments
                store.focusBrowserSearch += 1
            } label: {
                Label("Add an instrument", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            Text("Pick drums or a synth in the Browser on the left. Click to hear it, double-click to add it.")
                .font(Theme.small).foregroundStyle(Theme.textDim)
            if firstEver {
                Button("Or open the demo song") { store.openDemo() }
                    .buttonStyle(.link)
                    .font(Theme.small)
            }
        }
        .multilineTextAlignment(.center)
        .padding(30)
    }
}

/// Which source's link icon the pointer is over, so every linked copy can outline itself.
@Observable final class LinkHover {
    static let shared = LinkHover()
    var asset: AssetID?
}
