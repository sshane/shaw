import ShawCore
import SwiftUI

struct MixerPanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        if !store.hasContent {
            VStack(spacing: 8) {
                Image(systemName: "slider.vertical.3").font(.system(size: 26)).foregroundStyle(Theme.textFaint)
                Text("Nothing to mix yet").font(Theme.header).foregroundStyle(Theme.textFaint)
                Text("Each instrument you add gets a fader here.").font(Theme.small).foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let comp = store.activeComp {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(comp.tracks) { t in
                        MixerStrip(name: t.name, color: Theme.label(t.colorIndex), volume: t.volume, pan: t.pan,
                                   mute: t.mute, solo: t.solo, effects: t.effects, meter: { store.engine.meter(for: t.id) },
                                   host: .track(store.activeCompID, t.id),
                                   setVolume: { v in store.updateTrack(t.id, live: true) { $0.volume = v } },
                                   setPan: { v in store.updateTrack(t.id, live: true) { $0.pan = v } },
                                   toggleMute: { store.updateTrack(t.id) { $0.mute.toggle() } },
                                   toggleSolo: { store.updateTrack(t.id) { $0.solo.toggle() } })
                    }
                    Rectangle().fill(Theme.border).frame(width: 2)
                    MixerStrip(name: store.activeAsset?.name ?? "Comp", color: store.color(of: store.activeCompID), volume: comp.volume, pan: nil,
                               mute: nil, solo: nil, effects: comp.effects, meter: { store.engine.compMeter },
                               host: .composition(store.activeCompID),
                               setVolume: { v in let id = store.activeCompID; store.live { $0.updateComposition(id) { $0.volume = v } } },
                               setPan: { _ in }, toggleMute: {}, toggleSolo: {})
                    MixerStrip(name: "Master", color: .white, volume: store.project.masterVolume, pan: nil, mute: nil, solo: nil,
                               effects: nil, meter: { store.engine.masterMeter }, host: nil,
                               setVolume: { v in store.live { $0.masterVolume = v } },
                               setPan: { _ in }, toggleMute: {}, toggleSolo: {})
                }
                .padding(6)
            }
        }
    }
}

struct MixerStrip: View {
    @Environment(Store.self) private var store
    let name: String
    let color: Color
    let volume: Double
    let pan: Double?
    let mute: Bool?
    let solo: Bool?
    let effects: [Effect]?
    let meter: () -> LevelMeter?
    let host: EffectHost?
    let setVolume: (Double) -> Void
    let setPan: (Double) -> Void
    let toggleMute: () -> Void
    let toggleSolo: () -> Void
    @State private var target = false
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 6) {
            Text(name).font(Theme.tiny).foregroundStyle(Theme.text).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.vertical, 3)
                .background(color.opacity(0.35))
            VStack(alignment: .leading, spacing: 1) {
                ForEach(effects ?? []) { e in
                    Text(EffectRegistry.descriptor(e.kind)?.name ?? e.kind)
                        .font(.system(size: 9)).foregroundStyle(e.enabled ? Theme.text : Theme.textFaint).lineLimit(1)
                        .padding(.horizontal, 3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 2).fill(Theme.control))
                }
            }
            .frame(height: 54, alignment: .top)
            .clipped()
            if let pan {
                Knob(value: pan, size: 20, onChange: setPan, onEnd: { store.endGesture() })
            } else {
                Spacer().frame(height: 20)
            }
            HStack(spacing: 4) {
                fader
                TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
                    let m = meter()
                    HStack(spacing: 1) {
                        LevelMeterView(level: m?.peakL ?? 0, vertical: true)
                        LevelMeterView(level: m?.peakR ?? 0, vertical: true)
                    }
                }
                .frame(width: 9)
            }
            // The fader is the one part that can give: a short panel gets a shorter fader, so the
            // whole strip always fits instead of losing its mute and solo off the bottom.
            .frame(minHeight: 40, maxHeight: 120)
            Text(volume <= -60 ? "-inf" : String(format: "%.1f", volume)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.textDim)
            HStack(spacing: 3) {
                if let mute { ToggleChip(label: "M", on: mute, color: Theme.mute, action: toggleMute) }
                if let solo { ToggleChip(label: "S", on: solo, color: Theme.solo, action: toggleSolo) }
            }
            .frame(height: 16)
        }
        .padding(4)
        .frame(width: 78)
        .background(RoundedRectangle(cornerRadius: 4).fill(target ? Theme.accent.opacity(0.2) : Color.black.opacity(0.2)))
        .onTapGesture {
            switch host {
            case .track(let c, let t)?: store.inspector = .track(c, t)
            case .composition(let c)?: store.inspector = .composition(c)
            default: break
            }
        }
        .onDrop(of: [.utf8PlainText], delegate: ShawDropDelegate(
            onPayload: { p, _ in
                guard let host else { return false }
                switch p {
                case .effect(let k): store.addEffect(k, to: host)
                case .effectInstance(let id): store.dropEffect(id, onto: host, before: nil)
                default: return false
                }
                return true
            },
            onHover: { target = $0 != nil }))
    }

    private var fader: some View {
        GeometryReader { g in
            let range = -60.0...6.0
            let n = (min(range.upperBound, max(range.lowerBound, volume)) - range.lowerBound) / (range.upperBound - range.lowerBound)
            let zeroN = (0 - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.4)).frame(width: 4)
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 14, height: 1).offset(y: -g.size.height * zeroN)
                RoundedRectangle(cornerRadius: 2).fill(Theme.text).frame(width: 22, height: 10)
                    .offset(y: -g.size.height * n + 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragStart == nil { dragStart = volume }
                    let fine = NSEvent.modifierFlags.contains(.shift) ? 0.25 : 1
                    var dB = dragStart! - Double(v.translation.height) / Double(g.size.height) * 66 * fine
                    dB = min(6, max(-60, dB))
                    if abs(dB) < 0.6 { dB = 0 }
                    setVolume(dB)
                }
                .onEnded { _ in dragStart = nil; store.endGesture() })
            .onTapGesture(count: 2) { setVolume(0); store.endGesture() }
        }
        .frame(width: 30)
    }
}
