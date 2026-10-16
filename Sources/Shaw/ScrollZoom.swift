import AppKit
import SwiftUI

/// Routes trackpad/mouse scroll and pinch events to a SwiftUI view region.
/// Using an event monitor (instead of ScrollView) lets the ruler, track headers
/// and lanes all share one scroll position and supports zooming around the cursor.
final class ScrollZoomMonitor {
    private var monitor: Any?
    var frame: CGRect = .zero // in SwiftUI global (window, top-left origin) coordinates
    var onScroll: ((CGFloat, CGFloat, CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onMagnify: ((CGFloat, CGPoint) -> Void)?
    /// Right-click inside the region (consumed only if the handler returns true).
    var onRightClick: ((CGPoint) -> Bool)?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .rightMouseDown]) { [weak self] e in
            guard let self, let window = e.window, let content = window.contentView else { return e }
            let p = CGPoint(x: e.locationInWindow.x, y: content.bounds.height - e.locationInWindow.y)
            guard self.frame.contains(p) else { return e }
            let local = CGPoint(x: p.x - self.frame.minX, y: p.y - self.frame.minY)
            if e.type == .rightMouseDown {
                return (self.onRightClick?(local) ?? false) ? nil : e
            }
            if e.type == .magnify {
                self.onMagnify?(e.magnification, local)
            } else {
                var dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
                if !e.hasPreciseScrollingDeltas { dx *= 12; dy *= 12 }
                self.onScroll?(dx, dy, local, e.modifierFlags)
            }
            return nil
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    deinit { remove() }
}

struct FrameReporter: View {
    let onChange: (CGRect) -> Void
    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { onChange(g.frame(in: .global)) }
                .onChange(of: g.frame(in: .global)) { _, f in onChange(f) }
        }
    }
}

/// Diagonal hatch used for "past the end of the content" regions.
struct Hatch: Shape {
    var spacing: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

extension NSCursor {
    static func set(_ c: NSCursor, when inside: Bool) {
        if inside { c.push() } else { NSCursor.pop() }
    }
}
