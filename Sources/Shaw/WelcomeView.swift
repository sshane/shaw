import SwiftUI

/// First-launch quick start: three short pages on what's different about Shaw.
/// Back on the left, Next (blue) on the right. Reopen from Help → Welcome to Shaw.
struct WelcomeView: View {
    @Environment(Store.self) private var store
    @State private var page = min(2, max(0, Int(ProcessInfo.processInfo.environment["SHAW_WELCOME_PAGE"] ?? "") ?? 0))

    private struct Point { let icon: String; let title: String; let text: String }
    private struct Page { let icon: String; let title: String; let subtitle: String; let points: [Point] }

    private let pages: [Page] = [
        Page(icon: "rectangle.split.3x1", title: "Everything happens on one timeline",
             subtitle: "No separate arrangement and session views — looping is built into the top of the timeline.",
             points: [
                Point(icon: "repeat", title: "The loop bar",
                      text: "The orange bar above the timeline loops that section. Click it to turn looping on or off, drag its ends to resize it, or click any bar to loop just that bar."),
                Point(icon: "music.note", title: "Loop, tweak, save variations",
                      text: "Opening a clip loops it. Change notes while it plays, then Save Variation (⇧⌘D) to keep that version and continue on a copy right after it. Loop All plays them in a row."),
                Point(icon: "keyboard", title: "Your keyboard is a piano",
                      text: "A S D F… play the current instrument, W E T Y… are the black keys, Z / X change octave, C / V softer / harder. On drums, A is the kick, S the snare."),
             ]),
        Page(icon: "link", title: "Clips are linked, like After Effects",
             subtitle: "A clip is a placement of something — copies point at the same notes.",
             points: [
                Point(icon: "link", title: "Edit one, change them all",
                      text: "Duplicate a clip (⌘D or ⌥-drag) and every copy shares the same notes. Make Unique (⇧⌘U) gives one its own copy. Merge (⌘J) joins clips on a layer into one."),
                Point(icon: "square.stack.3d.up", title: "Compositions inside compositions",
                      text: "Pre-compose (⇧⌘C) groups clips into a composition you can place like a single clip anywhere — every use stays linked."),
                Point(icon: "pianokeys", title: "One editor for everything",
                      text: "Melodies and drums both live in the piano roll (drums can flip to a step grid). Double-click to add a note, double-click a note to delete it."),
             ]),
        Page(icon: "slider.horizontal.3", title: "Effects on anything, with keyframes",
             subtitle: "Search the Browser (\"reverb\") and drag an effect onto whatever should have it.",
             points: [
                Point(icon: "square.3.layers.3d", title: "Clip, layer or composition",
                      text: "Effects on a clip affect just that clip; on a layer, everything on it; on a composition, everything inside it — applied last, like an adjustment layer."),
                Point(icon: "doc.on.doc", title: "Select, copy, paste",
                      text: "Click an effect's name to select it, ⌘A for all of them, ⌘C, then select other clips or layers and ⌘V. Drag an effect's name to reorder it."),
                Point(icon: "stopwatch", title: "Keyframes",
                      text: "Click a setting's stopwatch, then change it at different spots — ◆ diamonds appear under the layer. Drag them to adjust. Right-click a clip for a quick Fade In / Fade Out."),
             ]),
    ]

    var body: some View {
        let p = pages[page]
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
            .frame(maxHeight: .infinity, alignment: .top)

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
        .frame(width: 600, height: 450)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}
