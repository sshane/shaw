import ShawCore
import SwiftUI

struct ClipSegment {
    var t0: Double, t1: Double     // clip-local beats
    var s0: Double, s1: Double     // source beats
    var empty: Bool                // past the end, not looping
    var loopStart: Bool            // segment begins at a loop repeat
}

/// Split a clip into the pieces that show source content, repeats, or silence.
func clipSegments(offset: Double, length: Double, loops: Bool, sourceLength L: Double) -> [ClipSegment] {
    let L = max(L, 1e-6)
    var out: [ClipSegment] = []
    var t = 0.0
    var src = loops ? offset.truncatingRemainder(dividingBy: L) : offset
    var first = true
    while t < length - 1e-9 && out.count < 512 {
        if !loops && src >= L {
            out.append(ClipSegment(t0: t, t1: length, s0: src, s1: src + length - t, empty: true, loopStart: false))
            break
        }
        let n = min(length - t, L - src)
        out.append(ClipSegment(t0: t, t1: t + n, s0: src, s1: src + n, empty: false, loopStart: !first && src == 0))
        t += n
        src += n
        if loops && src >= L - 1e-9 { src = 0 }
        first = false
    }
    return out
}

/// Draws a miniature of an asset's content (notes, hits, waveform or inner clips).
struct SourceDrawer {
    let project: Project

    func draw(_ ctx: GraphicsContext, assetID: AssetID, rect: CGRect, from s0: Double, to s1: Double, color: Color) {
        guard let a = project.asset(assetID), s1 > s0, rect.width > 1 else { return }
        let span = s1 - s0
        func x(_ b: Double) -> CGFloat { rect.minX + CGFloat((b - s0) / span) * rect.width }
        let ink = color.opacity(0.95)
        switch a.content {
        case .notes(let p):
            guard !p.notes.isEmpty else { return }
            let lo = (p.notes.map(\.pitch).min() ?? 60) - 1, hi = (p.notes.map(\.pitch).max() ?? 72) + 1
            let rows = CGFloat(max(hi - lo, 8))
            let h = max(1.5, min(5, rect.height / rows))
            for n in p.notes where n.end > s0 && n.start < s1 && n.start < p.length {
                let x0 = max(rect.minX, x(n.start)), x1 = min(rect.maxX, x(min(n.end, p.length)))
                let y = rect.maxY - CGFloat(n.pitch - lo) / rows * rect.height - h / 2
                ctx.fill(Path(CGRect(x: x0, y: y, width: max(1, x1 - x0 - 0.5), height: h)), with: .color(ink))
            }
        case .drums(let d):
            let rows = d.rows.enumerated().filter { _, r in r.steps.contains { $0 > 0 } }
            guard !rows.isEmpty else { return }
            let stepLen = 1.0 / Double(d.stepsPerBeat)
            let rh = rect.height / CGFloat(max(rows.count, 4))
            for (ri, (_, row)) in rows.enumerated() {
                for (si, v) in row.steps.enumerated() where v > 0 {
                    let b = Double(si) * stepLen
                    guard b >= s0 && b < s1 else { continue }
                    let y = rect.minY + CGFloat(ri) * rh
                    let w = max(1.5, min(CGFloat(stepLen / span) * rect.width - 1, 6))
                    ctx.fill(Path(CGRect(x: x(b), y: y + rh * 0.15, width: w, height: rh * 0.7)), with: .color(ink.opacity(0.5 + v * 0.5)))
                }
            }
        case .audio(let f):
            guard let peaks = SampleLibrary.shared.peaks(for: f.path), !peaks.isEmpty else { return }
            let sr = SampleLibrary.shared.sampleRate(for: f.path) ?? f.sampleRate
            let framesPerBeat = sr * 60 / project.bpm
            let mid = rect.midY
            var path = Path()
            let cols = Int(rect.width)
            for c in 0..<max(1, cols) {
                let b0 = s0 + span * Double(c) / Double(cols), b1 = s0 + span * Double(c + 1) / Double(cols)
                let i0 = Int(b0 * framesPerBeat) / SampleLibrary.peakBucket, i1 = max(i0 + 1, Int(b1 * framesPerBeat) / SampleLibrary.peakBucket)
                guard i0 < peaks.count else { break }
                var m: Float = 0
                for i in i0..<min(i1, peaks.count) { m = max(m, peaks[i]) }
                let h = CGFloat(m) * rect.height * 0.5
                path.addRect(CGRect(x: rect.minX + CGFloat(c), y: mid - h, width: 1, height: max(0.5, h * 2)))
            }
            ctx.fill(path, with: .color(ink))
        case .composition(let c):
            let n = max(c.tracks.count, 1)
            let rh = rect.height / CGFloat(max(n, 3))
            for (ti, t) in c.tracks.enumerated() {
                for k in t.clips where k.end > s0 && k.start < s1 {
                    let x0 = max(rect.minX, x(k.start)), x1 = min(rect.maxX, x(k.end))
                    let r = CGRect(x: x0, y: rect.minY + CGFloat(ti) * rh + 1, width: max(1, x1 - x0 - 1), height: max(1, rh - 2))
                    ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(Theme.label(project.asset(k.assetID)?.colorIndex ?? 0).opacity(0.9)))
                }
            }
        }
    }
}
