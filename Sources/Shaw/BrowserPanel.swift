import ShawCore
import SwiftUI

enum BrowserTab: String, CaseIterable { case instruments = "Instruments", effects = "Effects" }

struct BrowserPanel: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var selected: String?
    @FocusState private var searchFocused: Bool
    @State private var pulse = false

    var body: some View {
        let empty = !store.hasContent
        VStack(spacing: 0) {
            tabs(empty: empty)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.textDim)
                TextField(store.browserTab == .instruments ? "Search instruments (drums, bass, pad…)" : "Search effects (reverb, delay…)",
                          text: $search)
                    .textFieldStyle(.plain).font(Theme.small).focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(Color.black.opacity(0.15))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch store.browserTab {
                    case .instruments: instruments(empty: empty)
                    case .effects: effects
                    }
                }
            }
        }
        .overlay {
            // When the project is empty, this is the one place to start, so make it obvious.
            if empty && store.browserTab == .instruments {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.accent, lineWidth: 2)
                    .opacity(pulse ? 0.9 : 0.25)
                    .allowsHitTesting(false)
                    .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true } }
            }
        }
        .onChange(of: store.focusBrowserSearch) { _, _ in searchFocused = true }
        .onChange(of: store.browserTab) { _, _ in search = ""; selected = nil }
    }

    private func tabs(empty: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(BrowserTab.allCases, id: \.self) { tab in
                let disabled = tab == .effects && empty
                let active = store.browserTab == tab
                Button {
                    store.browserTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .foregroundStyle(disabled ? Theme.textFaint.opacity(0.6) : (active ? Theme.text : Theme.textDim))
                        .background(active ? Theme.panel : Color.black.opacity(0.12))
                        .overlay(alignment: .bottom) { if active { Rectangle().fill(Theme.accent).frame(height: 2) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help(disabled ? "Add an instrument first. Effects go on clips, layers and compositions." : "")
            }
        }
    }

    // MARK: Instruments

    @ViewBuilder private func instruments(empty: Bool) -> some View {
        if empty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Start here").font(Theme.header).foregroundStyle(Theme.accent)
                Text("Click an instrument to hear it. Double-click (or drag it right) to add it.")
                    .font(Theme.tiny).foregroundStyle(Theme.textDim)
            }
            .padding(10)
        }
        let all = InstrumentChoice.all.filter { matches($0.name) || matches($0.category) }
        ForEach(InstrumentChoice.categoryOrder, id: \.self) { cat in
            let items = all.filter { $0.category == cat }
            if !items.isEmpty {
                SectionHeader(title: cat)
                ForEach(items) { item in
                    BrowserRow(icon: item.icon, title: item.name, subtitle: subtitle(item), payload: item.payload,
                               selected: selected == item.id, actionLabel: "Add",
                               onSelect: {
                                   selected = item.id
                                   store.previewInstrument(item)
                               },
                               onActivate: { store.addInstrument(item) })
                }
            }
        }
    }

    private func subtitle(_ item: InstrumentChoice) -> String {
        switch item {
        case .kit(let k): return DrumKits.kits.first { $0.id == k }?.summary ?? "Drum kit"
        case .synth: return "Shaw Synth · \(item.category)"
        }
    }

    // MARK: Effects

    @ViewBuilder private var effects: some View {
        let fx = EffectRegistry.search(search)
        let host = store.currentEffectHost
        Text(hostDescription(host))
            .font(Theme.tiny).foregroundStyle(Theme.textDim)
            .padding(10)
        ForEach(["Space", "Modulation", "Dynamics", "EQ & Filter", "Distortion", "Utility"], id: \.self) { cat in
            let items = fx.filter { $0.category == cat }
            if !items.isEmpty {
                SectionHeader(title: cat)
                ForEach(items) { d in
                    BrowserRow(icon: icon(for: d.category), title: d.name, subtitle: d.summary, payload: .effect(d.id),
                               selected: selected == d.id, actionLabel: "Add",
                               onSelect: { selected = d.id },
                               onActivate: { if let host { store.addEffect(d.id, to: host) } })
                }
            }
        }
    }

    private func hostDescription(_ host: EffectHost?) -> String {
        switch host {
        case .clip?: return "Double-click adds to the selected clip. Or drag onto any clip, track or composition tab."
        case .track(let c, let t)?:
            let name = store.project.composition(c)?.tracks.first { $0.id == t }?.name ?? "track"
            return "Double-click adds to \(name). Or drag onto any clip, track or composition tab."
        case .composition(let id)?:
            return "Double-click adds to the whole \(store.project.asset(id)?.name ?? "composition"). Or drag it onto something."
        case nil: return "Drag onto a clip, track or composition tab."
        }
    }

    private func matches(_ s: String) -> Bool {
        search.isEmpty || s.localizedCaseInsensitiveContains(search)
            || search.lowercased().split(separator: " ").allSatisfy { s.lowercased().contains($0) }
            || (search.lowercased().contains("drum") && s == "Drums")
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Space": return "sparkles"
        case "Modulation": return "waveform.path"
        case "Dynamics": return "gauge.with.dots.needle.33percent"
        case "EQ & Filter": return "slider.horizontal.below.square.filled.and.square"
        case "Distortion": return "flame"
        default: return "dial.medium"
        }
    }
}

struct BrowserRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let payload: DragPayload
    var selected = false
    var actionLabel = "Add"
    let onSelect: () -> Void
    let onActivate: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.small).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.tiny).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            Spacer()
            if hover || selected {
                Button(actionLabel, action: onActivate)
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(selected ? Theme.accent.opacity(0.22) : (hover ? Color.white.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onActivate)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .shawDraggable(payload, preview: title)
    }
}
