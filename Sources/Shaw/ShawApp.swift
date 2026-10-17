import AppKit
import ShawCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        // Debug snapshot runs stay in the background so they never grab your keyboard.
        if !Store.isIsolatedLaunch { NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ShawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = Store()

    var body: some Scene {
        Window("Shaw", id: "main") {
            MainView()
                .environment(store)
                .frame(minWidth: 1100, minHeight: 680)
                .preferredColorScheme(.dark)
                .onAppear {
                    KeyRouter.shared.install(store)
                    // Show the whole song on launch once the window has its size.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.fitRequest += 1 }
                    DebugSnapshot.runIfRequested(store)
                }
        }
        .defaultSize(width: 1520, height: 960)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { ShawCommands(store: store) }

        Window(InstrumentEditorView.windowTitle, id: "instrument-editor") {
            InstrumentEditorView()
                .environment(store)
                .frame(minWidth: 640, minHeight: 520)
        }
        .defaultSize(width: 860, height: 720)
        .windowStyle(.titleBar)
    }
}

struct ShawCommands: Commands {
    let store: Store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") { store.newProject() }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Open Demo Song (Starlight FM)") { store.openDemo() }
            Button("Open Demo Song (Neon Drive)") { store.openNeonDriveDemo() }
            Button("Open Demo Song (First Light)") { store.openFirstLightDemo() }
            Button("Open…") { store.openDialog() }.keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(store.recentFiles, id: \.self) { url in
                    Button(store.recentTitle(url)) { store.openRecent(url) }
                }
                Divider()
                Button("Clear Menu") { store.clearRecentFiles() }.disabled(store.recentFiles.isEmpty)
            }
            Divider()
            Button("Import Audio…") { store.importAudioDialog() }.keyboardShortcut("i")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { store.save() }.keyboardShortcut("s")
            Button("Save As…") { store.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Export Audio…") { store.exportAudio() }.keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { store.undo() }.keyboardShortcut("z").disabled(!store.canUndo)
            Button("Redo") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.canRedo)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { KeyRouter.shared.edit(#selector(NSText.cut(_:))) { store.cutSelection() } }.keyboardShortcut("x")
            Button("Copy") { KeyRouter.shared.edit(#selector(NSText.copy(_:))) { store.copySelection() } }.keyboardShortcut("c")
            Button("Paste") { KeyRouter.shared.edit(#selector(NSText.paste(_:))) { store.paste() } }.keyboardShortcut("v")
            Button("Select All") { KeyRouter.shared.selectAll() }.keyboardShortcut("a")
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Duplicate") { KeyRouter.shared.duplicate() }.keyboardShortcut("d")
            Button("Split at Playhead") { store.splitSelectedClips(at: store.transport.position) }.keyboardShortcut("e")
            Button("Save Variation") { store.saveVariation() }.keyboardShortcut("d", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Welcome to Shaw") { store.showWelcome = true }
        }
        CommandMenu("Composition") {
            Button("New Composition") { store.openComposition(store.newComposition()) }.keyboardShortcut("n")
            Button("New Pattern") { store.open(asset: store.newPattern()) }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("New Drum Pattern") { store.open(asset: store.newBeat()) }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("New Track") { store.addTrack() }.keyboardShortcut("t")
            Divider()
            Button("Pre-compose Selection") { store.precomposeSelection() }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Merge Clips into One") { store.mergeSelectedClips() }.keyboardShortcut("j")
                .disabled(store.mergeProblem(store.selectedClips) != nil)
            Button("Make Clip Unique") {
                if let id = store.selectedClips.first { store.makeUnique(id) }
            }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Toggle Loop on Selected Clips") {
                for id in store.selectedClips { store.updateClip(id) { $0.loops.toggle() } }
            }.keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Open Main Composition") { store.openComposition(store.project.mainCompositionID) }
        }
        CommandMenu("Transport") {
            Button(store.transport.playing ? "Stop" : "Play") { store.togglePlay() }
            Button("Return to Start") { store.returnToStart() }.keyboardShortcut(.home, modifiers: [])
            Divider()
            Button(store.loopEnabled ? "Turn Loop Off" : "Turn Loop On") { store.loopEnabled.toggle() }.keyboardShortcut("l")
            Button(store.metronome ? "Metronome Off" : "Metronome On") { store.metronome.toggle() }.keyboardShortcut("k")
            Divider()
            Button(store.keyboardEnabled ? "Turn Off Computer Keyboard Playing" : "Play Instruments with Computer Keyboard") {
                store.keyboardEnabled.toggle()
            }
            Divider()
            Button("Stop All Session Clips") { store.engine.stopAllSession() }
        }
        CommandGroup(before: .toolbar) {
            Button("Zoom In") { store.zoom = min(400, store.zoom * 1.25) }.keyboardShortcut("=")
            Button("Zoom Out") { store.zoom = max(2, store.zoom / 1.25) }.keyboardShortcut("-")
            Button("Zoom to Fit") { store.fitRequest += 1 }.keyboardShortcut("0")
            Divider()
            Button(store.workspace.showLeft ? "Hide Left Panels" : "Show Left Panels") { store.workspace.showLeft.toggle() }
            Button(store.workspace.showBottom ? "Hide Bottom Panel" : "Show Bottom Panel") { store.workspace.showBottom.toggle() }
            Button(store.workspace.showRight ? "Hide Right Panel" : "Show Right Panel") { store.workspace.showRight.toggle() }
            Menu("Show Panel") {
                ForEach(PanelKind.available) { k in
                    Button(k.title) { store.workspace.reveal(k) }
                }
            }
            Button("Reset Workspace") { store.workspace = .standard }
            Divider()
        }
    }
}

/// Global key handling that respects text fields (typing a space in a name shouldn't start playback).
final class KeyRouter {
    static let shared = KeyRouter()
    private var monitor: Any?
    private var clickMonitor: Any?
    weak var store: Store?
    /// Set by the piano roll so arrow keys / delete act on notes when it has focus.
    var pianoRollHandler: ((NSEvent) -> Bool)?

    func install(_ store: Store) {
        self.store = store
        guard monitor == nil else { return }
        // Clicking anywhere that isn't a text field ends text editing, so Space goes back to play/stop.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            guard let window = e.window, let content = window.contentView, window.firstResponder is NSText else { return e }
            let hit = content.hitTest(content.convert(e.locationInWindow, from: nil))
            var v: NSView? = hit
            while let cur = v {
                if cur is NSTextField || cur is NSText { return e }
                v = cur.superview
            }
            window.makeFirstResponder(nil)
            return e
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.keyWindow?.makeFirstResponder(nil) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self, let store = self.store else { return e }
            if NSApp.keyWindow?.firstResponder is NSText { return e }
            if e.type == .keyUp {
                let plain = e.modifierFlags.intersection([.command, .option, .control]).isEmpty
                return plain && store.keyboardKey(e.charactersIgnoringModifiers ?? "", down: false, isRepeat: false) ? nil : e
            }
            return self.handle(e, store) ? nil : e
        }
    }

    private func handle(_ e: NSEvent, _ store: Store) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control])
        if store.focus == .pianoRoll, let h = pianoRollHandler, h(e) { return true }
        guard mods.isEmpty else { return false }
        let chars = (e.charactersIgnoringModifiers ?? "").lowercased()
        if chars == "b" && store.focus == .pianoRoll {
            store.drawMode.toggle() // Ableton's draw-mode key
            return true
        }
        // The computer keyboard plays the current instrument (A–' = notes, Z/X octave, C/V velocity).
        if !e.modifierFlags.contains(.shift), store.keyboardKey(chars, down: true, isRepeat: e.isARepeat) { return true }
        switch e.keyCode {
        case 49: // space
            store.togglePlay()
            return true
        case 51, 117: // delete, forward delete
            switch store.focus {
            case .project: store.deleteAssets(store.selectedAssets)
            case .inspector:
                guard !store.selectedEffects.isEmpty else { return false }
                store.deleteSelectedEffects()
            case .timeline:
                if !store.selectedKeyframes.isEmpty {
                    store.deleteSelectedKeyframes()
                } else if !store.selectedClips.isEmpty {
                    store.deleteSelectedClips()
                } else if case .track(let cid, let tid)? = store.inspector, cid == store.activeCompID {
                    store.deleteTrack(tid) // a selected layer (click its header); ⌘Z brings it back
                } else {
                    return false
                }
            default: return false // never delete hidden timeline clips from another panel
            }
            return true
        default:
            return false
        }
    }

    func toggleMainView() {
        guard let store else { return }
        if store.workspace.isVisible(.session) { store.workspace.reveal(.timeline) } else { store.workspace.reveal(.session) }
    }

    /// Edit-menu commands: text fields get the normal behaviour, everything else goes to Shaw.
    func edit(_ textAction: Selector, _ shaw: () -> Bool) {
        if NSApp.keyWindow?.firstResponder is NSText {
            NSApp.sendAction(textAction, to: nil, from: nil)
            return
        }
        if store?.focus == .pianoRoll, let h = pianoRollHandler, let ev = commandEvent(for: textAction), h(ev) { return }
        if !shaw() { NSSound.beep() }
    }

    func selectAll() {
        guard let store else { return }
        if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil); return }
        switch store.focus {
        case .pianoRoll: if let h = pianoRollHandler, let ev = commandEvent(for: #selector(NSText.selectAll(_:))) { _ = h(ev) }
        case .inspector: store.selectAllEffects()
        case .project: store.selectedAssets = Set(store.project.assets.map(\.id))
        default: store.selectAllClips()
        }
    }

    /// The piano roll handles its own ⌘ keys; synthesize the matching key event for menu clicks.
    private func commandEvent(for action: Selector) -> NSEvent? {
        let map: [Selector: (String, UInt16)] = [
            #selector(NSText.cut(_:)): ("x", 7), #selector(NSText.copy(_:)): ("c", 8),
            #selector(NSText.paste(_:)): ("v", 9), #selector(NSText.selectAll(_:)): ("a", 0),
        ]
        guard let (ch, code) = map[action] else { return nil }
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)
    }

    func duplicate() {
        guard let store else { return }
        if store.focus == .inspector && !store.selectedEffects.isEmpty {
            store.duplicateSelectedEffects()
            return
        }
        if store.focus == .pianoRoll, let h = pianoRollHandler {
            // Synthesize a Cmd-D for the piano roll.
            if let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                         context: nil, characters: "d", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2) {
                _ = h(ev)
            }
            return
        }
        if store.focus == .project {
            for id in store.selectedAssets { store.duplicateAsset(id) }
        } else {
            store.duplicateSelectedClips()
        }
    }
}

/// Developer aid: `SHAW_SNAPSHOT=/path.png` renders the window to a PNG and quits.
/// `SHAW_PANELS=session,beatMaker` reveals panels first.
enum DebugSnapshot {
    static func runIfRequested(_ store: Store) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SHAW_SNAPSHOT"] else { return }
        for name in (env["SHAW_PANELS"] ?? "").split(separator: ",") {
            if let k = PanelKind(rawValue: String(name)) { store.workspace.reveal(k) }
        }
        if let add = env["SHAW_ADD"] {
            for item in add.split(separator: ",") {
                if let c = InstrumentChoice.all.first(where: { $0.id == item }) { store.addInstrument(c) }
            }
        }
        if env["SHAW_FADE"] != nil, let c = store.activeComp?.tracks.first?.clips.first {
            store.updateClip(c.id) { $0.length = 16; $0.loops = true }
            store.addFade(clip: c.id, fadeIn: true)
            store.addFade(clip: c.id, fadeIn: false)
            store.seek(2)
        }
        if env["SHAW_SELECT_LINKED"] != nil, let comp = store.activeComp,
           let c = comp.tracks.flatMap(\.clips).first(where: { store.project.usageCount(of: $0.assetID) > 2 }) {
            store.selectedClips = [c.id]
        }
        // SHAW_EDITOR=scratch builds a new instrument; SHAW_EDITOR=1 edits the newest synth pattern.
        if let mode = env["SHAW_EDITOR"] {
            if mode == "scratch" {
                store.newInstrumentFromScratch()
                if let id = store.instrumentEditorAsset {
                    store.edit { $0.updateNotes(id) { p in
                        p.instrument.params["on2"] = 1; p.instrument.params["osc2"] = 2; p.instrument.params["semi2"] = 12
                        p.instrument.params["lvl2"] = 0.4; p.instrument.params["sub"] = 0.4
                    } }
                }
            } else if let a = store.project.assets.last(where: {
                if case .notes(let p) = $0.content { return !p.instrument.isDrumKit } else { return false }
            }) {
                store.openInstrumentEditor(a.id)
            }
        }
        if env["SHAW_PLAY"] != nil { store.togglePlay() }
        if env["SHAW_INSPECT_SLOT"] != nil, let comp = store.activeComp,
           let t = comp.tracks.first(where: { !$0.slots.isEmpty }), let scene = t.slots.keys.min() {
            store.updateTrack(t.id) { $0.effects.append(EffectRegistry.descriptor("reverb")!.makeEffect()) }
            store.inspector = .slot(store.activeCompID, t.id, scene)
            if env["SHAW_SELECT_FX"] != nil, let fx = store.effects(of: .track(store.activeCompID, t.id)).last {
                store.addEffect("delay", to: .track(store.activeCompID, t.id))
                store.inspector = .slot(store.activeCompID, t.id, scene)
                store.selectEffect(fx.id, in: .track(store.activeCompID, t.id), extend: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["SHAW_DELAY"] ?? "") ?? 2.5)) {
            let sheet = env["SHAW_WELCOME"] != nil ? NSApp.windows.first(where: { $0.isSheet && $0.isVisible })
                : env["SHAW_EDITOR"] != nil ? NSApp.windows.first(where: { $0.title == InstrumentEditorView.windowTitle && $0.isVisible }) : nil
            guard let w = sheet ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let v = w.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
