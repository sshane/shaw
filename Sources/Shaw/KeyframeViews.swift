import ShawCore
import SwiftUI

// MARK: - Effect Controls row with a stopwatch

/// A parameter row in Effect Controls, with After Effects' stopwatch (keyframing on/off)
/// and, once keyframed, ◀ ◆ ▶ to step between keyframes or add/remove one at the playhead.
struct EffectParamRow: View {
    @Environment(Store.self) private var store
    let host: EffectHost
    let effect: Effect
    let def: ParamDef

    var body: some View {
        let animated = effect.isAnimated(def.id)
        // Only animated rows follow the playhead, so the rest of the panel stays still while playing.
        let now = animated ? store.keyframeTime(for: host) : 0
        let value = effect.value(of: def, at: now)
        HStack(spacing: 3) {
            Button { store.toggleAnimation(host, effect: effect.id, param: def.id) } label: {
                Image(systemName: "stopwatch").font(.system(size: 10, weight: animated ? .bold : .regular))
                    .foregroundStyle(animated ? Theme.accent : Theme.textFaint)
                    .frame(width: 16, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(animated ? "Stop keyframing (keeps the current value)" : "Keyframe this: changes at the playhead become ◆ keyframes")
            ParamRow(def: def, value: value,
                     onChange: { v in store.setParam(host, effect: effect.id, param: def.id, value: v, live: true) },
                     onEnd: { store.endGesture() })
            if animated {
                HStack(spacing: 0) {
                    navButton("chevron.left", "Previous keyframe") { store.jumpToKeyframe(host, effect: effect.id, param: def.id, forward: false) }
                    let onKey = store.hasKeyframeAtPlayhead(effect, param: def.id, host: host)
                    navButton(onKey ? "diamond.fill" : "diamond", onKey ? "Remove the keyframe at the playhead" : "Add a keyframe at the playhead") {
                        store.toggleKeyframeAtPlayhead(host, effect: effect.id, param: def.id)
                    }
                    navButton("chevron.right", "Next keyframe") { store.jumpToKeyframe(host, effect: effect.id, param: def.id, forward: true) }
                }
            }
        }
    }

    private func navButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 8, weight: .semibold))
                .frame(width: 13, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
        .help(help)
    }
}

// MARK: - Timeline: row label

struct KeyframeRowHeader: View {
    @Environment(Store.self) private var store
    let prop: AnimatedProperty

    var body: some View {
        let e = store.effect(prop.effectID, in: prop.host)
        let def = e.flatMap { EffectRegistry.descriptor($0.kind)?.params.first { $0.id == prop.paramID } }
        HStack(spacing: 5) {
            Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(Theme.accent)
            Text(prop.label).font(Theme.tiny).foregroundStyle(Theme.textDim).lineLimit(1)
            Spacer(minLength: 2)
            if let e, let def {
                Text(def.format(e.value(of: def, at: store.keyframeTime(for: prop.host))))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.leading, 22).padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22))
        .contentShape(Rectangle())
        .onTapGesture {
            switch prop.host {
            case .clip(let c, let k): store.inspector = .clip(c, k)
            case .track(let c, let t): store.inspector = .track(c, t)
            case .composition(let c): store.inspector = .composition(c)
            }
            store.workspace.reveal(.inspector)
        }
        .help("Click to show this effect in Effect Controls")
    }
}

// MARK: - Timeline: the ◆ lane

struct KeyframeLane: View {
    @Environment(Store.self) private var store
    let prop: AnimatedProperty
    let scrollX: CGFloat
    let width: CGFloat

    private struct DragInfo {
        var key: UUID?
        var time: Double = 0   // host time at drag start
        var norm: Double = 0   // normalized value at drag start
        var axis: Int = 0      // 0 undecided, 1 time, 2 value
    }
    @State private var drag: DragInfo?
    @State private var lastClick: (time: Date, key: UUID?) = (.distantPast, nil)
    @State private var editing: UUID?
    @State private var editText = ""
    @State private var editRect: CGRect = .zero

    private var zoom: CGFloat { CGFloat(store.zoom) }
    private let h = TrackLayout.propRowHeight

    private var effect: Effect? { store.effect(prop.effectID, in: prop.host) }
    private var def: ParamDef? { effect.flatMap { EffectRegistry.descriptor($0.kind)?.params.first { $0.id == prop.paramID } } }
    private var keys: [Keyframe] { effect?.keyframes[prop.paramID] ?? [] }

    private func x(_ hostTime: Double) -> CGFloat { CGFloat(prop.origin + hostTime) * zoom - scrollX }
    private func y(_ value: Double) -> CGFloat {
        guard let def else { return h / 2 }
        return h - 4 - CGFloat(def.normalized(value)) * (h - 8)
    }

    var body: some View {
        let sel = store.selectedKeyframes
        let color = Theme.accent
        Canvas { ctx, size in
            guard let def else { return }
            let s0 = CGFloat(prop.span.lowerBound) * zoom - scrollX, s1 = CGFloat(prop.span.upperBound) * zoom - scrollX
            ctx.fill(Path(CGRect(x: s0, y: 1, width: max(0, s1 - s0), height: size.height - 2)), with: .color(Color.white.opacity(0.04)))
            // Value line: held before the first and after the last keyframe, straight between them.
            var path = Path()
            if let first = keys.first, let last = keys.last {
                path.move(to: CGPoint(x: max(s0, -10), y: y(first.value)))
                for k in keys { path.addLine(to: CGPoint(x: x(k.time), y: y(k.value))) }
                if def.choices != nil {
                    // Choice settings step rather than glide.
                    path = Path()
                    path.move(to: CGPoint(x: max(s0, -10), y: y(first.value)))
                    for (i, k) in keys.enumerated() {
                        if i > 0 { path.addLine(to: CGPoint(x: x(k.time), y: y(keys[i - 1].value))) }
                        path.addLine(to: CGPoint(x: x(k.time), y: y(k.value)))
                    }
                }
                path.addLine(to: CGPoint(x: min(s1, size.width + 10), y: y(last.value)))
            }
            ctx.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1.5)
            for k in keys {
                let c = CGPoint(x: x(k.time), y: y(k.value))
                guard c.x > -10 && c.x < size.width + 10 else { continue }
                let d = Path { p in
                    p.move(to: CGPoint(x: c.x, y: c.y - 5)); p.addLine(to: CGPoint(x: c.x + 5, y: c.y))
                    p.addLine(to: CGPoint(x: c.x, y: c.y + 5)); p.addLine(to: CGPoint(x: c.x - 5, y: c.y)); p.closeSubpath()
                }
                let isSel = sel.contains(k.id)
                ctx.fill(d, with: .color(isSel ? Color.yellow : Color.white))
                ctx.stroke(d, with: .color(.black.opacity(0.6)), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in changed(g) }
            .onEnded { g in ended(g) })
        .popover(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
                 attachmentAnchor: .rect(.rect(editRect)), arrowEdge: .top) {
            HStack(spacing: 6) {
                Text(def?.name ?? "").font(Theme.small).foregroundStyle(Theme.textDim)
                TextField("Value", text: $editText)
                    .frame(width: 80)
                    .onSubmit { commitEdit() }
                Button("Set") { commitEdit() }
            }
            .padding(10)
        }
        .help("◆ keyframes: drag to move (snaps to the grid, ⌘ for free), drag up/down to change the value, double-click a ◆ to type a value, double-click the row to add one, Delete removes selected")
    }

    private func hit(_ p: CGPoint) -> Keyframe? {
        keys.last { k in abs(x(k.time) - p.x) <= 7 && abs(y(k.value) - p.y) <= 9 }
    }

    private func changed(_ g: DragGesture.Value) {
        store.focus = .timeline
        guard let def else { return }
        if drag == nil {
            if let k = hit(g.startLocation) {
                if NSEvent.modifierFlags.contains(.shift) {
                    if store.selectedKeyframes.contains(k.id) { store.selectedKeyframes.remove(k.id) } else { store.selectedKeyframes.insert(k.id) }
                } else if !store.selectedKeyframes.contains(k.id) {
                    store.selectedKeyframes = [k.id]
                }
                drag = DragInfo(key: k.id, time: k.time, norm: def.normalized(k.value))
            } else {
                drag = DragInfo(key: nil)
            }
        }
        guard var d = drag, let key = d.key else { return }
        let dx = g.translation.width, dy = g.translation.height
        if d.axis == 0 && hypot(dx, dy) > 4 {
            // Lock to the direction you start dragging in, so moving a ◆ in time doesn't nudge its value.
            d.axis = NSEvent.modifierFlags.contains(.command) ? 3 : (abs(dx) >= abs(dy) ? 1 : 2)
            drag = d
        }
        guard d.axis != 0 else { return }
        var t = d.time, v = keys.first { $0.id == key }?.value ?? 0
        if d.axis == 1 || d.axis == 3 {
            let comp = prop.origin + d.time + Double(dx / zoom)
            let snapped = d.axis == 3 ? comp : store.snapBeat(comp)
            t = min(max(0, snapped - prop.origin), prop.span.upperBound - prop.origin)
        }
        if d.axis == 2 || d.axis == 3 {
            v = def.value(fromNormalized: d.norm - Double(dy / (h - 8)))
        }
        store.moveKeyframe(prop, key: key, time: t, value: v)
    }

    private func ended(_ g: DragGesture.Value) {
        let wasClick = hypot(g.translation.width, g.translation.height) <= 3
        let d = drag
        drag = nil
        store.endGesture()
        guard wasClick, let def else { return }
        let now = Date()
        let isDouble = now.timeIntervalSince(lastClick.time) < 0.35 && lastClick.key == d?.key
        lastClick = isDouble ? (.distantPast, nil) : (now, d?.key)
        if let key = d?.key {
            if isDouble, let k = keys.first(where: { $0.id == key }) {
                // Double-click a ◆: type an exact value.
                editRect = CGRect(x: x(k.time) - 5, y: y(k.value) - 5, width: 10, height: 10)
                editText = def.format(k.value).components(separatedBy: " ").first ?? ""
                editing = key
            }
            return
        }
        if isDouble {
            // Double-click the row: add a ◆ there, at the value under the pointer.
            let comp = store.snapBeat(Double((g.location.x + scrollX) / zoom))
            guard prop.span.contains(comp) else { return }
            let norm = Double((h - 4 - g.location.y) / (h - 8))
            if let id = store.addKeyframe(prop, time: comp - prop.origin, value: def.value(fromNormalized: norm)) {
                store.selectedKeyframes = [id]
            }
        } else {
            store.selectedKeyframes = []
        }
    }

    private func commitEdit() {
        guard let key = editing, let def else { editing = nil; return }
        let digits = editText.filter { "0123456789.-".contains($0) }
        if var v = Double(digits) {
            if def.unit == .percent { v /= 100 }
            if case .hz = def.unit, editText.lowercased().contains("k") { v *= 1000 }
            if editText.lowercased().contains("inf") { v = def.min }
            store.setKeyframeValue(prop, key: key, value: def.clamp(v))
        } else if editText.lowercased().contains("inf") {
            store.setKeyframeValue(prop, key: key, value: def.min)
        }
        editing = nil
    }
}
