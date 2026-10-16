import Foundation
import SwiftUI

enum PanelKind: String, Codable, CaseIterable, Identifiable {
    case project, browser, inspector, timeline, session, pianoRoll, beatMaker, mixer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .project: return "Project"
        case .browser: return "Browser"
        case .inspector: return "Effect Controls"
        case .timeline: return "Timeline"
        case .session: return "Session (clip launcher)"
        case .pianoRoll: return "Piano Roll"
        case .beatMaker: return "Beat Maker"
        case .mixer: return "Mixer"
        }
    }

    var icon: String {
        switch self {
        case .project: return "folder"
        case .browser: return "magnifyingglass"
        case .inspector: return "slider.horizontal.3"
        case .timeline: return "rectangle.split.3x1"
        case .session: return "square.grid.3x3"
        case .pianoRoll: return "pianokeys"
        case .beatMaker: return "circle.grid.3x3.fill"
        case .mixer: return "slider.vertical.3"
        }
    }

    /// Panels offered in menus (the old Beat Maker is retired: drums live in the piano roll).
    static var available: [PanelKind] { allCases.filter { $0 != .beatMaker } }

    /// Where a panel goes if it isn't open anywhere yet.
    var defaultSlot: SlotID {
        switch self {
        case .project: return .leftTop
        case .browser: return .leftBottom
        case .inspector: return .right
        case .timeline, .session: return .center
        case .pianoRoll, .beatMaker, .mixer: return .bottom
        }
    }
}

enum SlotID: String, Codable, CaseIterable {
    case leftTop, leftBottom, center, bottom, right

    var title: String {
        switch self {
        case .leftTop: return "Top Left"
        case .leftBottom: return "Bottom Left"
        case .center: return "Center"
        case .bottom: return "Bottom"
        case .right: return "Right"
        }
    }
}

struct PanelSlot: Codable, Equatable {
    var tabs: [PanelKind]
    var active: PanelKind?
}

/// The panel arrangement. Every panel lives in a tabbed slot and can be moved
/// to any other slot, like panel groups in After Effects.
struct Workspace: Codable, Equatable {
    var slots: [SlotID: PanelSlot]
    var showLeft = true
    var showRight = true
    var showBottom = true

    static let standard = Workspace(slots: [
        .leftTop: PanelSlot(tabs: [.project], active: .project),
        .leftBottom: PanelSlot(tabs: [.browser], active: .browser),
        .center: PanelSlot(tabs: [.timeline], active: .timeline),
        .bottom: PanelSlot(tabs: [.pianoRoll, .mixer], active: .pianoRoll),
        .right: PanelSlot(tabs: [.inspector], active: .inspector),
    ])

    static let key = "ShawWorkspace.v2"

    static func load() -> Workspace {
        guard let d = UserDefaults.standard.data(forKey: key), var w = try? JSONDecoder().decode(Workspace.self, from: d) else {
            return .standard
        }
        w.close(.beatMaker)
        return w
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Workspace.key) }
    }

    func slot(_ id: SlotID) -> PanelSlot { slots[id] ?? PanelSlot(tabs: [], active: nil) }

    func location(of kind: PanelKind) -> SlotID? { slots.first { $0.value.tabs.contains(kind) }?.key }

    func isVisible(_ kind: PanelKind) -> Bool {
        guard let s = location(of: kind), slot(s).active == kind else { return false }
        switch s {
        case .leftTop, .leftBottom: return showLeft
        case .right: return showRight
        case .bottom: return showBottom
        case .center: return true
        }
    }

    /// Bring a panel to the front, opening it in its default slot if needed.
    mutating func reveal(_ kind: PanelKind) {
        let s = location(of: kind) ?? kind.defaultSlot
        var slot = self.slot(s)
        if !slot.tabs.contains(kind) { slot.tabs.append(kind) }
        slot.active = kind
        slots[s] = slot
        switch s {
        case .leftTop, .leftBottom: showLeft = true
        case .right: showRight = true
        case .bottom: showBottom = true
        case .center: break
        }
    }

    mutating func activate(_ kind: PanelKind, in s: SlotID) {
        slots[s]?.active = kind
    }

    mutating func close(_ kind: PanelKind) {
        guard let s = location(of: kind) else { return }
        var slot = self.slot(s)
        slot.tabs.removeAll { $0 == kind }
        if slot.active == kind { slot.active = slot.tabs.first }
        slots[s] = slot
    }

    mutating func move(_ kind: PanelKind, to target: SlotID) {
        close(kind)
        var slot = self.slot(target)
        slot.tabs.append(kind)
        slot.active = kind
        slots[target] = slot
        reveal(kind)
    }
}
