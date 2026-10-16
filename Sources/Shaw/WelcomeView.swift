import SwiftUI

/// First-launch quick start: what's different about Shaw, in six short cards.
struct WelcomeView: View {
    @Environment(Store.self) private var store

    private let points: [(icon: String, title: String, text: String)] = [
        ("link", "Copies stay linked",
         "Duplicate a clip and both copies share the same notes — edit one, they all change, like footage in After Effects. Make Unique (⇧⌘U) when you want them separate."),
        ("square.stack.3d.up", "Compositions inside compositions",
         "Group clips into a composition (Pre-compose, ⇧⌘C) and use it like a single clip anywhere. Effects on a composition apply after everything inside it."),
        ("slider.horizontal.3", "Effects on anything, with keyframes",
         "Drop effects on a clip, a layer or a whole composition. Click a setting's stopwatch to keyframe it — ◆ diamonds, just like After Effects."),
        ("repeat", "Loop, tweak, save variations",
         "Opening a clip loops it. Change notes while it plays, then Save Variation (⇧⌘D) to keep that version and keep going — no recording needed."),
        ("keyboard", "Your keyboard is a piano",
         "A S D F… play the current instrument, W E T Y… are the black keys, Z / X change octave. Drums too: A is the kick, S the snare."),
        ("pianokeys", "One editor for everything",
         "Melodies and drums both live in the piano roll (drums can flip to a step grid). Double-click to add a note, double-click to delete."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Shaw").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
                    Text("A few things work differently from other music apps:")
                        .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(points, id: \.title) { p in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: p.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(p.text).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack {
                Text("Reopen this anytime from the Help menu.").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                Spacer()
                if !store.hasContent {
                    Button("Open the Demo Song") {
                        store.dismissWelcome()
                        store.openDemo()
                    }
                }
                Button("Get Started") { store.dismissWelcome() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(24)
        .frame(width: 680)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}
