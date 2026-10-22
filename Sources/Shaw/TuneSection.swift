import ShawCore
import SwiftUI

/// Tune, for a recording: pitch correction in a few controls. A style sets everything at once
/// (Natural for evening out a take, Robot for the hard effect), and the sliders fine-tune it.
struct TuneSection: View {
    @Environment(Store.self) private var store
    let assetID: AssetID
    @State private var showMore = false

    static let amount = ParamDef("amount", "Strength", 0, 1, VocalTune.natural.amount, .percent)
    static let speed = ParamDef("speed", "Speed", 0, 200, VocalTune.natural.speed, .ms)
    static let vibrato = ParamDef("vibrato", "Vibrato", 0, 2, VocalTune.natural.vibrato, .percent)
    static let straighten = ParamDef("straighten", "Straighten", 0, 1, VocalTune.natural.straighten, .percent)
    static let styles: [(String, VocalTune, String)] = [
        ("Natural", .natural, "Evens out the pitch and keeps the vibrato and slides as sung"),
        ("Tight", .tight, "Every note right on pitch, still sounding human"),
        ("Robot", .robot, "The hard, stepping effect"),
    ]

    var body: some View {
        if case .audio(let ref)? = store.project.asset(assetID)?.content {
            let tune = ref.tune ?? VocalTune()
            let on = ref.tune?.enabled ?? false
            header(on: on, path: ref.path)
            if on {
                controls(tune, path: ref.path)
            } else {
                Text("Corrects the pitch of a voice or instrument, keeping the way it was sung.")
                    .font(Theme.tiny).foregroundStyle(Theme.textFaint).padding(.horizontal, 10)
            }
        }
    }

    private func header(on: Bool, path: String) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { on }, set: { v in set { $0.enabled = v } }))
                .toggleStyle(.checkbox).labelsHidden().controlSize(.small)
            Text("TUNE").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint)
            Spacer()
            // Reading the load counter redraws this when a new version is ready.
            if on && store.samplesLoaded >= 0 && SampleLibrary.shared.tunes.isRendering(path) {
                Text("Tuning…").font(Theme.tiny).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
        .help("Pitch correction for this recording")
    }

    @ViewBuilder private func controls(_ tune: VocalTune, path: String) -> some View {
        row("Style") {
            HStack(spacing: 2) {
                ForEach(Self.styles, id: \.0) { name, preset, help in
                    let current = tune.hasStyle(of: preset)
                    Button(name) { set { $0 = $0.styled(like: preset) } }
                        .buttonStyle(.plain).font(Theme.small)
                        .foregroundStyle(current ? Theme.text : Theme.textDim)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(current ? Theme.accent.opacity(0.45) : Theme.control))
                        .help(help)
                }
            }
        }
        row("Key") { keyMenu(tune, path: path) }
        slider(Self.amount, tune.amount) { $0.amount = $1 }
        slider(Self.speed, tune.speed) { $0.speed = $1 }
        Button(showMore ? "Less" : "More (2)") { showMore.toggle() }
            .buttonStyle(.plain).font(Theme.tiny).foregroundStyle(Theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 2)
        if showMore {
            slider(Self.vibrato, tune.vibrato) { $0.vibrato = $1 }
            slider(Self.straighten, tune.straighten) { $0.straighten = $1 }
        }
    }

    /// A row lined up with the sliders' labels.
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.small).foregroundStyle(Theme.textDim).frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .padding(.horizontal, 10)
    }

    private func slider(_ def: ParamDef, _ value: Double, _ apply: @escaping (inout VocalTune, Double) -> Void) -> some View {
        ParamRow(def: def, value: value, onChange: { v in set(live: true) { apply(&$0, def.clamp(v)) } }, onEnd: { store.endGesture() })
            .padding(.horizontal, 10)
            .help(Self.help(def.id))
    }

    static func help(_ id: String) -> String {
        switch id {
        case "amount": return "How far each note moves toward the right pitch"
        case "speed": return "How quickly a note settles on pitch. Slower sounds more natural; 0 is the robot effect."
        case "vibrato": return "Keep the vibrato as sung (100%), flatten it (0%), or deepen it"
        default: return "Smooth out slow wandering within each note"
        }
    }

    private func keyMenu(_ tune: VocalTune, path: String) -> some View {
        let auto = store.project.songKey ?? (store.samplesLoaded >= 0 ? SampleLibrary.shared.tunes.takeKey(path) : nil)
        let label: String = switch tune.scale {
        case .auto: auto.map { "Auto (\($0.name))" } ?? "Auto"
        case .chromatic: "Any note"
        case .major, .minor: VocalTune.Key(root: tune.root ?? 0, minor: tune.scale == .minor).name
        }
        return Menu {
            Button(auto.map { "Auto (\($0.name))" } ?? "Auto") { set { $0.scale = .auto; $0.root = nil } }
            Button("Any note (no key)") { set { $0.scale = .chromatic; $0.root = nil } }
            Divider()
            ForEach([false, true], id: \.self) { minor in
                Menu(minor ? "Minor" : "Major") {
                    ForEach(0..<12, id: \.self) { root in
                        Button(VocalTune.Key(root: root, minor: minor).name) { set { $0.scale = minor ? .minor : .major; $0.root = root } }
                    }
                }
            }
        } label: {
            Text(label).font(Theme.small).foregroundStyle(Theme.accent)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Notes move to the nearest note in this key. Auto uses the song's key, from its notes (or the recording's own, if the song has none).")
    }

    private func set(live: Bool = false, _ change: @escaping (inout VocalTune) -> Void) {
        let id = assetID
        let body: (inout Project) -> Void = { p in
            p.updateAsset(id) { a in
                guard case .audio(var r) = a.content else { return }
                var t = r.tune ?? VocalTune()
                change(&t)
                r.tune = t
                a.content = .audio(r)
            }
        }
        if live { store.live(body) } else { store.edit(body) }
    }
}
