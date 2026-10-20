import Accelerate
import XCTest
@testable import ShawCore
@testable import Shaw

/// An engineer's analyzer for the demo songs: octave-band balance, stereo width, and how squashed
/// the drop is. Finished EDM falls off a few dB per octave from bass to treble; big bumps mean
/// boom or mud, and a tiny crest factor means the master is crushing the mix.
enum MixReport {
    static let centers = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    /// Average power per octave band, in dB.
    static func bands(_ x: [Float]) -> [Double] {
        let n = 8192, log2n = vDSP_Length(13)
        guard x.count > n, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return centers.map { _ in -200 } }
        defer { vDSP_destroy_fftsetup(setup) }
        var acc = [Double](repeating: 0, count: n / 2)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var frames = 0
        for start in stride(from: 0, to: x.count - n, by: n / 2) {
            var seg = Array(x[start..<start + n])
            vDSP_vmul(seg, 1, window, 1, &seg, 1, vDSP_Length(n))
            var re = [Float](repeating: 0, count: n / 2), im = [Float](repeating: 0, count: n / 2)
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    seg.withUnsafeBufferPointer { sp in
                        sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    for k in 0..<n / 2 { acc[k] += Double(rp[k] * rp[k] + ip[k] * ip[k]) }
                }
            }
            frames += 1
        }
        let binHz = 48000.0 / Double(n)
        return centers.map { c in
            var e = 0.0
            for k in Int(c / sqrt(2) / binHz)...min(n / 2 - 1, Int(c * sqrt(2) / binHz)) { e += acc[k] }
            return 10 * log10(e / Double(frames) + 1e-20)
        }
    }

    struct Result {
        var tilt: [Double] = []   // mid bands relative to 1 kHz
        var side: [Double] = []   // side bands relative to mid 1 kHz
        var crest = 0.0
        var text = ""
    }

    static func analyze(_ p: Project, from b0: Double, to b1: Double) -> Result {
        let (l, r) = OfflineRenderer.renderToMemory(project: p, composition: p.mainCompositionID, beats: b1)
        let fpb = 48000 * 60 / p.bpm
        let a = Int(b0 * fpb), b = min(l.count, Int(b1 * fpb))
        let bm = bands((a..<b).map { (l[$0] + r[$0]) / 2 }), bs = bands((a..<b).map { (l[$0] - r[$0]) / 2 })
        let ref = bm[5]
        var res = Result()
        res.tilt = bm.map { $0 - ref }
        res.side = bs.map { $0 - ref }
        var crests: [Double] = []
        for s in stride(from: a, to: b - 2400, by: 2400) {
            var pk: Float = 0, sum: Float = 0
            for i in s..<s + 2400 { pk = max(pk, abs(l[i])); sum += l[i] * l[i] }
            crests.append(20 * log10(Double(pk) / Double(sqrt(sum / 2400) + 1e-9) + 1e-9))
        }
        res.crest = crests.sorted()[crests.count / 2]
        res.text = "\(p.name) bars \(Int(b0 / 4) + 1)–\(Int(b1 / 4)):\n"
        for (i, c) in centers.enumerated() { res.text += String(format: "  %6.0f Hz  %+6.1f   side %+6.1f\n", c, res.tilt[i], res.side[i]) }
        res.text += String(format: "  crest factor %.1f dB\n", res.crest)
        return res
    }
}

final class MixReportTests: XCTestCase {
    /// Drops shouldn't be boomy (63–250 Hz way above the mids), hollow, mono, or crushed.
    func testDemoDropsAreBalanced() {
        for (p, b0, b1) in [(DemoProject.starlightFM(), 32.0, 96.0), (DemoProject.glasswing(), 64.0, 128.0),
                           (DemoProject.sunroom(), 64.0, 96.0)] {
            let m = MixReport.analyze(p, from: b0, to: b1)
            print(m.text)
            XCTAssertLessThan(m.tilt[1], 13, "\(p.name): too much boom at 63 Hz")
            XCTAssertLessThan(m.tilt[3], 7, "\(p.name): muddy at 250 Hz")
            XCTAssertGreaterThan(m.crest, 6.5, "\(p.name): the master is crushing the drop")
            XCTAssertGreaterThan(m.side[5], -18, "\(p.name): almost mono in the mids")
        }
    }
}
