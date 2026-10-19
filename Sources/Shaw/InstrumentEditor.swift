import ShawCore
import SwiftUI

/// The Instrument Editor window: build a sound by stacking oscillators, then shape it with the
/// filter, envelope, and LFO. Every change plays live on the pattern you opened it from.
struct InstrumentEditorView: View {
    static let windowTitle = "Instrument Editor"
    static let cardHeight: CGFloat = 200
    @Environment(Store.self) private var store
    /// Sub and noise cards stay visible while you drag their level down to zero.
    @State private var shownExtras: Set<String> = []

    var body: some View {
        Group {
            if let id = store.instrumentEditorAsset, let a = store.project.asset(id),
               case .notes(let pat) = a.content, pat.instrument.isSynth {
                editor(id, a, pat.instrument)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 28)).foregroundStyle(Theme.textFaint)
                    Text("Select a synth pattern and click Edit Instrument, or click + under My Instruments in the Browser to start from scratch.")
                        .font(Theme.small).foregroundStyle(Theme.textDim).multilineTextAlignment(.center).frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: Layout

    private func editor(_ id: AssetID, _ a: Asset, _ inst: Instrument) -> some View {
        let p = SynthParams.defs.defaults().merging(inst.params) { $1 }
        return VStack(spacing: 0) {
            header(id, a)
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WaveformPreview(params: p)
                        .frame(height: 86)
                        .panelBox()
                    oscillators(id, p)
                    HStack(alignment: .top, spacing: 12) {
                        filter(id, p).frame(maxWidth: .infinity)
                        envelope(id, p).frame(maxWidth: .infinity)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        lfo(id, p).frame(maxWidth: .infinity)
                        character(id, p).frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
            }
        }
        .onChange(of: store.instrumentEditorAsset) { _, _ in shownExtras = [] }
    }

    private func header(_ id: AssetID, _ a: Asset) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.label(a.colorIndex)).frame(width: 10, height: 12)
                    InstrumentMenu(assetID: id)
                    if Store.baseName(a.name) != store.instrumentName(id) {
                        Text("on \(a.name)").font(Theme.small).foregroundStyle(Theme.textFaint)
                    }
                }
                InstrumentActions(assetID: id, showEdit: false)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button { store.auditionPattern(id) } label: { Label("Play", systemImage: "play.fill") }
                    .controlSize(.small)
                    .help("Play a short phrase with this sound")
                Text("Or play notes with your keyboard: A S D F…").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            }
        }
        .padding(12)
    }

    // MARK: Oscillators

    private func oscillators(_ id: AssetID, _ p: [String: Double]) -> some View {
        let levels = OscillatorLevels.levels(p)
        let on = [true, (p["on2"] ?? 1) > 0.5, (p["on3"] ?? 0) > 0.5, (p["on4"] ?? 0) > 0.5]
        let showSub = (p["sub"] ?? 0) > 0 || shownExtras.contains("sub")
        let showNoise = (p["noise"] ?? 0) > 0 || shownExtras.contains("noise")
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Oscillators", "Stack waves to build the tone. Each one plays the same note, shifted by its pitch.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<4) { i in
                        if on[i] { oscCard(id, p, i, level: min(1, levels[i])) }
                    }
                    if showSub {
                        extraCard(id, title: "Sub", detail: "A sine one octave down, for weight.", pid: "sub", value: p["sub"] ?? 0)
                    }
                    if showNoise {
                        extraCard(id, title: "Noise", detail: "Hiss for breath, air, and texture.", pid: "noise", value: p["noise"] ?? 0)
                    }
                    addCard(id, p, on: on, showSub: showSub, showNoise: showNoise)
                }
                .padding(.bottom, 2)
            }
        }
    }

    private func oscCard(_ id: AssetID, _ p: [String: Double], _ i: Int, level: Double) -> some View {
        let n = i + 1
        let wave = Int(p["osc\(n)"] ?? 2)
        let semiKey = "semi\(n)"
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Osc \(n)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if i > 0 {
                    Button { removeOsc(id, p, n) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textFaint).help("Remove Osc \(n)")
                }
            }
            WaveIcon(shape: .osc(wave)).stroke(Theme.accent, lineWidth: 1.6).frame(height: 30)
            HStack(spacing: 4) {
                ForEach(0..<4) { w in
                    Button { setOsc(id, p, ["osc\(n)": Double(w)]) } label: {
                        WaveIcon(shape: .osc(w)).stroke(w == wave ? Theme.text : Theme.textDim, lineWidth: 1.2)
                            .frame(width: 22, height: 12).padding(4)
                            .background(RoundedRectangle(cornerRadius: 3).fill(w == wave ? Theme.accent.opacity(0.35) : Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(SynthParams.waves[w])
                }
            }
            labeled("Pitch") {
                HStack(spacing: 4) {
                    stepButton(down: true) { nudge(id, p, semiKey, -12, -24, 24) }
                    DragNumber(value: p[semiKey] ?? 0, range: -24...24, step: 1, sensitivity: 0.15,
                               format: { semitoneText($0) },
                               onChange: { v in set(id, semiKey, v.rounded()) }, onEnd: { store.endGesture() })
                        .frame(width: 52)
                    stepButton(down: false) { nudge(id, p, semiKey, 12, -24, 24) }
                }
            }
            if i > 0 {
                labeled("Fine") {
                    DragNumber(value: p["fine\(n)"] ?? 0, range: -50...50, step: 1, sensitivity: 0.3,
                               format: { String(format: "%+.0f ct", $0) },
                               onChange: { v in set(id, "fine\(n)", v) }, onEnd: { store.endGesture() })
                        .frame(width: 58)
                }
            }
            labeled("Level") {
                Slider(value: Binding(get: { level }, set: { setOsc(id, p, ["lvl\(n)": $0], live: true) }),
                       in: 0...1, onEditingChanged: { if !$0 { store.endGesture() } })
                    .controlSize(.mini)
            }
            if i == 1 {
                labeled("FM") {
                    Slider(value: Binding(get: { p["fm"] ?? 0 }, set: { set(id, "fm", $0) }),
                           in: 0...1, onEditingChanged: { if !$0 { store.endGesture() } })
                        .controlSize(.mini)
                }
                .help("Osc 2 bends Osc 1's wave instead of only mixing with it. Great for bells and growls. FM Env (under the volume envelope) makes each note start brighter.")
            }
        }
        .padding(10)
        .frame(width: 168, height: Self.cardHeight, alignment: .topLeading)
        .panelBox()
    }

    private func extraCard(_ id: AssetID, title: String, detail: String, pid: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button {
                    shownExtras.remove(pid)
                    store.edit { $0.updateNotes(id) { $0.instrument.params[pid] = 0 } }
                } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textFaint).help("Remove \(title)")
            }
            WaveIcon(shape: pid == "sub" ? .osc(0) : .noise).stroke(Theme.accent, lineWidth: 1.4).frame(height: 30)
            Text(detail).font(Theme.tiny).foregroundStyle(Theme.textFaint).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            labeled("Level") {
                Slider(value: Binding(get: { value }, set: { set(id, pid, $0) }), in: 0...1,
                       onEditingChanged: { if !$0 { store.endGesture() } })
                    .controlSize(.mini)
            }
        }
        .padding(10)
        .frame(width: 140, height: Self.cardHeight, alignment: .topLeading)
        .panelBox()
    }

    private func addCard(_ id: AssetID, _ p: [String: Double], on: [Bool], showSub: Bool, showNoise: Bool) -> some View {
        Menu {
            if let free = on.indices.first(where: { !on[$0] }) {
                ForEach(0..<4) { w in
                    Button("Add \(SynthParams.waves[w]) Wave") { addOsc(id, p, free + 1, wave: w) }
                }
            }
            if !showSub { Button("Add Sub") { shownExtras.insert("sub"); set(id, "sub", 0.5); store.endGesture() } }
            if !showNoise { Button("Add Noise") { shownExtras.insert("noise"); set(id, "noise", 0.15); store.endGesture() } }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle").font(.system(size: 22, weight: .light))
                Text("Add").font(Theme.small)
                Text(on.allSatisfy { $0 } ? "Sub or noise" : "Wave, sub, or noise").font(Theme.tiny).foregroundStyle(Theme.textFaint)
            }
            .foregroundStyle(Theme.accent)
            .frame(width: 110, height: Self.cardHeight)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(on.allSatisfy { $0 } && showSub && showNoise)
    }

    // MARK: Filter, envelope, LFO, character

    private func filter(_ id: AssetID, _ p: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Filter", "Cuts frequencies. Low-pass makes it darker, high-pass makes it thinner.")
            Picker("", selection: Binding(get: { Int(p["ftype"] ?? 0) }, set: { set(id, "ftype", Double($0)); store.endGesture() })) {
                Text("Low-pass").tag(0)
                Text("Low 24").tag(1)
                Text("Band").tag(2)
                Text("High-pass").tag(3)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
            FilterCurve(type: Int(p["ftype"] ?? 0), cutoff: p["cutoff"] ?? 6000, resonance: p["resonance"] ?? 0)
                .frame(height: 70)
            params(id, p, ["cutoff", "resonance", "fenv", "fa", "fd", "fs", "fr", "keytrack", "velcut"],
                   names: ["fa": "Env Attack", "fd": "Env Decay", "fs": "Env Sustain", "fr": "Env Release", "velcut": "Velocity"])
        }
        .padding(10).panelBox()
    }

    private func envelope(_ id: AssetID, _ p: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Volume Envelope", "How the sound starts, holds, and fades when you let go.")
            EnvelopeShape(a: p["a"] ?? 0.004, d: p["d"] ?? 0.3, s: p["s"] ?? 0.75, r: p["r"] ?? 0.25)
                .frame(height: 70)
            params(id, p, ["a", "d", "s", "r"])
            Divider().overlay(Theme.border).padding(.vertical, 2)
            params(id, p, ["penv", "pdecay"], names: ["penv": "Pitch Drop", "pdecay": "Drop Time"])
            if (p["on2"] ?? 1) > 0.5 {
                // Extra FM at the start of each note that dies away: the bright attack of FM pianos and bells.
                params(id, p, ["fmenv", "fmdecay"])
            }
        }
        .padding(10).panelBox()
    }

    private func lfo(_ id: AssetID, _ p: [String: Double]) -> some View {
        let shape = Int(p["lfoshape"] ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("LFO", "A slow wave that moves things: wobbles, vibrato, and pulsing.")
            HStack(spacing: 4) {
                ForEach(0..<6) { s in
                    Button { set(id, "lfoshape", Double(s)); store.endGesture() } label: {
                        WaveIcon(shape: .lfo(s)).stroke(s == shape ? Theme.text : Theme.textDim, lineWidth: 1.2)
                            .frame(width: 22, height: 12).padding(4)
                            .background(RoundedRectangle(cornerRadius: 3).fill(s == shape ? Theme.accent.opacity(0.35) : Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(["Sine", "Triangle", "Saw Down", "Saw Up", "Square", "Random"][s])
                }
            }
            params(id, p, (p["lfosync"] ?? 0) > 0 ? ["lfosync"] : ["lfosync", "lforate"], names: ["lfosync": "Sync", "lforate": "Rate"])
            params(id, p, ["lfocut", "lfopitch", "lfoamp", "lfofm"], names: ["lfocut": "→ Filter", "lfopitch": "→ Pitch", "lfoamp": "→ Volume", "lfofm": "→ FM"])
        }
        .padding(10).panelBox()
    }

    private func character(_ id: AssetID, _ p: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Character", "Thickness, width, grit, and how notes connect.")
            params(id, p, ["unison", "spread", "width", "drift", "drive", "mode", "glide", "volume"],
                   names: ["unison": "Voices", "spread": "Detune", "width": "Width", "mode": "Notes"])
        }
        .padding(10).panelBox()
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textDim)
            Text(help).font(Theme.tiny).foregroundStyle(Theme.textFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.tiny).foregroundStyle(Theme.textDim).frame(width: 34, alignment: .leading)
            content()
        }
    }

    private func stepButton(down: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: down ? "chevron.down" : "chevron.up").font(.system(size: 8, weight: .bold))
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain).foregroundStyle(Theme.textDim)
        .help(down ? "Down an octave" : "Up an octave")
    }

    @ViewBuilder private func params(_ id: AssetID, _ p: [String: Double], _ ids: [String], names: [String: String] = [:]) -> some View {
        ForEach(ids, id: \.self) { pid in
            if let base = SynthParams.defs.first(where: { $0.id == pid }) {
                let def = names[pid].map(base.renamed) ?? base
                ParamRow(def: def, value: def.clamp(p[pid] ?? def.defaultValue),
                         onChange: { v in set(id, pid, v) }, onEnd: { store.endGesture() })
            }
        }
    }

    private func semitoneText(_ v: Double) -> String {
        let s = Int(v.rounded())
        if s == 0 { return "0 st" }
        if s % 12 == 0 { return String(format: "%+d oct", s / 12) }
        return String(format: "%+d st", s)
    }

    // MARK: Editing

    private func set(_ id: AssetID, _ pid: String, _ v: Double) {
        store.live { $0.updateNotes(id) { $0.instrument.params[pid] = v } }
    }

    private func nudge(_ id: AssetID, _ p: [String: Double], _ pid: String, _ by: Double, _ lo: Double, _ hi: Double) {
        set(id, pid, min(hi, max(lo, (p[pid] ?? 0) + by)))
        store.endGesture()
    }

    /// Oscillator changes go through the level view, so levels mean what they show.
    private func setOsc(_ id: AssetID, _ p: [String: Double], _ changes: [String: Double], live: Bool = false) {
        var q = OscillatorLevels.normalized(p)
        for (k, v) in changes { q[k] = v }
        store.live { $0.updateNotes(id) { $0.instrument.params = q } }
        if !live { store.endGesture() }
    }

    private func addOsc(_ id: AssetID, _ p: [String: Double], _ n: Int, wave: Int) {
        // A new wave starts an octave up at half level: easy to hear, easy to blend.
        var c: [String: Double] = ["on\(n)": 1, "osc\(n)": Double(wave), "semi\(n)": 12, "fine\(n)": 0, "lvl\(n)": 0.5]
        if n == 2 { c["fm"] = p["fm"] ?? 0 }
        setOsc(id, p, c)
    }

    private func removeOsc(_ id: AssetID, _ p: [String: Double], _ n: Int) {
        var c: [String: Double] = ["on\(n)": 0]
        if n == 2 { c["fm"] = 0; c["lfofm"] = 0; c["fmenv"] = 0 } // FM needs osc 2
        setOsc(id, p, c)
    }
}

// MARK: - Pictures

/// The combined wave of every oscillator, two cycles of the note: what you're building, before the filter.
struct WaveformPreview: View {
    let params: [String: Double]

    var body: some View {
        Canvas { ctx, size in
            let pts = WaveformPreview.samples(params, count: Int(max(64, size.width)))
            let mid = size.height / 2
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: mid)); grid.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(grid, with: .color(Theme.border), lineWidth: 1)
            var path = Path()
            for (i, v) in pts.enumerated() {
                let pt = CGPoint(x: CGFloat(i) / CGFloat(pts.count - 1) * size.width, y: mid - CGFloat(v) * (mid - 6))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
        .overlay(alignment: .topLeading) {
            Text("YOUR WAVE").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textFaint).padding(6)
        }
    }

    static func wave(_ w: Int, _ ph: Double) -> Double {
        let t = ph - ph.rounded(.down)
        switch w {
        case 0: return sin(2 * .pi * t)
        case 1: return t < 0.5 ? 4 * t - 1 : 3 - 4 * t
        case 2: return 2 * t - 1
        default: return t < 0.5 ? 1 : -1
        }
    }

    static func samples(_ p: [String: Double], count: Int) -> [Double] {
        func v(_ k: String) -> Double { p[k] ?? 0 }
        let lv = OscillatorLevels.levels(p)
        let s1 = v("semi1")
        let r = [pow(2, s1 / 12), pow(2, (s1 + v("semi2") + v("fine2") / 100) / 12),
                 pow(2, (s1 + v("semi3") + v("fine3") / 100) / 12), pow(2, (s1 + v("semi4") + v("fine4") / 100) / 12)]
        let waves = [Int(v("osc1")), Int(v("osc2")), Int(v("osc3")), Int(v("osc4"))]
        let fm = v("fm") * 2.5
        var seed: UInt32 = 99
        var out: [Double] = []
        for i in 0..<count {
            let x = Double(i) / Double(count - 1) * 2 // two cycles
            let o2 = wave(waves[1], x * r[1])
            var y = wave(waves[0], x * r[0] + fm * o2) * lv[0] + o2 * lv[1]
            y += wave(waves[2], x * r[2]) * lv[2] + wave(waves[3], x * r[3]) * lv[3]
            y += sin(2 * .pi * x * 0.5) * v("sub") * 2
            if v("noise") > 0 {
                seed = seed &* 1664525 &+ 1013904223
                y += (Double(seed) / 4294967296 * 2 - 1) * v("noise") * 2
            }
            out.append(y)
        }
        let m = out.map(abs).max() ?? 1
        return m > 0 ? out.map { $0 / m } : out
    }
}

/// Little line drawings of wave and LFO shapes for the pickers.
struct WaveIcon: Shape {
    enum Kind { case osc(Int), lfo(Int), noise }
    let shape: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = 60
        var seed: UInt32 = 7
        for i in 0...n {
            let x = Double(i) / Double(n)
            let y: Double
            switch shape {
            case .osc(let w): y = WaveformPreview.wave(w, x * 2)
            case .noise:
                seed = seed &* 1664525 &+ 1013904223
                y = Double(seed) / 4294967296 * 2 - 1
            case .lfo(let s):
                switch s {
                case 1: y = WaveformPreview.wave(1, x * 2)
                case 2: y = 1 - 2 * ((x * 2) - (x * 2).rounded(.down))
                case 3: y = 2 * ((x * 2) - (x * 2).rounded(.down)) - 1
                case 4: y = WaveformPreview.wave(3, x * 2)
                case 5: y = [0.6, -0.4, 0.9, -0.8, 0.2, -0.1][min(5, Int(x * 6))]
                default: y = sin(2 * .pi * x * 2)
                }
            }
            let pt = CGPoint(x: rect.minX + rect.width * x, y: rect.midY - rect.height / 2 * y * 0.9)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// The filter's frequency response: where it lets sound through, and the resonance bump.
struct FilterCurve: View {
    let type: Int
    let cutoff: Double
    let resonance: Double

    var body: some View {
        Canvas { ctx, size in
            func mag(_ f: Double) -> Double {
                let w = f / cutoff
                func stage(_ k: Double) -> (Double, Double, Double) {
                    let d = sqrt(pow(1 - w * w, 2) + pow(k * w, 2))
                    return (1 / d, k * w / d, w * w / d)
                }
                let k = 2 - 1.95 * min(max(resonance, 0), 1)
                switch type {
                case 1: return stage(2 - 1.95 * 0.08).0 * stage(k).0
                case 2: return stage(k).1
                case 3: return stage(k).2
                default: return stage(k).0
                }
            }
            let lo = log10(20.0), hi = log10(20000.0)
            func y(_ db: Double) -> CGFloat { CGFloat((24 - min(24, max(-48, db))) / 72) * size.height }
            var line = Path(), fill = Path()
            for i in 0...120 {
                let f = pow(10, lo + (hi - lo) * Double(i) / 120)
                let pt = CGPoint(x: CGFloat(i) / 120 * size.width, y: y(20 * log10(max(1e-6, mag(f)))))
                if i == 0 { line.move(to: pt); fill.move(to: CGPoint(x: 0, y: size.height)); fill.addLine(to: pt) } else { line.addLine(to: pt); fill.addLine(to: pt) }
            }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0))); zero.addLine(to: CGPoint(x: size.width, y: y(0)))
            ctx.stroke(zero, with: .color(Theme.border), lineWidth: 1)
            ctx.fill(fill, with: .color(Theme.accent.opacity(0.15)))
            ctx.stroke(line, with: .color(Theme.accent), lineWidth: 1.6)
            let cx = CGFloat((log10(max(20, min(20000, cutoff))) - lo) / (hi - lo)) * size.width
            var marker = Path()
            marker.move(to: CGPoint(x: cx, y: 0)); marker.addLine(to: CGPoint(x: cx, y: size.height))
            ctx.stroke(marker, with: .color(Theme.textFaint), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.2)))
    }
}

/// Attack, decay, sustain, and release as a shape. Times are drawn on a square-root scale so short and long both read.
struct EnvelopeShape: View {
    let a: Double, d: Double, s: Double, r: Double

    var body: some View {
        Canvas { ctx, size in
            let wa = sqrt(a), wd = sqrt(d), wr = sqrt(r), hold = 0.9
            let total = wa + wd + hold + wr
            func x(_ t: Double) -> CGFloat { CGFloat(t / total) * (size.width - 8) + 4 }
            let top: CGFloat = 6, bottom = size.height - 4
            func y(_ level: Double) -> CGFloat { bottom - CGFloat(level) * (bottom - top) }
            var p = Path()
            p.move(to: CGPoint(x: x(0), y: y(0)))
            p.addLine(to: CGPoint(x: x(wa), y: y(1)))
            // Exponential-looking decay and release.
            for i in 1...16 {
                let f = Double(i) / 16
                p.addLine(to: CGPoint(x: x(wa + wd * f), y: y(s + (1 - s) * exp(-4.6 * f))))
            }
            p.addLine(to: CGPoint(x: x(wa + wd + hold), y: y(s)))
            for i in 1...16 {
                let f = Double(i) / 16
                p.addLine(to: CGPoint(x: x(wa + wd + hold + wr * f), y: y(s * exp(-4.6 * f))))
            }
            var fill = p
            fill.addLine(to: CGPoint(x: x(total), y: bottom))
            fill.addLine(to: CGPoint(x: x(0), y: bottom))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(Theme.accent.opacity(0.15)))
            ctx.stroke(p, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            // Note-off marker where release starts.
            var m = Path()
            m.move(to: CGPoint(x: x(wa + wd + hold), y: top)); m.addLine(to: CGPoint(x: x(wa + wd + hold), y: bottom))
            ctx.stroke(m, with: .color(Theme.textFaint), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.2)))
    }
}

extension View {
    func panelBox() -> some View {
        background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
    }
}
