import SwiftUI

enum Theme {
    static let bg = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let panel = Color(red: 0.145, green: 0.145, blue: 0.155)
    static let panelHeader = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let lane = Color(red: 0.165, green: 0.165, blue: 0.175)
    static let laneAlt = Color(red: 0.155, green: 0.155, blue: 0.165)
    static let beyondEnd = Color(red: 0.09, green: 0.09, blue: 0.095)
    static let gridBar = Color.white.opacity(0.13)
    static let gridBeat = Color.white.opacity(0.06)
    static let gridSub = Color.white.opacity(0.025)
    static let text = Color(white: 0.86)
    static let textDim = Color(white: 0.55)
    static let textFaint = Color(white: 0.38)
    static let accent = Color(red: 0.25, green: 0.56, blue: 1.0)
    static let playhead = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let record = Color(red: 0.95, green: 0.27, blue: 0.27)
    static let selection = Color.white
    static let border = Color.black.opacity(0.55)
    static let control = Color(white: 0.22)
    static let controlHi = Color(white: 0.3)
    static let mute = Color(red: 0.95, green: 0.65, blue: 0.2)
    static let solo = Color(red: 0.3, green: 0.6, blue: 1.0)
    static let loopRegion = Color(red: 0.95, green: 0.6, blue: 0.2)

    /// After Effects-style label colors.
    static let labels: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 0.95), // blue
        Color(red: 0.93, green: 0.43, blue: 0.40), // red
        Color(red: 0.91, green: 0.74, blue: 0.30), // yellow
        Color(red: 0.42, green: 0.80, blue: 0.53), // green
        Color(red: 0.70, green: 0.48, blue: 0.92), // purple
        Color(red: 0.95, green: 0.58, blue: 0.30), // orange
        Color(red: 0.36, green: 0.80, blue: 0.85), // aqua
        Color(red: 0.92, green: 0.50, blue: 0.75), // pink
        Color(red: 0.62, green: 0.80, blue: 0.36), // lime
        Color(red: 0.55, green: 0.62, blue: 0.72), // slate
        Color(red: 0.80, green: 0.62, blue: 0.45), // sand
        Color(red: 0.50, green: 0.45, blue: 0.95), // violet
    ]

    static let labelNames = ["Blue", "Red", "Yellow", "Green", "Purple", "Orange", "Aqua", "Pink", "Lime", "Slate", "Sand", "Violet"]

    static func label(_ i: Int) -> Color { labels[((i % labels.count) + labels.count) % labels.count] }

    static let mono = Font.system(size: 11, design: .monospaced)
    static let small = Font.system(size: 11)
    static let tiny = Font.system(size: 10)
    static let header = Font.system(size: 11, weight: .semibold)
}

extension Color {
    func darker(_ amount: Double = 0.3) -> Color {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .gray
        return Color(red: ns.redComponent * (1 - amount), green: ns.greenComponent * (1 - amount), blue: ns.blueComponent * (1 - amount))
    }
}

/// Small rounded toggle button used for mute/solo/loop etc.
struct ToggleChip: View {
    let label: String
    let on: Bool
    var color: Color = Theme.accent
    var width: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .frame(width: width, height: 15)
                .foregroundStyle(on ? Color.black : Theme.textDim)
                .background(RoundedRectangle(cornerRadius: 3).fill(on ? color : Theme.control))
        }
        .buttonStyle(.plain)
    }
}

/// Toolbar icon button.
struct IconButton: View {
    let systemName: String
    var active = false
    var help: String = ""
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: 24, height: 22)
                .foregroundStyle(active ? Theme.accent : Theme.text)
                .background(RoundedRectangle(cornerRadius: 4).fill(active ? Theme.accent.opacity(0.18) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
