import AppKit
import ShawCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
                    DebugSnapshot.runIfRequested(store)
                }
        }
        .defaultSize(width: 1520, height: 960)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { ShawCommands(store: store) }
    }
}

struct ShawCommands: Commands {
    let store: Store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") { store.newProject() }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Open Demo Project") { store.openDemo() }
            Button("Open…") { store.openDialog() }.keyboardShortcut("o")
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
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Duplicate") { KeyRouter.shared.duplicate() }.keyboardShortcut("d")
            Button("Split at Playhead") { store.splitSelectedClips(at: store.transport.position) }.keyboardShortcut("e")
        }
        CommandMenu("Composition") {
            Button("New Composition") { store.openComposition(store.newComposition()) }.keyboardShortcut("n")
            Button("New Pattern") { store.open(asset: store.newPattern()) }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("New Beat") { store.open(asset: store.newBeat()) }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("New Track") { store.addTrack() }.keyboardShortcut("t")
            Divider()
            Button("Pre-compose Selection") { store.precomposeSelection() }.keyboardShortcut("c", modifiers: [.command, .shift])
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
            Button("Stop All Session Clips") { store.engine.stopAllSession() }
        }
        CommandGroup(before: .toolbar) {
            Button("Switch Timeline / Session") { KeyRouter.shared.toggleMainView() }
            Button("Zoom In") { store.zoom = min(400, store.zoom * 1.25) }.keyboardShortcut("=")
            Button("Zoom Out") { store.zoom = max(2, store.zoom / 1.25) }.keyboardShortcut("-")
            Button("Zoom to Fit") { store.fitRequest += 1 }.keyboardShortcut("0")
            Divider()
            Button(store.workspace.showLeft ? "Hide Left Panels" : "Show Left Panels") { store.workspace.showLeft.toggle() }
            Button(store.workspace.showBottom ? "Hide Bottom Panel" : "Show Bottom Panel") { store.workspace.showBottom.toggle() }
            Button(store.workspace.showRight ? "Hide Right Panel" : "Show Right Panel") { store.workspace.showRight.toggle() }
            Menu("Show Panel") {
                ForEach(PanelKind.allCases) { k in
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
    var beatMakerHandler: ((NSEvent) -> Bool)?

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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let store = self.store else { return e }
            if NSApp.keyWindow?.firstResponder is NSText { return e }
            return self.handle(e, store) ? nil : e
        }
    }

    private func handle(_ e: NSEvent, _ store: Store) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control])
        if store.focus == .pianoRoll, let h = pianoRollHandler, h(e) { return true }
        if store.focus == .beatMaker, let h = beatMakerHandler, h(e) { return true }
        guard mods.isEmpty else { return false }
        switch e.keyCode {
        case 49: // space
            store.togglePlay()
            return true
        case 51, 117: // delete, forward delete
            switch store.focus {
            case .project: store.deleteAssets(store.selectedAssets)
            case .timeline: store.deleteSelectedClips()
            default: return false // never delete hidden timeline clips from another panel
            }
            return true
        case 48: // tab
            toggleMainView()
            return true
        default:
            return false
        }
    }

    func toggleMainView() {
        guard let store else { return }
        if store.workspace.isVisible(.session) { store.workspace.reveal(.timeline) } else { store.workspace.reveal(.session) }
    }

    func duplicate() {
        guard let store else { return }
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
        if env["SHAW_PLAY"] != nil { store.togglePlay() }
        if env["SHAW_INSPECT_SLOT"] != nil, let comp = store.activeComp,
           let t = comp.tracks.first(where: { !$0.slots.isEmpty }), let scene = t.slots.keys.min() {
            store.updateTrack(t.id) { $0.effects.append(EffectRegistry.descriptor("reverb")!.makeEffect()) }
            store.inspector = .slot(store.activeCompID, t.id, scene)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["SHAW_DELAY"] ?? "") ?? 2.5)) {
            guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let v = w.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
