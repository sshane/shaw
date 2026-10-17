import AppKit
import ShawCore
import SwiftUI

/// After Effects-style "scrubby" number: drag left/right to change, click to type.
struct DragNumber: View {
    let value: Double
    var range: ClosedRange<Double> = -Double.infinity...Double.infinity
    var step: Double = 1
    var sensitivity: Double = 1 // value units per pixel
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var parse: (String) -> Double? = { Double($0.trimmingCharacters(in: .whitespaces)) }
    var color: Color = Theme.accent
    var font: Font = Theme.mono
    let onChange: (Double) -> Void
    var onEnd: () -> Void = {}

    /// Point size of the text while typing a value.
    var editSize: CGFloat = 11

    @State private var dragStart: Double?
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        Group {
            if editing {
                // A real NSTextField that takes focus and selects its text itself. SwiftUI focus
                // sometimes failed here, and the select-all then hit another field (Project search).
                SelectAllField(text: text, fontSize: editSize,
                               onCommit: { t in text = t; commit() },
                               onCancel: { editing = false })
                    .frame(minWidth: 40)
            } else {
                Text(format(value))
                    .font(font)
                    .foregroundStyle(color)
                    .underline(true, pattern: .dot, color: color.opacity(0.5))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        text = format(value).components(separatedBy: " ").first ?? ""
                        editing = true
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                if dragStart == nil { dragStart = value }
                                let fine = NSEvent.modifierFlags.contains(.command) ? 0.1 : (NSEvent.modifierFlags.contains(.shift) ? 10 : 1)
                                var v = dragStart! + Double(g.translation.width - g.translation.height) * sensitivity * fine
                                if step > 0 { v = (v / step).rounded() * step }
                                onChange(min(range.upperBound, max(range.lowerBound, v)))
                            }
                            .onEnded { _ in dragStart = nil; onEnd() }
                    )
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            }
        }
    }

    private func commit() {
        if let v = parse(text) { onChange(min(range.upperBound, max(range.lowerBound, v))); onEnd() }
        editing = false
    }
}

/// Text field for typing a number: focused with its text selected the moment it appears.
/// Enter or clicking away commits; Esc cancels.
struct SelectAllField: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 11
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: text)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        f.textColor = .white
        f.delegate = context.coordinator
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        DispatchQueue.main.async {
            guard let w = f.window else { return }
            w.makeFirstResponder(f)
            f.currentEditor()?.selectAll(nil)
        }
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SelectAllField
        var done = false
        init(_ parent: SelectAllField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                done = true
                parent.onCancel()
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                finish(control)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let c = obj.object as? NSControl { finish(c) }
        }

        private func finish(_ control: NSControl) {
            guard !done else { return }
            done = true
            parent.onCommit(control.stringValue)
            // Hand the keyboard back to Shaw (Space plays again).
            control.window?.makeFirstResponder(nil)
        }
    }
}

/// A labelled parameter control generated from a `ParamDef`.
struct ParamRow: View {
    let def: ParamDef
    let value: Double
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(def.name)
                .font(Theme.small)
                .foregroundStyle(Theme.textDim)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { onChange(def.defaultValue); onEnd() }
                .help("Double-click to reset")
            if let choices = def.choices {
                Menu {
                    ForEach(choices.indices, id: \.self) { i in
                        Button(choices[i]) { onChange(Double(i)); onEnd() }
                    }
                } label: {
                    Text(def.format(value)).font(Theme.small).foregroundStyle(Theme.accent)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer(minLength: 0)
            } else {
                ParamSlider(def: def, value: value, onChange: onChange, onEnd: onEnd)
                DragNumber(value: value, range: def.min...def.max, step: 0,
                           sensitivity: (def.max - def.min) / 300,
                           format: { def.format($0) },
                           parse: { s in
                               let d = Double(s.filter { "0123456789.-".contains($0) })
                               if def.unit == .percent, let d { return d / 100 }
                               if case .hz = def.unit, s.lowercased().contains("k"), let d { return d * 1000 }
                               return d
                           },
                           onChange: onChange, onEnd: onEnd)
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .frame(height: 20)
    }
}

struct ParamSlider: View {
    let def: ParamDef
    let value: Double
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { geo in
            let n = def.normalized(value)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.control).frame(height: 4)
                Capsule().fill(Theme.accent.opacity(0.8)).frame(width: max(0, geo.size.width * n), height: 4)
                Circle().fill(Theme.text).frame(width: 9, height: 9).offset(x: geo.size.width * n - 4.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onChange(def.value(fromNormalized: g.location.x / max(1, geo.size.width))) }
                    .onEnded { _ in onEnd() }
            )
        }
        .frame(height: 16)
    }
}

/// Compact horizontal fader used in track headers.
struct MiniFader: View {
    let value: Double   // dB
    var range: ClosedRange<Double> = -60...6
    var width: CGFloat = 60
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        let n = (min(range.upperBound, max(range.lowerBound, value)) - range.lowerBound) / (range.upperBound - range.lowerBound)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.control)
            RoundedRectangle(cornerRadius: 2).fill(Theme.textDim.opacity(0.6)).frame(width: width * n)
            // 0 dB tick
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1)
                .offset(x: width * (0 - range.lowerBound) / (range.upperBound - range.lowerBound))
        }
        .frame(width: width, height: 6)
        .contentShape(Rectangle().inset(by: -5))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let n = min(1, max(0, g.location.x / width))
                    var v = range.lowerBound + n * (range.upperBound - range.lowerBound)
                    if abs(v) < 0.8 { v = 0 } // detent at unity
                    onChange(v)
                }
                .onEnded { _ in onEnd() }
        )
        .onTapGesture(count: 2) { onChange(0); onEnd() }
        .help(String(format: "%.1f dB. Double-click for 0 dB.", value))
    }
}

/// Small rotary pan/param knob.
struct Knob: View {
    let value: Double // -1...1 for pan, or normalized
    var bipolar = true
    var size: CGFloat = 16
    let onChange: (Double) -> Void
    let onEnd: () -> Void
    @State private var start: Double?

    var body: some View {
        let n = bipolar ? (value + 1) / 2 : value
        ZStack {
            Circle().stroke(Theme.control, lineWidth: 2.5)
            Circle()
                .trim(from: bipolar ? min(0.5, n) * 0.75 : 0, to: bipolar ? max(0.5, n) * 0.75 : n * 0.75)
                .stroke(Theme.accent, lineWidth: 2.5)
                .rotationEffect(.degrees(135))
            Rectangle().fill(Theme.text).frame(width: 1.5, height: size * 0.35)
                .offset(y: -size * 0.2)
                .rotationEffect(.degrees(-135 + n * 270))
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if start == nil { start = value }
                    let span = bipolar ? 2.0 : 1.0
                    let lo = bipolar ? -1.0 : 0
                    onChange(min(lo + span, max(lo, start! - Double(g.translation.height) / 100 * span)))
                }
                .onEnded { _ in start = nil; onEnd() }
        )
        .onTapGesture(count: 2) { onChange(bipolar ? 0 : 0.5); onEnd() }
    }
}

struct LevelMeterView: View {
    let level: Float
    var vertical = false

    var body: some View {
        GeometryReader { geo in
            let db = gainToDb(Double(level))
            let n = CGFloat(max(0, min(1, (db + 48) / 54)))
            let color: Color = db > -0.5 ? .red : (db > -6 ? .yellow : .green)
            ZStack(alignment: vertical ? .bottom : .leading) {
                Rectangle().fill(Color.black.opacity(0.4))
                if vertical {
                    Rectangle().fill(color.opacity(0.85)).frame(height: geo.size.height * n)
                } else {
                    Rectangle().fill(color.opacity(0.85)).frame(width: geo.size.width * n)
                }
            }
        }
    }
}

/// Section header used in sidebars.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

/// Icon for an asset kind.
func assetIcon(_ kind: AssetKind) -> String {
    switch kind {
    case .composition: return "square.stack.3d.up"
    case .audio: return "waveform"
    case .notes: return "pianokeys"
    case .drums: return "circle.grid.3x3.fill"
    }
}

/// Format beats as bars.beats.sixteenths (1-based like every DAW).
func formatPosition(_ beat: Double, beatsPerBar: Int) -> String {
    let b = max(0, beat)
    let bar = Int(b / Double(beatsPerBar)) + 1
    let beatInBar = Int(b.truncatingRemainder(dividingBy: Double(beatsPerBar))) + 1
    let six = Int((b - b.rounded(.down)) * 4) + 1
    return "\(bar).\(beatInBar).\(six)"
}

func formatLength(_ beats: Double, beatsPerBar: Int) -> String {
    let bars = beats / Double(beatsPerBar)
    if bars == bars.rounded() { return "\(Int(bars)) bar\(Int(bars) == 1 ? "" : "s")" }
    return String(format: "%.2f beats", beats)
}

// MARK: - Drag payloads

/// Internal drag-and-drop payloads are plain strings, e.g. "effect:reverb".
enum DragPayload {
    case asset(AssetID)
    case effect(String)
    case preset(String)
    case kit(String)
    /// An effect already on something (dragged by its title in Effect Controls).
    case effectInstance(UUID)

    var string: String {
        switch self {
        case .asset(let id): return "shaw-asset:\(id.uuidString)"
        case .effect(let k): return "shaw-effect:\(k)"
        case .preset(let p): return "shaw-preset:\(p)"
        case .kit(let k): return "shaw-kit:\(k)"
        case .effectInstance(let id): return "shaw-fx:\(id.uuidString)"
        }
    }

    init?(_ s: String) {
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "shaw-asset": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .asset(id)
        case "shaw-effect": self = .effect(parts[1])
        case "shaw-preset": self = .preset(parts[1])
        case "shaw-kit": self = .kit(parts[1])
        case "shaw-fx": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .effectInstance(id)
        default: return nil
        }
    }
}

/// Drop handler that understands Shaw payloads and audio files from Finder.
struct ShawDropDelegate: DropDelegate {
    var onPayload: (DragPayload, CGPoint) -> Bool
    var onFiles: (([URL], CGPoint) -> Void)? = nil
    var onHover: ((CGPoint?) -> Void)? = nil
    var accepts: ((DragPayload) -> Bool)? = nil

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.utf8PlainText, .plainText]) || (onFiles != nil && info.hasItemsConforming(to: [.fileURL]))
    }

    func dropEntered(info: DropInfo) { onHover?(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHover?(info.location)
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { onHover?(nil) }

    func performDrop(info: DropInfo) -> Bool {
        onHover?(nil)
        let loc = info.location
        if let onFiles, info.hasItemsConforming(to: [.fileURL]) {
            let providers = info.itemProviders(for: [.fileURL])
            var urls: [URL] = []
            let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { urls.append(url) } }
                    group.leave()
                }
            }
            group.notify(queue: .main) { onFiles(urls, loc) }
            return true
        }
        guard let p = info.itemProviders(for: [.utf8PlainText, .plainText]).first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let payload = DragPayload(s) else { return }
            DispatchQueue.main.async { _ = onPayload(payload, loc) }
        }
        return true
    }
}

extension View {
    func shawDraggable(_ payload: DragPayload, preview: String) -> some View {
        onDrag {
            NSItemProvider(object: payload.string as NSString)
        } preview: {
            Text(preview)
                .font(Theme.small)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.8)))
        }
    }
}
