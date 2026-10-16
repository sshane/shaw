import ShawCore
import SwiftUI

struct MainView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            TransportBar()
            Divider().overlay(Theme.border)
            HSplitView {
                if store.workspace.showLeft {
                    VSplitView {
                        PanelSlotView(slot: .leftTop).frame(minHeight: 140, idealHeight: 340)
                        PanelSlotView(slot: .leftBottom).frame(minHeight: 140)
                    }
                    .frame(minWidth: 220, idealWidth: 290, maxWidth: 460)
                }
                VSplitView {
                    PanelSlotView(slot: .center).frame(minHeight: 180, idealHeight: 420)
                    if store.workspace.showBottom {
                        PanelSlotView(slot: .bottom).frame(minHeight: 150, idealHeight: 300)
                    }
                }
                .frame(minWidth: 480)
                .layoutPriority(1)
                if store.workspace.showRight {
                    PanelSlotView(slot: .right).frame(minWidth: 280, idealWidth: 310, maxWidth: 480)
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle(store.project.name + (store.dirty && store.fileURL != nil ? " — Edited" : ""))
    }
}

// MARK: - Panel slots

struct PanelSlotView: View {
    @Environment(Store.self) private var store
    let slot: SlotID

    var body: some View {
        let s = store.workspace.slot(slot)
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(s.tabs) { tab in
                    PanelTab(kind: tab, active: s.active == tab, slot: slot)
                }
                Spacer(minLength: 0)
                Menu {
                    Section("Add Panel Here") {
                        ForEach(PanelKind.available) { k in
                            Button {
                                store.workspace.move(k, to: slot)
                            } label: {
                                Label(k.title, systemImage: k.icon)
                            }
                        }
                    }
                    Divider()
                    Button("Reset Workspace") { store.workspace = .standard }
                } label: {
                    Image(systemName: "line.3.horizontal").font(.system(size: 10))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 6)
            }
            .frame(height: 24)
            .background(Theme.panelHeader)
            Group {
                if let a = s.active {
                    panel(a)
                } else {
                    Text("Empty panel — use ☰ to add one")
                        .font(Theme.small).foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Theme.panel)
    }

    @ViewBuilder func panel(_ k: PanelKind) -> some View {
        switch k {
        case .project: ProjectPanel()
        case .browser: BrowserPanel()
        case .inspector: InspectorPanel()
        case .timeline: TimelinePanel()
        case .session: SessionPanel()
        case .pianoRoll: PianoRollPanel()
        case .beatMaker: PianoRollPanel()
        case .mixer: MixerPanel()
        }
    }
}

struct PanelTab: View {
    @Environment(Store.self) private var store
    let kind: PanelKind
    let active: Bool
    let slot: SlotID

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon).font(.system(size: 9))
            Text(kind.title).font(.system(size: 11, weight: active ? .semibold : .regular))
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .foregroundStyle(active ? Theme.text : Theme.textDim)
        .background(active ? Theme.panel : Color.clear)
        .overlay(alignment: .top) { if active { Rectangle().fill(Theme.accent).frame(height: 2) } }
        .contentShape(Rectangle())
        .onTapGesture { store.workspace.activate(kind, in: slot) }
        .contextMenu {
            Menu("Move to") {
                ForEach(SlotID.allCases, id: \.self) { s in
                    if s != slot { Button(s.title) { store.workspace.move(kind, to: s) } }
                }
            }
            Button("Close Panel") { store.workspace.close(kind) }
        }
    }
}

// MARK: - Transport bar

struct TransportBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                IconButton(systemName: "backward.end.fill", help: "Return to start (Home)") { store.returnToStart() }
                PlayButton()
                IconButton(systemName: "stop.fill", help: "Stop") { store.stop() }
                IconButton(systemName: "repeat", active: store.loopEnabled, help: "Loop (⌘L)") { store.loopEnabled.toggle() }
                IconButton(systemName: "metronome", active: store.metronome, help: "Metronome (⌘K)") { store.metronome.toggle() }
            }
            // Nothing to play yet: keep the transport visible but clearly inactive.
            .disabled(!store.hasContent)
            .opacity(store.hasContent ? 1 : 0.35)
            PositionDisplay()
            HStack(spacing: 4) {
                DragNumber(value: store.project.bpm, range: 40...300, step: 0.1, sensitivity: 0.2,
                           format: { String(format: "%.1f", $0) },
                           font: .system(size: 13, weight: .semibold, design: .monospaced),
                           onChange: { v in store.live { $0.bpm = v } }, onEnd: { store.endGesture() })
                Text("BPM").font(Theme.tiny).foregroundStyle(Theme.textDim)
            }
            .help("Tempo — drag or double-click to type")
            Menu {
                ForEach([2, 3, 4, 5, 6, 7], id: \.self) { n in
                    Button("\(n)/4") { store.edit { $0.beatsPerBar = n } }
                }
            } label: {
                Text("\(store.project.beatsPerBar)/4").font(Theme.mono)
            }
            .menuStyle(.borderlessButton).fixedSize()

            Divider().frame(height: 18)
            HStack(spacing: 4) {
                Text("Snap").font(Theme.tiny).foregroundStyle(Theme.textDim)
                Picker("", selection: $store.snap) {
                    ForEach(SnapSetting.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .labelsHidden().frame(width: 76).controlSize(.small)
            }
            .disabled(!store.hasContent)
            .opacity(store.hasContent ? 1 : 0.35)
            .help("Grid snap. Hold ⌘ while dragging to move freely.")

            Spacer()

            KeyboardIndicator()

            Spacer()

            HStack(spacing: 2) {
                IconButton(systemName: "sidebar.left", active: store.workspace.showLeft, help: "Left panels") { store.workspace.showLeft.toggle() }
                IconButton(systemName: "rectangle.bottomthird.inset.filled", active: store.workspace.showBottom, help: "Bottom panel") { store.workspace.showBottom.toggle() }
                IconButton(systemName: "sidebar.right", active: store.workspace.showRight, help: "Right panel") { store.workspace.showRight.toggle() }
            }
            MasterMeter().frame(width: 90, height: 8)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Theme.panelHeader)
    }
}

/// Shows what the computer keyboard plays; click to turn it on or off.
struct KeyboardIndicator: View {
    @Environment(Store.self) private var store

    var body: some View {
        let hasTarget = store.keyboardTarget != nil
        Button { store.keyboardEnabled.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "keyboard").font(.system(size: 12))
                Text(store.keyboardEnabled ? store.keyboardLabel : "Keyboard off").font(Theme.small).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 3)
            .foregroundStyle(store.keyboardEnabled && hasTarget ? Theme.text : Theme.textFaint)
            .background(RoundedRectangle(cornerRadius: 5).fill(store.keyboardEnabled && hasTarget ? Theme.accent.opacity(0.18) : Color.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .help("Play the current instrument with your keyboard: A S D F G H J K L = white keys, W E T Y U O P = black keys, Z / X = octave down / up, C / V = softer / harder. Click to turn off.")
    }
}

struct PlayButton: View {
    @Environment(Store.self) private var store
    var body: some View {
        IconButton(systemName: store.transport.playing ? "pause.fill" : "play.fill", active: store.transport.playing,
                   help: "Play / Stop (Space)") { store.togglePlay() }
    }
}

struct PositionDisplay: View {
    @Environment(Store.self) private var store
    var body: some View {
        let pos = store.transport.position
        let secs = pos * 60 / store.project.bpm
        HStack(spacing: 8) {
            Text(formatPosition(pos, beatsPerBar: store.project.beatsPerBar))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.playhead)
                .frame(width: 80, alignment: .leading)
            Text(String(format: "%d:%05.2f", Int(secs) / 60, secs.truncatingRemainder(dividingBy: 60)))
                .font(Theme.mono).foregroundStyle(Theme.textDim)
                .frame(width: 62, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.35)))
    }
}

struct MasterMeter: View {
    @Environment(Store.self) private var store
    var body: some View {
        LevelMeterView(level: store.transport.masterLevel)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .help("Master level")
    }
}
