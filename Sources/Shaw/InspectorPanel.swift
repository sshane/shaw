import ShawCore
import SwiftUI

struct InspectorPanel: View {
    @Environment(Store.self) private var store
    @State private var dropTarget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .padding(.bottom, 30)
        }
        .background(dropTarget ? Theme.accent.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.focus = .inspector
            store.selectedEffects = []
        }
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { payload, _ in
                switch payload {
                case .effect(let k):
                    guard let host = store.currentEffectHost else { return false }
                    store.addEffect(k, to: host)
                    return true
                case .preset(let name):
                    if case .asset(let id)? = store.inspector { store.edit { $0.updateNotes(id) { $0.instrument = .preset(name) } } }
                    return true
                case .effectInstance(let id):
                    guard let host = store.currentEffectHost else { return false }
                    store.dropEffect(id, onto: host, before: nil)
                    return true
                default: return false
                }
            },
            onHover: { dropTarget = $0 != nil }))
    }

    @ViewBuilder private var content: some View {
        if !store.hasContent {
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 22)).foregroundStyle(Theme.textFaint)
                Text("Nothing to adjust yet").font(Theme.header).foregroundStyle(Theme.textFaint)
                Text("Add an instrument and its sound and effects show up here.")
                    .font(Theme.small).foregroundStyle(Theme.textFaint).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60).padding(.horizontal, 20)
        } else {
            details
        }
    }

    @ViewBuilder private var details: some View {
        switch store.inspector ?? .composition(store.activeCompID) {
        case .composition(let id): CompositionInspector(compID: id)
        case .track(let cid, let tid): TrackInspector(compID: cid, trackID: tid)
        case .clip(let cid, let kid): ClipInspector(compID: cid, clipID: kid)
        case .asset(let id):
            if let a = store.project.asset(id) {
                switch a.content {
                case .notes: InstrumentInspector(assetID: id)
                case .drums: EmptyView()
                case .audio(let f): AudioInspector(asset: a, file: f)
                case .composition: CompositionInspector(compID: id)
                }
            }
        case .slot(let cid, let tid, let scene): SlotInspector(compID: cid, trackID: tid, scene: scene)
        }
    }
}

struct InspectorTitle: View {
    let icon: String
    let kind: String
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint)
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}

struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.small).foregroundStyle(Theme.textDim).frame(width: 96, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .padding(.horizontal, 10)
    }
}

// MARK: - Composition

struct CompositionInspector: View {
    @Environment(Store.self) private var store
    let compID: AssetID

    var body: some View {
        if let a = store.project.asset(compID), let comp = store.project.composition(compID) {
            InspectorTitle(icon: assetIcon(.composition), kind: "Composition", name: a.name, color: Theme.label(a.colorIndex))
            PropertyRow(label: "Duration") {
                DragNumber(value: comp.length / Double(store.project.beatsPerBar), range: 1...999, step: 1, sensitivity: 0.1,
                           format: { "\(Int($0)) bars" },
                           onChange: { v in store.live { $0.updateComposition(compID) { $0.length = v * Double(store.project.beatsPerBar) } } },
                           onEnd: { store.endGesture() })
            }
            PropertyRow(label: "Volume") {
                DragNumber(value: comp.volume, range: -60...12, step: 0.1, sensitivity: 0.2, format: { String(format: "%.1f dB", $0) },
                           onChange: { v in store.live { $0.updateComposition(compID) { $0.volume = v } } }, onEnd: { store.endGesture() })
            }
            PropertyRow(label: "Used") {
                let n = store.project.usageCount(of: compID)
                Text(compID == store.project.mainCompositionID && n == 0 ? "Main composition" :
                        (n == 0 ? "Not placed anywhere" : "Used in \(n) place\(n == 1 ? "" : "s"), all linked"))
                    .font(Theme.small).foregroundStyle(Theme.textDim)
            }
            Text("Composition effects run after every track and clip inside it, like an After Effects adjustment on a precomp.")
                .font(Theme.tiny).foregroundStyle(Theme.textFaint).padding(.horizontal, 10).padding(.top, 4)
            EffectStack(host: .composition(compID))
        }
    }
}

// MARK: - Track

struct TrackInspector: View {
    @Environment(Store.self) private var store
    let compID: AssetID
    let trackID: UUID

    var body: some View {
        if let comp = store.project.composition(compID), let i = comp.trackIndex(trackID) {
            let t = comp.tracks[i]
            InspectorTitle(icon: "rectangle.split.3x1", kind: "Track", name: t.name, color: Theme.label(t.colorIndex))
            PropertyRow(label: "Volume") {
                DragNumber(value: t.volume, range: -60...12, step: 0.1, sensitivity: 0.2, format: { String(format: "%.1f dB", $0) },
                           onChange: { v in store.updateTrack(trackID, in: compID, live: true) { $0.volume = v } }, onEnd: { store.endGesture() })
            }
            PropertyRow(label: "Pan") {
                DragNumber(value: t.pan * 50, range: -50...50, step: 1, sensitivity: 0.5,
                           format: { $0 == 0 ? "C" : ($0 < 0 ? "\(Int(-$0))L" : "\(Int($0))R") },
                           onChange: { v in store.updateTrack(trackID, in: compID, live: true) { $0.pan = v / 50 } }, onEnd: { store.endGesture() })
            }
            PropertyRow(label: "State") {
                ToggleChip(label: "M", on: t.mute, color: Theme.mute) { store.updateTrack(trackID, in: compID) { $0.mute.toggle() } }
                ToggleChip(label: "S", on: t.solo, color: Theme.solo) { store.updateTrack(trackID, in: compID) { $0.solo.toggle() } }
            }
            EffectStack(host: .track(compID, trackID))
        }
    }
}

// MARK: - Clip

struct ClipInspector: View {
    @Environment(Store.self) private var store
    let compID: AssetID
    let clipID: UUID
    @State private var showMore = false

    var body: some View {
        if let comp = store.project.composition(compID), let (ti, ci) = comp.locate(clip: clipID) {
            let c = comp.tracks[ti].clips[ci]
            let src = store.project.asset(c.assetID)
            let bpb = Double(store.project.beatsPerBar)
            InspectorTitle(icon: assetIcon(src?.kind ?? .notes), kind: "Clip of \(src?.kind.label ?? "?")", name: src?.name ?? "Missing",
                           color: Theme.label(src?.colorIndex ?? 0))
            HStack(spacing: 6) {
                Button("Open Source") { store.open(asset: c.assetID) }
                Button("Make Unique") { store.makeUnique(clipID) }
                    .help("Give this clip its own copy so edits stop affecting the other uses")
            }
            .controlSize(.small).padding(.horizontal, 10).padding(.bottom, 6)
            PropertyRow(label: "Start") {
                DragNumber(value: c.start, range: 0...100_000, step: 0.25, sensitivity: 0.05,
                           format: { formatPosition($0, beatsPerBar: Int(bpb)) }, parse: { Self.parsePos($0, bpb) },
                           onChange: { v in store.updateClip(clipID, live: true) { $0.start = v } }, onEnd: { store.endGesture() })
            }
            PropertyRow(label: "Length") {
                DragNumber(value: c.length, range: 0.0625...100_000, step: 0.25, sensitivity: 0.05,
                           format: { formatLength($0, beatsPerBar: Int(bpb)) }, parse: { Double($0.filter { "0123456789.".contains($0) }).map { $0 * bpb } },
                           onChange: { v in store.updateClip(clipID, live: true) { $0.length = v } }, onEnd: { store.endGesture() })
            }
            if showMore {
            PropertyRow(label: "Source Offset") {
                DragNumber(value: c.offset, range: 0...100_000, step: 0.25, sensitivity: 0.05, format: { String(format: "%.2f beats", $0) },
                           onChange: { v in store.updateClip(clipID, live: true) { $0.offset = v } }, onEnd: { store.endGesture() })
            }
            PropertyRow(label: "Gain") {
                DragNumber(value: c.gain, range: -60...24, step: 0.1, sensitivity: 0.2, format: { String(format: "%.1f dB", $0) },
                           onChange: { v in store.updateClip(clipID, live: true) { $0.gain = v } }, onEnd: { store.endGesture() })
            }
            PropertyRow(label: "Past End") {
                Picker("", selection: Binding(get: { c.loops }, set: { v in store.updateClip(clipID) { $0.loops = v } })) {
                    Text("Silence").tag(false)
                    Text("Loop").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130).controlSize(.small)
            }
            PropertyRow(label: "Mute") {
                Toggle("", isOn: Binding(get: { c.mute }, set: { v in store.updateClip(clipID) { $0.mute = v } })).labelsHidden()
            }
            Text("Tip: Option-drag a clip's right edge to loop it. Plain drag trims; past the end is silent (hatched).")
                .font(Theme.tiny).foregroundStyle(Theme.textFaint).padding(.horizontal, 10).padding(.top, 4)
            }
            Button(showMore ? "Fewer clip settings" : "More clip settings") { showMore.toggle() }
                .buttonStyle(.plain).font(Theme.tiny).foregroundStyle(Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 4)
            SourceSoundSection(assetID: c.assetID)
            EffectStack(host: .clip(compID, clipID), title: "Clip Effects")
            EffectStack(host: .track(compID, comp.tracks[ti].id), title: "Track Effects · \(comp.tracks[ti].name)")
        }
    }

    static func parsePos(_ s: String, _ bpb: Double) -> Double? {
        let parts = s.split(separator: ".").compactMap { Double($0) }
        guard let bar = parts.first else { return nil }
        let beat = parts.count > 1 ? parts[1] - 1 : 0
        let six = parts.count > 2 ? (parts[2] - 1) / 4 : 0
        return (bar - 1) * bpb + beat + six
    }
}

// MARK: - Effects

struct EffectStack: View {
    @Environment(Store.self) private var store
    let host: EffectHost
    var title = "Effects"

    var body: some View {
        let effects = store.effects(of: host)
        HStack {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint).lineLimit(1)
            Spacer()
            Menu {
                ForEach(EffectRegistry.all) { d in
                    Button(d.name) { store.addEffect(d.id, to: host) }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Add an effect")
        }
        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(onPayload: { payload, _ in
            switch payload {
            case .effectInstance(let id): store.dropEffect(id, onto: host, before: nil)
            case .effect(let k): store.addEffect(k, to: host)
            default: return false
            }
            return true
        }))
        if effects.isEmpty {
            Text("Drop an effect here, or search the Browser (e.g. \"reverb\") and drag it onto anything.")
                .font(Theme.tiny).foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Theme.textFaint.opacity(0.5)))
                .padding(.horizontal, 10)
        }
        ForEach(Array(effects.enumerated()), id: \.element.id) { i, e in
            EffectCard(host: host, effect: e, index: i, count: effects.count)
        }
    }
}

/// One effect: its main controls up front, the rest behind "More", and a visible delete button.
struct EffectCard: View {
    @Environment(Store.self) private var store
    let host: EffectHost
    let effect: Effect
    let index: Int
    let count: Int
    @State private var showAdvanced = false

    @State private var dropTarget = false

    var body: some View {
        let d = EffectRegistry.descriptor(effect.kind)
        let selected = store.selectedEffects.contains(effect.id) && store.selectedEffectsHost == host
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button { update { $0.expanded.toggle() } } label: {
                    Image(systemName: effect.expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                        .frame(width: 12, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textDim)
                .help(effect.expanded ? "Collapse" : "Expand")
                Toggle("", isOn: Binding(get: { effect.enabled }, set: { v in
                    update { $0.enabled = v }
                }))
                .toggleStyle(.checkbox).labelsHidden().controlSize(.small)
                .help("On / off")
                // Like After Effects: click the name to select (⇧/⌘ for more), ⌘C / ⌘V to copy onto other things,
                // drag the name to reorder or onto another layer to copy it there.
                Text(d?.name ?? effect.kind).font(Theme.header).foregroundStyle(effect.enabled ? Theme.text : Theme.textFaint)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(selected ? Theme.accent.opacity(0.35) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let extend = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
                        store.selectEffect(effect.id, in: host, extend: extend)
                    }
                    .shawDraggable(.effectInstance(effect.id), preview: d?.name ?? effect.kind)
                    .help("Click to select · ⌘C copy · ⌘V paste onto a selected clip or track · drag to reorder or copy")
                Spacer()
                Menu {
                    Button("Move Up") { move(-1) }.disabled(index == 0)
                    Button("Move Down") { move(1) }.disabled(index == count - 1)
                    Button("Duplicate") {
                        store.updateEffects(host) { fx in var c = effect; c.id = UUID(); fx.insert(c, at: index + 1) }
                    }
                    Button("Reset to Defaults") { update { $0.params = d?.params.defaults() ?? [:] } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Button {
                    store.updateEffects(host) { $0.removeAll { $0.id == effect.id } }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
                .help("Delete this effect")
            }
            .frame(height: 24)
            if effect.expanded, let d {
                ForEach(d.basicParams) { p in row(p) }
                let advanced = d.advancedParams
                if !advanced.isEmpty {
                    Button(showAdvanced ? "Less" : "More (\(advanced.count))") { showAdvanced.toggle() }
                        .buttonStyle(.plain)
                        .font(Theme.tiny).foregroundStyle(Theme.accent)
                        .padding(.leading, 4).padding(.vertical, 2)
                    if showAdvanced { ForEach(advanced) { p in row(p) } }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accent.opacity(0.1) : Color.black.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.accent.opacity(0.8) : Color.clear, lineWidth: 1))
        .overlay(alignment: .top) { if dropTarget { Rectangle().fill(Theme.accent).frame(height: 2).offset(y: -3) } }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { payload, _ in
                switch payload {
                case .effectInstance(let id): store.dropEffect(id, onto: host, before: effect.id)
                case .effect(let k):
                    guard let d = EffectRegistry.descriptor(k) else { return false }
                    let e = d.makeEffect()
                    store.updateEffects(host) { fx in fx.insert(e, at: fx.firstIndex { $0.id == effect.id } ?? fx.count) }
                default: return false
                }
                return true
            },
            onHover: { dropTarget = $0 != nil }))
    }

    private func row(_ p: ParamDef) -> some View {
        EffectParamRow(host: host, effect: effect, def: p)
    }

    private func update(_ f: @escaping (inout Effect) -> Void) {
        store.updateEffects(host) { fx in if let i = fx.firstIndex(where: { $0.id == effect.id }) { f(&fx[i]) } }
    }

    private func move(_ d: Int) {
        store.updateEffects(host) { fx in
            guard let i = fx.firstIndex(where: { $0.id == effect.id }) else { return }
            let j = max(0, min(fx.count - 1, i + d))
            fx.swapAt(i, j)
        }
    }
}

// MARK: - Sound of a clip or slot

/// The instrument (or kit) behind a clip, shown compactly.
struct SourceSoundSection: View {
    @Environment(Store.self) private var store
    let assetID: AssetID

    var body: some View {
        switch store.project.asset(assetID)?.kind {
        case .notes?: InstrumentInspector(assetID: assetID, compact: true)
        default: EmptyView()
        }
    }
}

// MARK: - Session slot

struct SlotInspector: View {
    @Environment(Store.self) private var store
    let compID: AssetID
    let trackID: UUID
    let scene: Int

    var body: some View {
        if let comp = store.project.composition(compID), let ti = comp.trackIndex(trackID),
           let slot = comp.tracks[ti].slots[scene], let a = store.project.asset(slot.assetID) {
            let t = comp.tracks[ti]
            InspectorTitle(icon: assetIcon(a.kind), kind: "Session clip · \(t.name)", name: a.name, color: Theme.label(a.colorIndex))
            HStack(spacing: 6) {
                Button("Launch") { store.launch(track: trackID, scene: scene) }
                Button("Open") { store.open(asset: a.id) }
            }
            .controlSize(.small).padding(.horizontal, 10).padding(.bottom, 4)
            SourceSoundSection(assetID: a.id)
            if a.kind == .composition { EffectStack(host: .composition(a.id), title: "Composition Effects · \(a.name)") }
            EffectStack(host: .track(compID, trackID), title: "Track Effects · \(t.name)")
        }
    }
}

// MARK: - Instrument (synth)

struct InstrumentInspector: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    /// Compact: shown inside a clip/slot inspector, with a smaller header.
    var compact = false
    @State private var showAll = false

    static let groups: [(String, [String])] = [
        ("Oscillators", ["osc1", "semi1", "lvl1", "on2", "osc2", "semi2", "fine2", "lvl2", "mix", "fm", "fmenv", "fmdecay",
                         "on3", "osc3", "semi3", "fine3", "lvl3", "on4", "osc4", "semi4", "fine4", "lvl4",
                         "osclevel", "sub", "noise", "unison", "spread", "drift"]),
        ("Filter", ["ftype", "cutoff", "resonance", "fenv", "keytrack"]),
        ("Amp Envelope", ["a", "d", "s", "r"]),
        ("Filter Envelope", ["fa", "fd", "fs", "fr"]),
        ("Pitch & Voice", ["penv", "pdecay", "mode", "glide"]),
        ("LFO", ["lfosync", "lforate", "lfoshape", "lfocut", "lfopitch", "lfoamp", "lfofm"]),
        ("Output", ["drive", "volume"]),
    ]

    var body: some View {
        if let a = store.project.asset(assetID), case .notes(let p) = a.content, let kit = p.instrument.kit {
            // Drum kit: nothing to tweak but which kit.
            if compact { SectionHeader(title: "Sound · Drum Kit") } else {
                InspectorTitle(icon: "circle.grid.3x3.fill", kind: "Drum Pattern", name: a.name, color: Theme.label(a.colorIndex))
            }
            PropertyRow(label: "Kit") {
                Menu(p.instrument.displayName) {
                    ForEach(DrumKits.kits) { k in
                        Button(k.name) {
                            store.replaceInstrument(ofAsset: assetID, with: .kit(k.id))
                            if !store.transport.playing { store.previewInstrument(.kit(k.id)) }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            KitSamplesSection(assetID: assetID, kit: kit, files: p.instrument.kitSamples ?? [:])
        } else if let a = store.project.asset(assetID), case .notes(let p) = a.content, p.instrument.isSampler {
            SamplerInspector(assetID: assetID, asset: a, pattern: p, compact: compact)
        } else if let a = store.project.asset(assetID), case .notes(let p) = a.content {
            if compact {
                SectionHeader(title: "Sound · Shaw Synth")
            } else {
                InspectorTitle(icon: "pianokeys", kind: "Pattern · Shaw Synth", name: a.name, color: Theme.label(a.colorIndex))
            }
            PropertyRow(label: "Instrument") {
                InstrumentMenu(assetID: assetID)
            }
            InstrumentActions(assetID: assetID)
                .padding(.horizontal, 10).padding(.bottom, 4)
            if !compact {
                PropertyRow(label: "Length") {
                    DragNumber(value: p.length / Double(store.project.beatsPerBar), range: 0.25...64, step: 0.25, sensitivity: 0.05,
                               format: { String(format: $0 == $0.rounded() ? "%.0f bars" : "%.2f bars", $0) },
                               onChange: { v in store.live { $0.updateNotes(assetID) { $0.length = v * Double(store.project.beatsPerBar) } } },
                               onEnd: { store.endGesture() })
                }
            }
            if showAll {
                ForEach(Self.groups, id: \.0) { group in
                    SectionHeader(title: group.0)
                    ForEach(group.1, id: \.self) { pid in paramRow(pid, p) }
                }
            } else {
                ForEach(SynthParams.basic, id: \.self) { pid in paramRow(pid, p) }
            }
            Button(showAll ? "Show fewer synth controls" : "Show all synth controls (\(SynthParams.defs.count - SynthParams.basic.count) more)") {
                showAll.toggle()
            }
            .buttonStyle(.plain)
            .font(Theme.tiny).foregroundStyle(Theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 4)
        }
    }

    @ViewBuilder private func paramRow(_ pid: String, _ p: NotePattern) -> some View {
        if let def = SynthParams.defs.first(where: { $0.id == pid }) {
            ParamRow(def: def, value: def.clamp(p.instrument.params[pid] ?? def.defaultValue),
                     onChange: { v in
                         store.live { $0.updateNotes(assetID) { $0.instrument.params[pid] = v } }
                     },
                     onEnd: { store.endGesture() })
            .padding(.horizontal, 10)
        }
    }
}

/// Pick a sound for a pattern: your instruments first, then the built-in presets by category.
struct InstrumentMenu: View {
    @Environment(Store.self) private var store
    let assetID: AssetID

    var body: some View {
        Menu(store.instrumentName(assetID)) {
            if !store.customInstruments.isEmpty {
                Section("My Instruments") {
                    ForEach(store.customInstruments) { c in Button(c.name) { pick(c.name) } }
                }
            }
            ForEach(InstrumentChoice.categoryOrder.filter { $0 != "My Instruments" && $0 != "Drums" }, id: \.self) { cat in
                let names = SynthPresets.names.filter { (SynthPresets.categories[$0] ?? "Synth") == cat }
                if !names.isEmpty {
                    Menu(cat) { ForEach(names, id: \.self) { n in Button(n) { pick(n) } } }
                }
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func pick(_ name: String) {
        store.replaceInstrument(ofAsset: assetID, with: .synth(name))
        if !store.transport.playing { store.previewInstrument(.synth(name)) }
    }
}

/// Where the sound stands (edited or saved) and what you can do about it.
struct InstrumentActions: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    /// The editor window already is the editor, so it hides that button.
    var showEdit = true

    var body: some View {
        let status = store.instrumentStatus(assetID)
        let name = store.instrumentName(assetID)
        VStack(alignment: .leading, spacing: 4) {
            Text(statusText(status, name))
                .font(Theme.tiny).foregroundStyle(status == .edited || status == .unsaved ? Theme.accent : Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if showEdit {
                    Button("Edit Instrument…") { store.openInstrumentEditor(assetID) }
                        .help("Open the Instrument Editor: oscillators, filter, envelope, and LFO, with pictures")
                }
                if status == .edited, SynthPresets.isBuiltIn(name) == false {
                    Button("Save") { store.saveInstrument(from: assetID) }
                        .help("Update \(name) in My Instruments. Layers already using it keep their own copy.")
                }
                Button(status == .unsaved ? "Save to My Instruments…" : "Save as New…") { store.saveInstrumentAsNew(from: assetID) }
                    .help("Save this sound as a new instrument you can add from the Browser in any project")
                if status == .edited {
                    Button("Revert") { store.revertInstrument(assetID) }
                        .help("Go back to the saved \(name) sound")
                }
            }
            .controlSize(.small)
        }
    }

    private func statusText(_ status: InstrumentStatus?, _ name: String) -> String {
        switch status {
        case .builtIn?: return "Built-in preset. Change anything, then save it as your own."
        case .custom?: return "One of your instruments."
        case .edited?: return SynthPresets.isBuiltIn(name)
            ? "Edited. Only this pattern changed. The built-in \(name) stays the same."
            : "Edited. Save updates \(name) for new layers; layers already using it keep their own copy."
        case .unsaved?: return "Not saved yet. Save it to use it in other projects."
        case nil: return ""
        }
    }
}

struct AudioInspector: View {
    let asset: Asset
    let file: AudioFileRef

    var body: some View {
        InspectorTitle(icon: "waveform", kind: "Audio File", name: asset.name, color: Theme.label(asset.colorIndex))
        PropertyRow(label: "Duration") { Text(String(format: "%.2f s", file.duration)).font(Theme.small) }
        PropertyRow(label: "Format") { Text("\(Int(file.sampleRate)) Hz · \(file.channels) ch").font(Theme.small) }
        Text(file.path).font(Theme.tiny).foregroundStyle(Theme.textFaint).padding(10).textSelection(.enabled)
    }
}
