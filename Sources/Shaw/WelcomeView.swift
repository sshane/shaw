import SwiftUI

/// First-launch quick start: three short pages on what's different about Shaw.
/// Back on the left, Next (blue) on the right. Reopen from Help → Welcome to Shaw.
struct WelcomeView: View {
    @Environment(Store.self) private var store
    @State private var page = min(2, max(0, Int(ProcessInfo.processInfo.environment["SHAW_WELCOME_PAGE"] ?? "") ?? 0))

    private struct Point { let icon: String; let title: String; let text: String }
    private struct Page { let icon: String; let title: String; let subtitle: String; let points: [Point] }

    private let pages: [Page] = [
        Page(icon: "square.stack.3d.up", title: "The building blocks",
             subtitle: "Everything in Shaw is made of three things: clips, layers, and compositions.",
             points: [
                Point(icon: "rectangle.fill", title: "Clip",
                      text: "A clip is a block on the timeline that holds notes, drums, or audio. Double-click it to edit its notes in the piano roll. When you duplicate a clip, every copy shares the same notes, so editing one changes them all. Make Unique (⇧⌘U) splits one off."),
                Point(icon: "line.3.horizontal", title: "Layer",
                      text: "A layer is a row on the timeline. Layers play at the same time, so drums can go on one, bass on another, and chords on a third. Each layer has its own volume, mute, solo, and effects."),
                Point(icon: "square.stack.3d.up", title: "Composition",
                      text: "A composition is a group of layers or clips. Your song is a composition, and you can put compositions inside each other, like a precomp in After Effects. Pre-compose (⇧⌘C) turns the clips you select into one."),
             ]),
        Page(icon: "rectangle.split.3x1", title: "Everything happens on one timeline",
             subtitle: "There's no separate session view. Looping lives at the top of the timeline.",
             points: [
                Point(icon: "repeat", title: "The loop bar",
                      text: "The orange bar at the top loops that part of the song. Click it to turn looping on or off. Drag its ends to resize it, or click any bar to loop just that one."),
                Point(icon: "music.note", title: "Loop, tweak, save variations",
                      text: "Open a clip and it loops. Change notes while it plays. When you like it, hit Save Variation (⇧⌘D). Shaw keeps that version and puts a copy right after it so you can keep going. Loop All plays them back to back."),
                Point(icon: "keyboard", title: "Your keyboard is a piano",
                      text: "A S D F and the rest of that row play the current instrument, and W E T Y U O P are the black keys. Z and X change the octave, and C and V change how hard you hit. On drums, A is the kick and S is the snare."),
             ]),
        Page(icon: "slider.horizontal.3", title: "Effects on anything, with keyframes",
             subtitle: "Search the Browser for something like \"reverb\" and drag it where you want it.",
             points: [
                Point(icon: "square.3.layers.3d", title: "Clip, layer, or composition",
                      text: "An effect on a clip only changes that clip. On a layer, it changes everything on the layer. On a composition, it runs after everything inside it, so one reverb or filter sweep can cover a whole drop everywhere you use it."),
                Point(icon: "doc.on.doc", title: "Select, copy, paste",
                      text: "Click an effect's name to select it, or press ⌘A to grab them all. Press ⌘C, select other clips or layers, then press ⌘V. Drag an effect's name to reorder it."),
                Point(icon: "stopwatch", title: "Keyframes",
                      text: "Click the stopwatch next to a setting, then change it at different points in the song. Diamonds (◆) show up under the layer, and you can drag them around. Right-click a clip for a quick fade in or fade out."),
             ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Every page is laid out, only the current one is visible: the window fits the
            // longest page and stays the same size while you click through, with no dead space.
            ZStack(alignment: .topLeading) {
                ForEach(pages.indices, id: \.self) { i in
                    pageContent(pages[i])
                        .opacity(i == page ? 1 : 0)
                        .accessibilityHidden(i != page)
                }
            }

            HStack {
                Button("Back") { withAnimation(.easeOut(duration: 0.15)) { page -= 1 } }
                    .opacity(page == 0 ? 0 : 1)
                    .disabled(page == 0)
                Spacer()
                if page == pages.count - 1 && !store.hasContent {
                    Button("Open Demo Song") {
                        store.dismissWelcome()
                        store.openDemo()
                    }
                }
                Button(page == pages.count - 1 ? "Get Started" : "Next") {
                    if page == pages.count - 1 { store.dismissWelcome() } else { withAnimation(.easeOut(duration: 0.15)) { page += 1 } }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .controlSize(.large)
            .overlay {
                // Page dots, centered regardless of which buttons are showing.
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle().fill(i == page ? Theme.accent : Theme.textFaint.opacity(0.6)).frame(width: 7, height: 7)
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.top, 18)
        }
        .padding(26)
        .frame(width: 600)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }

    private func pageContent(_ p: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.18)).frame(width: 46, height: 46)
                    Image(systemName: p.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                    Text(p.subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(p.points, id: \.title) { pt in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pt.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24, height: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pt.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(pt.text).font(.system(size: 12.5)).foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
